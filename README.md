# jetson-tetragon

A reconfigured and rebuilt NVIDIA L4T kernel, not a patched one. Zero source changes.

This is not a SentoClaw product. It carries no support commitment. It is published as-is under the Apache-2.0 warranty disclaimer in [LICENSE](LICENSE).

Anything this repository asserts is listed in [CLAIMS.md](CLAIMS.md), with what was measured, what was observed on our board, and what is deliberately not claimed.

Stock Jetson L4T 5.15 ships without kprobes and without BTF. Tetragon's kprobe policies cannot load on that kernel. The same defconfig posture is present in NVIDIA's current 6.8 tree (Jetson Linux 39.2.1). Upgrading JetPack does not turn those options on.

This tree is the recipe that was used to rebuild R36.5 on an AGX Orin developer kit so those options are on, the stock fallback remains bootable, the onboard 10GbE stays up, and the NVIDIA GPU stack still answers `nvidia-smi`.

## Profiles

Two named profiles. Pick one `CONFIG_LOCALVERSION` that is not already installed. Stock is `CONFIG_LOCALVERSION=""`.

**observe (default).** Five symbols in `config-fragment`. Enables kprobes and BTF so Tetragon can attach. Built and booted on JetPack 6 / 5.15 as `5.15.185-tegra-tetragon`. `apply-config.sh` applies this profile.

**enforce (opt-in).** Seven symbols in `config-fragment.enforce`: the observe five plus `CONFIG_FUNCTION_ERROR_INJECTION=y` and `CONFIG_BPF_KPROBE_OVERRIDE=y`. That pair enables Tetragon's Override action. Override lets BPF change kernel function return values. It requires `CAP_BPF` or root, so it is not a new way in, but it widens what an attacker already inside can do. Built and BTF-verified on 5.15. **Not booted. Override not demonstrated at runtime.** Read the header comment in `config-fragment.enforce` before using it. `apply-config.sh` does **not** apply this profile.

## Versions boundary

**Tested:** L4T R36.5 (JetPack 6), kernel `5.15.185-tegra-tetragon`, pahole v1.25, gcc 11.4.0. Built and booted. The first five symbols in `config-fragment` are that measurement. See `VERSIONS-TESTED.md`.

**Not tested:** JetPack 7.x **boot**. A 6.8 Image was built on an AGX still running JetPack 6 (`config-fragment.jp7`; BTF in vmlinux). It was not flashed or booted. If you run this on JetPack 7, report what broke.

**Disk:** one native pass occupied 19G (kernel tree 8.2G, OOT tree 9.3G). `vmlinux` was 415M because `CONFIG_DEBUG_INFO=y` is required for BTF. Provision at least 20G free for one tree, 30G if you keep two kernel trees. See `VERSIONS-TESTED.md`.

## How to use

1. Fetch NVIDIA's R36.5 `public_sources.tbz2` (URL and sha256 in `VERSIONS-TESTED.md`). Unpack it, then unpack `Linux_for_Tegra/source/kernel_src.tbz2`. The kernel tree is `kernel/kernel-jammy-src`. On a board with no WAN, fetch on a laptop and copy the tree across. The same `public_sources.tbz2` also contains `kernel_oot_modules_src.tbz2` and `nvidia_kernel_display_driver_source.tbz2` for the GPU rebuild.
2. `KERNEL_SRC=… ./apply-config.sh` — bases `.config` on `zcat /proc/config.gz`, which is the **running** kernel's config, then applies the five observe symbols in `config-fragment`. On a first-time stock board that file is stock's config. On a board that has already been rebuilt once it is not: re-running the script seeds from the rebuilt config, not from stock. To seed from stock on a rebuilt board, extract the untouched stock `/boot/Image` with `scripts/extract-ikconfig` and start from that `.config` instead. This script's behaviour is unchanged: it always uses `/proc/config.gz`.
3. `KERNEL_SRC=… ./build-kernel.sh` — builds `Image` and modules, then installs modules and copies the uncompressed Image to `/boot/Image-tetragon`. It does **not** change extlinux `DEFAULT`. Set `SKIP_INSTALL=1` to stop after the build (no `sudo`, no `/boot` write) when you only need to prove the recipe compiles. `build-kernel.sh` expects the observe `LOCALVERSION` (`-tegra-tetragon`). Do not point it at an enforce `.config` without reading the script.
4. Add a `LABEL tetragon` stanza using `extlinux.conf.tetragon.example`. Keep stock as `DEFAULT`. Do not drop the `FDT` line.
5. Rebuild out-of-tree ethernet (`nvethernet` / `nvpps`) against the new `Module.symvers` if those drivers are how the board reaches the network.
6. `KERNEL_SRC=… L4T_SOURCE_DIR=… ARTIFACT=… STAGE=… OOT_SRC_TARBALL=…/kernel_oot_modules_src.tbz2 NV_DISPLAY_TARBALL=…/nvidia_kernel_display_driver_source.tbz2 ./oot-gpu-rebuild.sh build` then `install` if you need the GPU stack. `build` stages modules and does not write `/lib/modules` or `/boot`. Override `TARGET_VERMAGIC` if your `LOCALVERSION` is not `-tegra-tetragon`.

Read `KNOWN-FAILURES.md` before the first boot. The module-path collision and the dropped-`FDT` outage are the two ways this work destroyed rollback or networking.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Files

| File | Role |
|---|---|
| `config-fragment` | observe (default): JP6 / R36.x / 5.15 measured five |
| `config-fragment.enforce` | enforce (opt-in): seven symbols; security tradeoff — read its header |
| `config-fragment.jp7` | JP7 / 6.8 AGX resolution (built, not booted) |
| `apply-config.sh` | Apply the observe five onto `/proc/config.gz` |
| `build-kernel.sh` | Build and install Image + modules |
| `oot-gpu-rebuild.sh` | Rebuild NVIDIA GPU OOT modules |
| `extlinux.conf.tetragon.example` | Stanza with the `FDT` line |
| `CLAIMS.md` | Every factual claim, with its evidence and its limits |
| `KNOWN-FAILURES.md` | Symptom → cause → fix |
| `VERSIONS-TESTED.md` | What was booted and what was not |
| `LICENSE` | Apache-2.0 |
| `NOTICE` | Copyright line |
