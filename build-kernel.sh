#!/usr/bin/env bash
# Rebuild the running L4T kernel with the measured config delta.
# Sourced from 020 phases 1, 2, 5, 6, 7, 8. LOCALVERSION from 022.
# Does not change extlinux DEFAULT. Does not boot. Does not patch sources.
set -euo pipefail

KERNEL_SRC="${KERNEL_SRC:?set KERNEL_SRC to the unpacked kernel source tree}"
# 020 used JOBS=8 because that board reported 8 online cores. Default to
# this machine's nproc so a reader's power mode is not someone else's.
JOBS="${JOBS:-$(nproc)}"
STOCK_IMAGE="${STOCK_IMAGE:-/boot/Image}"
DEST_IMAGE="${DEST_IMAGE:-/boot/Image-tetragon}"
# Stock Image sha256 recorded on this platform (020 grounding / Phase A).
STOCK_IMAGE_SHA256="${STOCK_IMAGE_SHA256:-a5112e36f11e8987415eb1bce0b25baf8fd76bf29a58bb8ccec23a3b71a109a9}"
# R36.5 public_sources (Phase A measured URL).
PUBLIC_SOURCES_URL="${PUBLIC_SOURCES_URL:-https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.0/sources/public_sources.tbz2}"

LOCALVERSION='-tegra-tetragon'

die() { echo "FATAL: $*" >&2; exit 1; }
note() { echo "[*] $*"; }

pahole_ok() {
  command -v pahole >/dev/null 2>&1 || return 1
  local ver
  ver="$(pahole --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
  [[ -n "$ver" ]] || return 1
  awk -v v="$ver" 'BEGIN { split(v,a,"."); exit !((a[1] > 1) || (a[1] == 1 && a[2] >= 16)) }'
}

note "020 discipline: never interrupt a long make; verify file content after every install step."
note "Do not export IGNORE_BTF_ERRORS=1 — it defeats BTF and leaves no /sys/kernel/btf/vmlinux."

if ! pahole_ok; then
  die "pahole >= 1.16 is required (020 phase 1). Install dwarves, or on a zero-egress node transfer the package onto the board first."
fi

command -v gcc >/dev/null 2>&1 || die "gcc is not on PATH (020 phase 1)"
command -v make >/dev/null 2>&1 || die "make is not on PATH (020 phase 1)"

if [[ ! -d "$KERNEL_SRC" ]]; then
  die "KERNEL_SRC does not exist: $KERNEL_SRC. Fetch $PUBLIC_SOURCES_URL on a machine with egress, unpack the kernel source, and set KERNEL_SRC. If the build host has no WAN, copy the tree onto it (020 phase 2 laptop-fetch-and-scp fallback)."
fi

[[ -x "$KERNEL_SRC/scripts/config" ]] || die "not a kernel tree (missing scripts/config): $KERNEL_SRC"
[[ -f "$KERNEL_SRC/.config" ]] || die ".config missing — run apply-config.sh first"

cd "$KERNEL_SRC"

if grep -q '^CONFIG_LOCALVERSION="-tegra"$' .config; then
  die "CONFIG_LOCALVERSION is -tegra (colliding pin). apply-config.sh must set -tegra-tetragon"
fi
grep -q '^CONFIG_LOCALVERSION="-tegra-tetragon"$' .config \
  || die "CONFIG_LOCALVERSION is not -tegra-tetragon"

# 020 phase 5. Detach if your session cannot survive a multi-hour make.
# Do not ^C a running make.
note "make -j${JOBS} Image && make -j${JOBS} modules"
make -j"$JOBS" Image
make -j"$JOBS" modules

built="$KERNEL_SRC/arch/arm64/boot/Image"
[[ -f "$built" ]] || die "arch/arm64/boot/Image was not produced"
built_sha="$(sha256sum "$built" | awk '{print $1}')"
note "built Image sha256=${built_sha}"

if [[ -f "$STOCK_IMAGE" ]]; then
  stock_sha="$(sha256sum "$STOCK_IMAGE" | awk '{print $1}')"
  [[ "$built_sha" != "$stock_sha" ]] || die "built Image sha256 equals stock Image — wrong file"
fi
[[ "$built_sha" != "$STOCK_IMAGE_SHA256" ]] || die "built Image sha256 equals the recorded stock sha256"

# SKIP_INSTALL=1 builds Image + modules and stops. The default path still
# installs (sudo modules_install + copy to /boot/Image-tetragon). A live
# node used as a clean-room proof must not write /boot; set SKIP_INSTALL=1.
if [[ "${SKIP_INSTALL:-0}" == "1" ]]; then
  note "SKIP_INSTALL=1: Image and modules built at ${built}; not installing"
  exit 0
fi

note "020 phase 6: modules_install"
sudo make modules_install

moddir=""
for d in /lib/modules/*; do
  if [[ -d "$d" && "$d" == *"${LOCALVERSION}"* ]]; then
    moddir="$d"
  fi
done
[[ -n "$moddir" ]] || die "no /lib/modules directory carries ${LOCALVERSION}"
note "modules installed at ${moddir}"

note "020 phase 7: install uncompressed Image (Jetson extlinux boots raw Image)"
sudo cp -v "$built" "$DEST_IMAGE"
dest_sha="$(sha256sum "$DEST_IMAGE" | awk '{print $1}')"
[[ "$dest_sha" == "$built_sha" ]] || die "installed ${DEST_IMAGE} sha256 does not match the build output"
[[ "$dest_sha" != "$STOCK_IMAGE_SHA256" ]] || die "installed Image sha256 equals recorded stock sha256"

# 020 phase 8: DEFAULT must still be stock. This script does not edit extlinux.
if [[ -f /boot/extlinux/extlinux.conf ]]; then
  default_line="$(grep -E '^DEFAULT' /boot/extlinux/extlinux.conf || true)"
  note "extlinux DEFAULT line: ${default_line:-<missing>}"
  if echo "$default_line" | grep -qi 'tetragon'; then
    die "extlinux DEFAULT points at tetragon — this script must not change boot selection"
  fi
fi

note "Image installed at ${DEST_IMAGE} sha256=${dest_sha}"
note "Boot selection is an operator act. Do not change DEFAULT here."
