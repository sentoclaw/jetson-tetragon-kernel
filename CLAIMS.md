# Claims

Every factual claim this repository and its accompanying write-up make, with what backs it and how you can check it.

We keep this because a recipe you cannot audit is just a story. Some of what follows you can verify yourself in an afternoon with a download and a grep. Some of it happened on our board, where you can reproduce it but the run itself is ours. We marked those separately so you can weigh them differently. And some things we chose not to claim at all, which is the part most worth reading.

If you find something here that is wrong, open an issue. We would rather fix a row than defend one.

---

## 1. Verifiable from public sources

You do not need a Jetson to check any of these. Download the tarball, grep the file.

**1.1 Stock NVIDIA L4T kernel 5.15 (JetPack 6, L4T R36.5) ships with kprobes and BTF off.**

`CONFIG_KPROBES`, `CONFIG_DEBUG_INFO_BTF`, `CONFIG_DEBUG_INFO_BTF_MODULES` and `CONFIG_BPF_LSM` are all unset. `CONFIG_DEBUG_INFO_REDUCED=y`. `CONFIG_BPF_SYSCALL=y`.

Source: `public_sources.tbz2` from `https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.0/sources/public_sources.tbz2`, sha256 `d0acb2187786d6ba9f012dd72ee7005309903944c4e8f3d649d7dabd3aebba42`. Fetched from NVIDIA directly, not a mirror. Check `arch/arm64/configs/defconfig` in the kernel tree inside it.

**1.2 The same posture is present in NVIDIA's 6.8 tree (JetPack 7.2.1, Jetson Linux 39.2.1).**

Upgrading JetPack does not turn these on.

Source: `https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.1/sources/public_sources.tbz2`, sha256 `8346f0371649a92c42293b2d4a7bf3d69e4dd1de23009e1463ea910994a81371`. The adjacent `r39_Release_v2.0` was also checked and agrees on every gate symbol.

**1.3 The 6.8 defconfig covers more than Orin.**

The same `arch/arm64/configs/defconfig` selects both `CONFIG_ARCH_TEGRA_234_SOC` and `CONFIG_ARCH_TEGRA_264_SOC`. There is no separate defconfig for the newer silicon. This is why we say the configuration posture carries. See 3.5 for where that stops.

**1.4 `CONFIG_DEBUG_INFO_BTF_MODULES` is silently dropped when pahole is absent.**

The Kconfig, unchanged in both NVIDIA trees:

```
config DEBUG_INFO_BTF_MODULES
	bool "Generate BTF type information for kernel modules"
	default y
	depends on DEBUG_INFO_BTF && MODULES && PAHOLE_HAS_SPLIT_BTF
```

With no pahole on the build host, `CONFIG_PAHOLE_VERSION=0`, `PAHOLE_HAS_SPLIT_BTF` is never set, the dependency fails, and `olddefconfig` drops the symbol with exit code 0 and no warning.

**1.5 Override enforcement needs two more symbols. arm64 already supports it.**

`CONFIG_BPF_KPROBE_OVERRIDE` depends on `BPF_EVENTS` and `FUNCTION_ERROR_INJECTION`, and is `default n`. `FUNCTION_ERROR_INJECTION` is a prompted `bool` with no default, depending on `HAVE_FUNCTION_ERROR_INJECTION && KPROBES`, so it stays off until someone sets it. arm64 selects `HAVE_FUNCTION_ERROR_INJECTION` unconditionally in `arch/arm64/Kconfig` in both trees. All four statements are readable in the source.

**1.6 Tetragon distinguishes Override from Signal, and says so itself.**

Override means "the function will never be executed and, instead, a value (typically an error) will be returned to the caller." Signal kills the process, and Tetragon's own documentation states that "sending a `SIGKILL` signal does not always stop the operation being performed by the process." Their recommendation is to pair the two. See <https://tetragon.io/docs/concepts/enforcement/> and the kernel configuration list at <https://tetragon.io/docs/installation/faq/>.

**1.7 The BTFIDS unresolved-symbol failure is reported on the 5.10 line, from L4T 35.1 through JetPack 5.13.**

