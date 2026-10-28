# Build provenance

This page records where every shipped file came from and how it was checked. It separates three kinds of evidence:

- **Verified from files**: hashes, sizes, headers and diffs produced by commands run against the files (first at repository assembly on 2026-10-20, rechecked on 2026-10-21).
- **Observed on the board**: serial-console output from the Discovery Kit.
- **Historical record**: from the original bring-up log ([bring-up guide](../history/bringup-guide.md)) and handoff ([bring-up log](../history/bringup-log.md)), which cannot be re-checked from files.

## Shipped binaries

| Repository file | Origin | Size (bytes) | SHA-256 |
|---|---|---:|---|
| `images/sel4test.uImage` | [`scripts/build-sel4test.sh`](../scripts/build-sel4test.sh): clean build from pinned public sources + this repository's patches | 3,021,688 | `2c98607641ea3418f39e3b4396c9fd97afdd982b151a3b7a783408a41b887d27` |
| `boot/boot-auto.scr` | `mkimage` of [`boot/boot-auto.cmd`](../boot/boot-auto.cmd) in the pinned toolchain container, `SOURCE_DATE_EPOCH=1790092976` | 2,957 | `a5ab05d40c7d918150ded509a8a20ad91d39441d89772f6e992668160bcc6242` |
| `boot/boot-linux.scr` | Byte copy of the official Linux4Microchip 2026.04.1 `boot.scr`, taken from the team's SD card | 291 | `322ee52106fd2067a0b45932501d46d277018dbe46706ef6e608b41955db0060` |

**Checks:**

- **Reproducible.** `sel4test.uImage` came out byte-identical in three independent clean builds (two on 2026-10-20, one on 2026-10-21, each from a fresh `repo sync` into an empty directory). The 2026-10-21 build also reproduced `boot-auto.scr` byte-for-byte.
- **Board result** (observed): installed with the autoboot script on the team's SD card, the board booted it with no typing and printed `Test suite passed. 118 tests passed. 49 tests disabled.` At that time the same bytes were named `sel4-experimental.uImage`, and the script differed only in the file name it loads and its banner ([boot/README.md](../boot/README.md#history)).
- **Script source.** `tail -c +73 boot/boot-auto.scr | cmp - boot/boot-auto.cmd` is identical. `boot-linux.scr` was checked the same way and rebuilds byte-identically with its original timestamp.

### `sel4test.uImage` header (`dumpimage -l`)

```text
Created:      2026-09-22 16:02:56 UTC   (SOURCE_DATE_EPOCH = manifest commit time)
Image Type:   RISC-V Linux Kernel Image (uncompressed)
Data Size:    3021624 Bytes
Load Address: 80640000
Entry Point:  80640000
```

The image contains the string `TALOS: root task reached seL4 user space` (see the patches below).

### Source ELF (not shipped)

`<work-dir>/out/sel4test.elf`: ELF64 RISC-V (RVC, double-float), statically linked, with debug info. 3,093,024 bytes, SHA-256 `b670beb9397de118813f8dd22d33ee2c2b1ab7ac597de07f3400876782a857d8`. Entry `0x80640000`; one LOAD segment at `0x80640000`, filesz `0x2e1b38`, memsz `0x2e8000`.

## Source revisions

