# Known failures

Symptom strings a reader would search, what causes them, and the fix.
Nothing here asserts a vendor motive.

## Module tree collision

**Search for:** `disagrees about version of symbol module_layout`

**Cause:** `make modules_install` writes into `/lib/modules/$(uname -r)/`. If `CONFIG_LOCALVERSION` matches stock, that directory *is* the stock module tree. The rebuild's modules have the same vermagic string and different symbol CRCs. The **stock** fallback kernel is what floods the journal — the rebuild destroyed the rollback.

**Fix:** Restore factory modules from the BSP `kernel_supplements.tbz2` (`lib/modules/5.15.185-tegra/…`), `depmod` that tree, prove a clean stock boot (`disagrees` count = 0). Rebuild with a **distinct** `CONFIG_LOCALVERSION` (`-tegra-tetragon`) so modules land in a separate directory. Confirm the stock module directory's timestamp does not move on `modules_install`.

## Network loss

**Search for:** `ip -br addr` showing only `lo`, `l4tbr0`, `usb0`, `usb1`

**Cause (two, coupled):**

1. An extlinux rewrite that drops the per-stanza `FDT` line. The loader falls back to a firmware DTB with no MGBE node.
2. A factory module restore that omits the out-of-tree `nvethernet.ko` / `nvpps.ko`. The onboard Tegra MGBE 10GbE stays dead.

Diagnosed over serial with SSH dead.

**Fix:** Keep `FDT /boot/dtb/kernel_tegra234-p3737-0000+p3701-0005-nv.dtb` (or the matching board `-nv` DTB) on **every** stanza. Rebuild `nvethernet` and `nvpps` against the new kernel's symbols; do not copy stock `.ko` files into the new tree.

**Discarded theories** (chased, wrong, useful so a reader does not repeat them): the underlay is not PCIe `r8169` / `eno1`; the `[10ec:c822]` device is the RTL8822CE Wi-Fi, not the LAN; a UPHY / `Phy link never came up` cold-boot story does not explain the missing netdev.

## GPU gone

**Search for:** `NvRmMemInitNvmap failed`; `/dev/nvgpu*` missing; `modinfo nvgpu` not found

**Cause:** A new kernel invalidates the entire out-of-tree NVIDIA GPU stack. In-tree `modules_install` does not rebuild `nvgpu` / display / host1x.

**Fix:** Rebuild those modules against the new kernel's `Module.symvers` and install under `updates/`. On R36.5, `nvgpu.ko` lands at `updates/nvgpu.ko`, not `*/gpu/nvgpu/`. Never copy stock `.ko` files.

## BTF build failure

**Search for:** `BTFIDS vmlinux FAILED unresolved symbol netlink_sock` (or `tcp6_sock`)

**Cause (as published):** We went in expecting to hit this.

**This rebuild:** BTF generation completed without that patch, with pahole v1.25 and gcc 11.4.0. `/sys/kernel/btf/vmlinux` was present (7154354 bytes).

Do not treat that as a fix. Do not assert a root cause. Do not set `IGNORE_BTF_ERRORS=1` — that skips BTF generation.

## Clock in the past

**Search for:** `make` skipping incremental rebuilds; objects "newer than" sources after a reboot

**Cause:** The clock can reset across power loss. `make` then believes the tree is up to date.

**Fix:** Normalize timestamps (or `make clean`) before a rebuild. The hardware clock itself is a separate topic and is not narrated here.