- [L4T 35.1 / kernel 5.10.104, posted 2022-10-04](https://forums.developer.nvidia.com/t/jetson-35-1-linux-build-will-fail-if-config-debug-info-btf-y/229809): `BTFIDS vmlinux` / `FAILED unresolved symbol netlink_sock`. Reporter: an upstream 5.10.104 and the same tree with NVIDIA's patches removed both built. Thread is open. No official NVIDIA answer.
- [JetPack 5.1.2 / kernel 5.10.120, posted 2025-06-03](https://forums.developer.nvidia.com/t/nvidia-jetpack5-1-2-linux-5-10-120-build-will-fail-if-config-debug-info-btf-y/335094): same class (`tcp6_sock`, then `udp6_sock` after applying a `netlink_sock` BTF_ID). Closed.
- [JetPack 5.13, Orin NX 16G, posted 2025-08-26](https://forums.developer.nvidia.com/t/orinnx-enable-config-debug-info-btf-y-and-build-kernel-error/343156): `FAILED unresolved symbol netlink_sock`. NVIDIA staff (ShaneCCC) supplied: add `BTF_ID(struct, netlink_sock)` in `kernel/kernel-5.10/net/netlink/af_netlink.c`. Reporter: "thanks for your solution, I solved it." Closed, accepted answer.

All three reports are on kernel 5.10. Our builds are 5.15.185 and 6.8.12. See 2.2 and 3.2.

---

## 2. Observed on our hardware

You can reproduce all of these by following the repository. The runs themselves happened on our board, so section 1 carries NVIDIA's word and this section carries ours. We keep them apart for that reason.

Board: Jetson AGX Orin Developer Kit. Toolchain for every build below: pahole v1.25, gcc 11.4.0 (Ubuntu 11.4.0-1ubuntu1~22.04.3), GNU ld 2.38, building natively on the Jetson.

**2.1 The delta from stock is five changed symbols on JetPack 6.**

Measured by diffing the stock expanded config, recovered with `scripts/extract-ikconfig` against an untouched stock `/boot/Image`, against the rebuilt kernel's expanded config. `CONFIG_DEBUG_INFO`, `CONFIG_LOCALVERSION_AUTO` and `CONFIG_BPF_LSM` are already where we want them on JP6 stock, so they stay out of the five. See correction 4.1.

**2.2 `BTFIDS vmlinux` completed on both kernels. Stock source, stock build.**

On 5.15 and again on 6.8, with the toolchain above. `readelf -S vmlinux` shows `.BTF` and `.BTF_ids` in both. `IGNORE_BTF_ERRORS=1` was never set. The running 5.15 kernel exposes `/sys/kernel/btf/vmlinux` at 7,154,354 bytes.

Scope: two builds, these tool versions, this board. The reported history of the same error class is 1.7, and it is all on 5.10. Read 3.2 before drawing a conclusion from it.

**2.3 The GPU stack survives.**

`nvidia-smi` reports driver 540.5.0 and CUDA 12.6 on the rebuilt 5.15 kernel with the out-of-tree modules rebuilt against the new `Module.symvers`. On R36.5, `modules_install` places `nvgpu.ko` at `updates/nvgpu.ko`, not under `*/gpu/nvgpu/`, so a path check against the old location fails on a build that actually succeeded.

**2.4 The recipe reproduces from this repository alone.**

A clean-room rebuild, on a fresh tree, using only what is published here, produced config equivalence excluding `CC_VERSION_TEXT` and `BUILD_SALT`, BTF present, `CONFIG_KPROBES=y`, and an `nvgpu.ko` with matching vermagic. Doing it turned up three gaps in our own instructions, which are fixed in what you are reading. This build was verified and not installed, so the GPU check in 2.3 comes from the running kernel rather than from this build.

**2.5 JetPack 7 builds.**

R39.2.1 / 6.8, built natively on an AGX still running JetPack 6. 22 minutes 28 seconds, exit 0, kernel release `6.8.12-tegra-tetragon`, Image sha256 `db43d0fcd68a4788550be601b93bc6ef1a45b76aae2b76f960150a432df4945f`, BTF present, BTFIDS clean, module vermagic correct. Not flashed, not booted. See 3.4.

**2.6 The enforce profile builds, and costs nothing else.**

Same sources as the observe profile. `CONFIG_FUNCTION_ERROR_INJECTION=y` and `CONFIG_BPF_KPROBE_OVERRIDE=y` both resolve, 18 minutes 10 seconds, exit 0, Image sha256 `42d888f13cef4f111ccc7033511983bec85b13aa03477274c7e0703cba2810a2`, BTF present, out-of-tree GPU modules rebuilt with matching vermagic. Diffed against the observe config, exactly three symbols moved: the two above plus the version suffix. Nothing else changed. Not booted. See 3.3.

**2.7 Signal-class enforcement ran, and we have the event.**

On the rebuilt 5.15 kernel, 2026-06-11T03:00:34Z, a Tetragon policy fired `KPROBE_ACTION_SIGKILL` on a process reading a credential file. That is Signal-class. Override was never available on that kernel, per 1.5 and 3.3.

**2.8 Enforcement scoped too broadly will break things you did not think about.**

A network policy of ours using SIGSTOP applied to every UID, froze `connect()` for `chrony` and `systemd-resolved`, and broke package installs through a local caching proxy. We narrowed the selectors. That is the failure mode, and we hit it.

**2.9 Reusing stock's version suffix destroys your fallback.**

Stock R36.5 has `CONFIG_LOCALVERSION=""`; the `-tegra` in `uname -r` does not come from there. Setting `CONFIG_LOCALVERSION="-tegra"` produces a module path that collides with stock's, and `modules_install` overwrites the tree you were keeping as a rollback. We did this once. The two profiles in this repo carry distinct suffixes for exactly this reason.

**2.10 Dropping the `FDT` line takes the network down.**

An extlinux rewrite without the per-stanza `FDT` line makes the loader fall back to a firmware DTB with no MGBE node. Separately, restoring factory modules without the out-of-tree `nvethernet.ko` and `nvpps.ko` leaves the onboard 10GbE dead. Together you lose all LAN and diagnose over serial. `KNOWN-FAILURES.md` records the theories we chased and discarded on the way to that.

---

## 3. What we deliberately do not claim

**3.1 Bit-for-bit reproducibility.** Three builds of the same config gave three different `Image` hashes. Those builds left `KBUILD_BUILD_TIMESTAMP`, `USER` and `HOST` unpinned, and we let it go. Config equivalence is config equivalence.

**3.2 That the BTFIDS bug is fixed, or that pahole 1.25 fixes it.** We report that our builds cleared it with our toolchain, and we leave the mechanism alone. Upstream has at least three distinct causes in this error class and none is authoritatively pinned for Tegra. If you know, tell us.

**3.3 That Override enforcement works.** The enforce profile builds and the symbols resolve. Boot and a runtime Override event are both still ahead of us. When we have the event, we will publish it the way we published 2.7.

**3.4 That the recipe works on JetPack 7.** Build-level only. No boot, no extlinux or FDT validation, no `nvidia-smi`, no out-of-tree GPU rebuild, no Tetragon attach. If you are on R39.2 hardware, we would like to hear what broke.

**3.5 That this works on newer Tegra silicon.** The defconfig covers it, per 1.3. We have not run it on that hardware. That is a guess, and we are calling it a guess.

**3.6 Any performance or overhead figure.** We have not measured it. There are inference numbers on the rebuilt kernel, and the matching run on stock is missing, so there is no delta to report. The run we do have left the `nvpmodel` power mode and `jetson_clocks` state unrecorded, and on a Jetson those two dominate everything else. Put the power mode beside the number, or the number means nothing. We would like to see a proper one.

**3.7 Anything about NVIDIA's intent.** Why these options ship off, whether it is supported, what they plan. We report the observable defconfig posture and stop.

**3.8 That no prior writeup exists.** We did not find a published writeup that keeps the GPU. We are not claiming none exists. If you know of one, we will link it.

---

## 4. Corrections

Things we had wrong during the work and fixed. They are here because they are the useful part.

**4.1 We said seven symbols. It is five.** An earlier internal draft asserted a seven-symbol delta. Measuring stock-versus-running expanded configs gave five changed symbols, with three of the assumed seven turning out to be no-ops on JP6 stock. The number was not worth defending.

**4.2 We thought JetPack 7 needed a different fragment.** A first pass on a workstation showed `CONFIG_DEBUG_INFO_BTF_MODULES` failing to land on 6.8, which looked like a real platform difference. It was the workstation having no pahole, per 1.4. Re-running on a pahole-present host resolved it. The false start is in the write-up because the failure mode is the finding.

**4.3 We assumed `FUNCTION_ERROR_INJECTION` would resolve automatically.** It has a prompt and no default, so it does not. Reading the actual Kconfig in NVIDIA's tree settled it, per 1.5.

---

## Scope

This repository is kernel configuration and build scripts for somebody else's kernel. Everything in it is config and tooling. It ships as-is under the license's warranty disclaimer, with no support commitment, and it sits outside the SentoClaw product.