A Google `repo` checkout of [`seL4/sel4test-manifest`](https://github.com/seL4/sel4test-manifest) at manifest commit `11c9090d597e20d9a39474ec94be9f33f2964d6b`. The resolved, SHA-pinned manifest is shipped as [`source/sel4test-manifest-pinned.xml`](../source/sel4test-manifest-pinned.xml), an unmodified copy of `.repo/manifests/default.xml`, BSD-2-Clause, © seL4 Project. `build-sel4test.sh` checks that the fetched manifest is byte-identical to it and that every project is at its pinned SHA before building.

| Path | Upstream | Pinned SHA | TALOS changes |
|---|---|---|---|
| `kernel` | seL4 | `0f108291103d2797fc604fba71a1774d0ac20975` (`16.0.0-49-g0f1082911`) | patch `kernel/0001` |
| `projects/sel4test` | sel4test | `b00d84fca8890e34f6007f104372fec5e82a23d1` | patch `sel4test/0001` |
| `tools/seL4` | seL4_tools | `f1f63d93301cf491abc2d38ffb1a97803c218b31` | none |
| `projects/seL4_libs` | seL4_libs | `262a34dcb2f3285be01df9e5404d911132d567a6` | none |
| `projects/util_libs` | util_libs | `8dd23f736664fe61aefc25ea45ffff8127bcdf2b` | none |
| `projects/sel4_projects_libs` | sel4_projects_libs | `fe2647c2582cd22a83e07491bb281ce061324b81` | none |
| `projects/sel4runtime` | sel4runtime | `86489cf6efab9f314964e79468c036e9035394c7` | none |
| `projects/musllibc` | musllibc | `b0005f86fecbd6d0257b15363a5b013446914265` | none |
| `tools/nanopb` | nanopb | `cad3c18ef15a663e30e3e43e3a752b66378adec1` (0.4.9.1) | none |
| `tools/opensbi` | opensbi | `234ed8e427f4d92903123199f6590d144e0d9351` (v0.9) | none (unused: `UseRiscVOpenSBI=OFF`) |

## Source changes (patches)

| Patch | Applies to | Contents |
|---|---|---|
| [`patches/kernel/0001-polarfire-add-discovery-kit-board.patch`](../patches/kernel/0001-polarfire-add-discovery-kit-board.patch) | `kernel` @ `0f10829…` | `config.cmake`: `KernelPolarfireBoard` choice (`icicle` default, `discovery`). New `src/plat/polarfire/overlay-discovery.dts`. New `tools/dts/mpfs_discovery.dts` (identical to `board/discovery/discovery.dts`, board MAC zeroed) |
| [`patches/sel4test/0001-sel4test-driver-talos-banner.patch`](../patches/sel4test/0001-sel4test-driver-talos-banner.patch) | `projects/sel4test` @ `b00d84f…` | prints `TALOS: root task reached seL4 user space` at the start of the driver's `main()` |

Patches `kernel/0001` and `sel4test/0001` were generated from the original developer working tree and verified by applying them to fresh clones at the pinned SHAs: every resulting file was byte-identical to that tree. See [patches/README.md](../patches/README.md).

## Build configuration

[`scripts/build-sel4test.sh`](../scripts/build-sel4test.sh) runs inside `trustworthysystems/camkes@sha256:77dcf9c7927c138d88434d812d8bd8b86455f9418d0895682250745b192e291e` (riscv64-unknown-elf-gcc 14.2.0, CMake 3.31.6, Ninja 1.12.1, dtc 1.7.2, mkimage 2025.01), with the checkout mounted at `/build/sel4test`:

```sh
../init-build.sh -G Ninja -DPLATFORM=polarfire -DKernelPolarfireBoard=discovery \
  -DRELEASE=OFF -DSMP=OFF -DUseRiscVOpenSBI=OFF -DElfloaderImage=uimage \
  -DLibSel4PlatSupportUseDebugPutChar=ON \
  -DCMAKE_C_FLAGS=-ffile-prefix-map=/build/sel4test/= (same for CXX and ASM)
ninja
../tools/seL4/cmake-tool/helpers/make-uimage <objcopy> <readelf> \
  images/sel4test-driver-image-riscv-polarfire riscv \
  images/sel4test-driver-image-riscv-polarfire.uImage
```

- `UseRiscVOpenSBI=OFF`: HSS already provides M-mode SBI; U-Boot enters the payload in S-mode.
- `LibSel4PlatSupportUseDebugPutChar=ON`: user-level output goes via `seL4_DebugPutChar` → kernel → SBI console, so user space never touches MMUART3, which is disabled on this board.
- `ElfloaderImage=uimage` is overridden to `elf` by sel4test's `ApplyData61ElfLoaderSettings` for polarfire, so the ELF is wrapped afterwards by `make-uimage` (load = entry = ELF entry).
- The prefix map and the fixed container path keep host paths out of the image.

Resulting cache values: `KernelPlatform=polarfire`, `KernelSel4Arch=riscv64`, `KernelPolarfireBoard=discovery`, `CMAKE_BUILD_TYPE=Debug`, `KernelDebugBuild=ON`, `KernelPrinting=ON`, `KernelMaxNumNodes=1`, `Sel4testHaveCache=ON`, `Sel4testHaveTimer=OFF`. All 11 generated kernel platform configuration files are byte-identical to those of the original developer build.

The [Rust root task](../experiments/rust-root-task/README.md) reuses the same patched checkout, kernel options and toolchain image.

## Board and memory facts

From the board's own device tree ([`board/discovery/discovery.dts`](../board/discovery/discovery.dts), extracted from `/sys/firmware/fdt` on the running board) and the overlay:

| Item | Value |
|---|---|
| Boot hart | 1 (hart 0 = E51 monitor core, disabled) |
| Timebase | 1 MHz |
| PLIC | `0x0c000000`, 186 sources |
| CLINT | `0x02000000` (overlay sets compatible `riscv,clint0`) |
| Console | MMUART4 `0x20106000` (`stdout-path = "serial4:115200n8"`); MMUART3 `0x20104000` disabled |
| RAM given to seL4 | `0x80000000–0x84000000` (64 MiB) and `0x8a000000–0x92000000` (128 MiB) |
| Reserved | `0x80000000–0x80200000` (2 MiB, firmware/SBI); aliased windows `0xc4000000`, `0x1022000000`, `0x1412000000` deleted |
| Image | load/entry `0x80640000`; staged by U-Boot at `0x8e000000` (`scriptaddr`) |
| Layout seen on the board (Rust root task boot) | kernel `0x80200000–0x80223fff`, DTB `0x80224000–0x80229fff`, root task from `0x8022a000`; seL4 reported memory `[80200000..84000000)` and `[8a000000..92000000)` |

## Board firmware observed

| Item | Value | Evidence |
|---|---|---|
| Linux image | Linux4Microchip **2026.04.1** (kernel 6.18.17) | Verified from files: `/lib/modules/6.18.17-linux4microchip-2026.04.1-g7fbe4f69684d` on the SD card's root partition |
| U-Boot | `2025.07-linux4microchip-2026.04` | Verified from the board-extracted DTS; also printed at boot (observed 2026-10-21) |
| FPGA reference design | `microchip,mpfs-disco-kit-reference-rtl-v2507` | Verified from the board-extracted DTS |
| HSS | 0.99.53 | Historical record only |
| SBI | `OpenSBI v1.2`, runtime SBI version 2.0 | Observed 2026-10-21 (banner before U-Boot) |

## History: the first image

The repository's first revision shipped `images/sel4.uImage` (SHA-256 `29d926e4…`, 3,057,528 bytes, load `0x80650000`) with a staging script `boot/boot-sel4.scr`. That image was copied from the original developer's working tree and was the first to pass 118/49 on the board, booted by typing `bootm` at `RISC-V #`. It embedded 594 absolute paths containing the developer's username and the board's MAC, and could not be rebuilt byte-for-byte. Once the clean build above passed on the board, the first image and its script were removed. Both remain in git history.

## Rebuilding

How to rebuild the image and check it against the shipped hash: [building.md](building.md#rebuild-imagessel4testuimage).

## Privacy and publication notes

Full audit: [reports/PRIVACY_AUDIT.md](../reports/PRIVACY_AUDIT.md).

- **`images/sel4test.uImage`**: no username, home directory, hostname, IP or email strings, and the embedded DTB's MAC is zeroed. The only absolute path is `/build/reproducible-path/gcc-riscv64-unknown-elf-19/…`, which comes from the upstream toolchain's prebuilt `libgcc`.
- **Board DTS/DTB and `patches/kernel/0001`**: the board-unique Ethernet MAC is zeroed in all three (2026-10-22). Before that, a separate patch `kernel/0002` zeroed it only at build time. The built DTS is the same either way, so the image did not change. **The original MAC is still in this repository's first commit**, so publish from a fresh history (or rewrite it), not by pushing the existing one.
- **Rust root task**: only sources are shipped. A local build embeds the builder's paths in its debug strings, so don't publish built Rust images without rebuilding them in a generic path.
- **Text documents**: usernames replaced with `<user>`, the private workspace path shortened, the laptop model generalised, and the main TALOS repository's name omitted (owner decision).
- Not included: credentials, SD root filesystem, `.wic`, `fitImage`, build trees, `.git`/`.repo` internals, the large local source snapshot.

## Licensing and attribution

Third-party licences, the copyright notices required for binary redistribution, and the GPL source mechanism are in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), with full texts in [LICENSES/](../LICENSES/). Summary:

- The image contains **GPL-2.0-only** code (seL4 kernel, ELF loader) and one **GPL-2.0-or-later** file (`util_libs/libfdt/fdtget.c`). The rest is BSD-2/3-Clause, MIT (sel4runtime, util_libs, musl) and Zlib (nanopb). The static `libgcc` is covered by the GCC Runtime Library Exception.
- **GPL source:** publish the output of `scripts/make-source-archive.sh` (pristine pinned sources + all patches + build scripts, reproducible) **as a release asset next to the binary**. Links to upstream alone are not relied on.

**Open questions (release blockers until decided):**

1. **TALOS licence:** no licence has been chosen for the team's own docs and scripts. Kernel patches are necessarily GPL-2.0-only. The owner/team must pick one for the rest.
2. **Board DTS licence:** decompiled from Microchip firmware with no tag. The upstream Linux source for this board, `mpfs-disco-kit.dts`, is "(GPL-2.0 OR MIT)", © Microchip Technology Inc., but this exact blob also contains U-Boot/HSS fix-ups. Not confirmed.

This is an engineering assessment, **not legal advice**.
