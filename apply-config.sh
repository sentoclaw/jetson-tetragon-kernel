#!/usr/bin/env bash
# Apply the measured five-symbol delta onto the running kernel's config.
# Base: zcat /proc/config.gz (020 phase 3). LOCALVERSION from 022, not 020.
set -euo pipefail

KERNEL_SRC="${KERNEL_SRC:?set KERNEL_SRC to the unpacked kernel source tree}"
cd "$KERNEL_SRC"

if [[ ! -r /proc/config.gz ]]; then
  echo "FATAL: /proc/config.gz is not readable — this script bases .config on the running kernel" >&2
  exit 1
fi

zcat /proc/config.gz > .config

# 020 pinned LOCALVERSION to '-tegra'. That matched stock's uname suffix and
# made modules_install overwrite the stock module tree. Use a distinct pin.
./scripts/config --enable CONFIG_KPROBES
./scripts/config --disable CONFIG_DEBUG_INFO_REDUCED
./scripts/config --enable CONFIG_DEBUG_INFO_BTF
./scripts/config --enable CONFIG_DEBUG_INFO_BTF_MODULES
./scripts/config --set-str LOCALVERSION '-tegra-tetragon'

make olddefconfig

fail=0
grep -q '^CONFIG_KPROBES=y$' .config || { echo "FATAL: CONFIG_KPROBES did not land" >&2; fail=1; }
grep -q '^# CONFIG_DEBUG_INFO_REDUCED is not set$' .config || { echo "FATAL: CONFIG_DEBUG_INFO_REDUCED did not land unset" >&2; fail=1; }
grep -q '^CONFIG_DEBUG_INFO_BTF=y$' .config || { echo "FATAL: CONFIG_DEBUG_INFO_BTF did not land" >&2; fail=1; }
grep -q '^CONFIG_DEBUG_INFO_BTF_MODULES=y$' .config || { echo "FATAL: CONFIG_DEBUG_INFO_BTF_MODULES did not land" >&2; fail=1; }
grep -q '^CONFIG_LOCALVERSION="-tegra-tetragon"$' .config || { echo "FATAL: CONFIG_LOCALVERSION is not -tegra-tetragon" >&2; fail=1; }
if grep -q '^CONFIG_LOCALVERSION="-tegra"$' .config; then
  echo "FATAL: CONFIG_LOCALVERSION is -tegra (colliding pin)" >&2
  fail=1
fi
exit "$fail"
