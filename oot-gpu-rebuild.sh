#!/usr/bin/env bash
# Rebuild NVIDIA out-of-tree GPU modules against the rebuilt kernel's
# Module.symvers. Sanitized derivative of an internal GPU recovery script.
# On R36.5, nvgpu.ko lands at updates/nvgpu.ko — an assertion on
# */gpu/nvgpu/ fails on a successful build.
set -euo pipefail

TARGET_VERMAGIC="${TARGET_VERMAGIC:-5.15.185-tegra-tetragon}"
KERNEL_SRC="${KERNEL_SRC:?set KERNEL_SRC to the rebuilt kernel source (must contain Module.symvers)}"
L4T_SOURCE_DIR="${L4T_SOURCE_DIR:?set L4T_SOURCE_DIR to the unpacked OOT module source root (contains Makefile, nvgpu)}"
OOT_SRC_TARBALL="${OOT_SRC_TARBALL:-}"
NV_DISPLAY_TARBALL="${NV_DISPLAY_TARBALL:-}"
ARTIFACT="${ARTIFACT:?set ARTIFACT to the output tar.gz path}"
STAGE="${STAGE:?set STAGE to a staging directory for modules_install}"
STOCK_MODDIR="${STOCK_MODDIR:-/lib/modules/5.15.185-tegra}"

PHASE="${1:-}"
MODDIR="/lib/modules/${TARGET_VERMAGIC}"

die() { echo "FATAL: $*" >&2; exit 1; }
note() { echo "[*] $*"; }

find_built_ko() {
  find "$1" -type f \( -name '*.ko' -o -name '*.ko.zst' -o -name '*.ko.xz' -o -name '*.ko.gz' \) -print0
}

verify_vermagic() {
  local ko="$1" vm
  vm="$(modinfo -F vermagic "$ko" 2>/dev/null | awk '{print $1}')" || die "modinfo failed on $ko"
  [[ "$vm" == "$TARGET_VERMAGIC" ]] || die "vermagic mismatch on $(basename "$ko"): got '$vm', need '$TARGET_VERMAGIC'"
  note "vermagic OK: $(basename "$ko") = $vm"
}

find_nvgpu() {
  local root="$1"
  find "$root" -type f \( -path '*/updates/nvgpu.ko*' -o -path '*/gpu/nvgpu/nvgpu.ko*' -o -name 'nvgpu.ko*' \) | head -n1
}

build_phase() {
  [[ -f "$KERNEL_SRC/Module.symvers" ]] || die "Module.symvers not found at $KERNEL_SRC"
  note "Using rebuilt kernel tree: $KERNEL_SRC"

  export KERNEL_HEADERS="$KERNEL_SRC"
  unset CROSS_COMPILE

  if [[ ! -d "$L4T_SOURCE_DIR/nvgpu" ]]; then
    [[ -n "$OOT_SRC_TARBALL" && -f "$OOT_SRC_TARBALL" ]] \
      || die "nvgpu missing; set OOT_SRC_TARBALL to kernel_oot_modules_src.tbz2"
    note "Extracting: $OOT_SRC_TARBALL"
    tar -xf "$OOT_SRC_TARBALL" -C "$L4T_SOURCE_DIR"
  fi
  if [[ ! -d "$L4T_SOURCE_DIR/nvdisplay" ]]; then
    [[ -n "$NV_DISPLAY_TARBALL" && -f "$NV_DISPLAY_TARBALL" ]] \
      || die "nvdisplay missing; set NV_DISPLAY_TARBALL to nvidia_kernel_display_driver_source.tbz2"
    note "Extracting: $NV_DISPLAY_TARBALL"
    tar -xf "$NV_DISPLAY_TARBALL" -C "$L4T_SOURCE_DIR"
  fi
  [[ -f "$L4T_SOURCE_DIR/Makefile" ]] || die "OOT Makefile missing under $L4T_SOURCE_DIR"

  note "Building OOT GPU modules (native)"
  cd "$L4T_SOURCE_DIR"
  make modules -j"$(nproc)"
  rm -rf "$STAGE"
  make modules_install INSTALL_MOD_PATH="$STAGE" KERNEL_HEADERS="$KERNEL_SRC"

  local MODROOT="$STAGE/lib/modules/$TARGET_VERMAGIC"
  [[ -d "$MODROOT" ]] || die "staged modules dir not found: $MODROOT"

  note "Verifying vermagic on every staged .ko:"
  local found=0 ko
  while IFS= read -r -d '' ko; do
    verify_vermagic "$ko"
    found=$((found + 1))
  done < <(find_built_ko "$MODROOT")
  [[ "$found" -gt 0 ]] || die "no .ko modules under $MODROOT"

  local nvgpu_ko
  nvgpu_ko="$(find_nvgpu "$MODROOT")"
  [[ -n "$nvgpu_ko" ]] || die "nvgpu.ko not produced"
  # R36.5 modules_install path: updates/nvgpu.ko is success. Do not require */gpu/nvgpu/.
  note "nvgpu: $nvgpu_ko"

  tar -czf "$ARTIFACT" -C "$STAGE/lib/modules" "$TARGET_VERMAGIC"
  note "Artifact: $ARTIFACT"
}

install_phase() {
  [[ "$(id -u)" -eq 0 ]] || die "install needs root"
  [[ "$(uname -r)" == "$TARGET_VERMAGIC" ]] || die "booted $(uname -r), expected $TARGET_VERMAGIC"
  [[ -f "$ARTIFACT" ]] || die "artifact not found: $ARTIFACT"

  note "Installing rebuilt modules only (never copy from $STOCK_MODDIR)"
  tar -xzf "$ARTIFACT" -C /lib/modules/
  [[ -d "$MODDIR" ]] || die "expected $MODDIR after extract"

  note "Re-verifying vermagic on every installed .ko:"
  while IFS= read -r -d '' ko; do
    verify_vermagic "$ko"
  done < <(find_built_ko "$MODDIR")
  [[ -n "$(find_nvgpu "$MODDIR")" ]] || die "nvgpu.ko missing after install"

  depmod -a "$TARGET_VERMAGIC"
  note "depmod done for $TARGET_VERMAGIC"
  echo "REBOOT REQUIRED."
}

smoke_hint() {
  cat <<'EOF'
After reboot:
  lsmod | grep -E 'nvgpu|nvidia'
  ls -l /dev/nvgpu* /dev/nvhost*
  nvidia-smi
EOF
}

case "$PHASE" in
  build) build_phase ;;
  install) install_phase; smoke_hint ;;
  *) die "usage: $0 {build|install}" ;;
esac
