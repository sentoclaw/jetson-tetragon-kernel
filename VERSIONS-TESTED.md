# Versions tested

Not-tested is as prominent as tested.

## Built and booted

| Item | Value |
|---|---|
| Board | Jetson AGX Orin developer kit |
| L4T | R36.5 (JetPack 6 series) |
| Running kernel | `5.15.185-tegra-tetragon` |
| Stock Image sha256 | `a5112e36f11e8987415eb1bce0b25baf8fd76bf29a58bb8ccec23a3b71a109a9` |
| Rebuilt Image sha256 | `77bc0cfdc562a7419420468f92511dd8126bfc1d28a816306f8b1496eeb10d2b` |
| pahole | v1.25 |
| gcc | Ubuntu 11.4.0 |
| BTF | `/sys/kernel/btf/vmlinux` present, 7154354 bytes |
| GPU after OOT rebuild | `nvidia-smi` driver 540.5.0 / CUDA 12.6 |

R36.5 `public_sources.tbz2`:

- URL: `https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.0/sources/public_sources.tbz2`
- sha256: `d0acb2187786d6ba9f012dd72ee7005309903944c4e8f3d649d7dabd3aebba42`

## Defconfig posture (not a boot test)

Stock NVIDIA `arch/arm64/configs/defconfig` from NVIDIA's own tarballs. kprobes, BTF, BTF-modules, and BPF-LSM are absent-or-unset on all three.

| Release | URL | sha256 |
|---|---|---|
| R36.5 (5.15) | `https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.0/sources/public_sources.tbz2` | `d0acb2187786d6ba9f012dd72ee7005309903944c4e8f3d649d7dabd3aebba42` |
| r39_Release_v2.1 **current** (6.8, Jetson Linux 39.2.1 / JetPack 7.2.1) | `https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.1/sources/public_sources.tbz2` | `8346f0371649a92c42293b2d4a7bf3d69e4dd1de23009e1463ea910994a81371` |
| r39_Release_v2.0 adjacent, checked, agrees | `https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.0/sources/public_sources.tbz2` | `87d2e31ff55beaf2373e2f288538585995b231fd5745ec21f39a668e36efab2f` |

`CONFIG_DEBUG_INFO` is `=y` on R36.5 and absent as a written symbol on both 6.8 defconfigs (the DWARF choice is `CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y`). After the JP6 five plus `olddefconfig` on R39.2.1 kernel-noble, `CONFIG_DEBUG_INFO=y` is written.

On a laptop without pahole (`CONFIG_PAHOLE_VERSION=0`, 007) `CONFIG_DEBUG_INFO_BTF_MODULES` did not land. On the AGX with pahole v1.25 (`CONFIG_PAHOLE_VERSION=125`, 008) it landed.

## Built, not booted (JetPack 7.2.1 / 6.8)

Native `make ARCH=arm64 -j12 Image modules` on an AGX Orin that was itself running L4T R36.5 / `5.15.185-tegra-tetragon`. Building a 6.8 tree on a 5.15 host is expected.

| Item | Value |
|---|---|
| Sources | `r39_Release_v2.1` `public_sources.tbz2` sha256 `8346f037…a81371` |
| Unpack | `Linux_for_Tegra/source/kernel_src.tbz2` → `kernel/kernel-noble` |
| kernelrelease | `6.8.12-tegra-tetragon` |
| Image sha256 | `db43d0fcd68a4788550be601b93bc6ef1a45b76aae2b76f960150a432df4945f` |
| vmlinux BTF | `readelf -S`: `.BTF` and `.BTF_ids` present |
| BTFIDS | `BTFIDS vmlinux` succeeded (no unresolved-symbol line) |
| Module vermagic | `qrtr.ko`: `6.8.12-tegra-tetragon SMP preempt mod_unload modversions aarch64` |
| pahole | v1.25 |
| gcc | Ubuntu 11.4.0 (the running JP6 board's compiler) |
| Flashed / booted / Tetragon on JP7 | **no** |

`config-fragment.jp7` is this resolution. The JP6 five in `config-fragment` are unchanged.

## Config equivalence

`apply-config.sh` + `olddefconfig` is expected to match a prior expanded running config except:

- `CONFIG_BUILD_SALT` (build identity)
- `CONFIG_CC_VERSION_TEXT` when only the distro gcc package revision changes (observed: `11.4.0-1ubuntu1~22.04.2` vs `22.04.3`) while `CONFIG_GCC_VERSION` stays `110400`

Those two are not recipe symbols. The five measured flags in `config-fragment` must match.

## Disk budget (measured)

Measured on an AGX Orin native rebuild with `CONFIG_DEBUG_INFO=y` (required for BTF). Object files are large; `vmlinux` was 415M.

| Tree | Size |
|---|---|
| Kernel build tree (`kernel-jammy-src` after Image + modules) | 8.2G |
| OOT GPU source + build | 9.3G |
| Staged OOT modules | 407M |
| `public_sources.tbz2` | 222M |
| Extracted `kernel_src` wrapper | 223M |
| OOT artifact tar.gz | 124M |
| **Occupied by one clean-room pass** | **19G** |

A second concurrent kernel tree is another ~8.2G. The 40G floor used in the Phase C executor handoff was an estimate, not this measurement. Ordinary "a kernel build needs 10G" provisioning will not fit kernel + OOT.

## Not tested

This recipe has **not** been booted on JetPack 7.x / Jetson Linux 39.2.1 hardware.

A 6.8 Image was built on a board still running JetPack 6. It was not flashed, not booted, and Tetragon was not attached on JP7. Untested on that release: boot, extlinux / FDT behavior, `nvidia-smi` recovery, OOT GPU rebuild, and module-tree collision behavior.

If you run this on JetPack 7 hardware, report what broke.
