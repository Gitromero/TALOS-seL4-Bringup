# Build provenance

This page records where every shipped file came from and what was checked when the repository was assembled (**2026-10-20**). It separates three kinds of evidence:

- **Verified at assembly**: checked directly against files on the developer's workstation and the working SD card. Hashes, sizes, headers and diffs below were produced by commands run then.
- **Historical record**: comes from the original bring-up log ([BRINGUP_GUIDE.md](BRINGUP_GUIDE.md)) and handoff ([context](../context/SEL4_BRINGUP_CONTEXT.md)), e.g. serial-console observations and the 118/49 test result. These cannot be re-checked from files.
- **Not verified**: stated as such wherever it appears.

## Shipped binaries

All three were copied **from the working seL4 SD card's FAT boot partition**, which was read only.

| Repository file | Source on the SD card | Size (bytes) | SHA-256 |
|---|---|---:|---|
| `images/sel4.uImage` | `sel4.uImage` | 3,057,528 | `29d926e476074f026c166d6032ad384d511e93dfaaa1c24b62fbed03549531f5` |
| `boot/boot-sel4.scr` | `boot.scr` | 324 | `8aabe37f2891eb2aabe33783cdb10aad19ecb78640d534e81a5fb89834f349fb` |
| `boot/boot-linux.scr` | `boot-linux.scr` | 291 | `322ee52106fd2067a0b45932501d46d277018dbe46706ef6e608b41955db0060` |

**Cross-checks (verified at assembly):**

- `sel4.uImage` on the SD card, `sel4test/build-polarfire/images/sel4test-driver-image-riscv-polarfire.uImage` in the build tree, and the developer's local milestone copy `sel4test-working.uImage` are **byte-identical** (same SHA-256). There is no mismatch to explain.
- `boot.scr` and `boot-linux.scr` exist only on the SD card. No other copy or hand-written source was found in the workspace. Their payloads were extracted to `boot/*.cmd`, and rebuilding with `mkimage` reproduces both binaries byte-for-byte (details in [boot/README.md](../boot/README.md#how-the-cmd-sources-were-recovered-and-checked)).
- The same card's FAT partition also held `fitImage` (6,179,748 B) and `uboot.env` (8,192 B) from the official image. These are **not** shipped; every teammate gets them from the official `.wic`. `uboot.env` was read to confirm `scriptaddr=0x8e000000`, `fdt_addr_r=0x8a000000`, `kernel_addr_r=0x80200000`, `bootdelay=2`, `boot_targets= mmc0 dhcp`.

### `sel4.uImage` header (`dumpimage -l` / `file`)

```text
Image Type:   RISC-V Linux Kernel Image (uncompressed)
Created:      2026-10-20 02:59:40 UTC   (= 2026-10-19 19:59:40 local, PDT)
Data Size:    3057464 Bytes
Load Address: 80650000
Entry Point:  80650000
Header CRC:   0xD337656B    Data CRC: 0x8441E07F
```

The 3,057,464-byte payload plus the 64-byte legacy header gives 3,057,528 bytes, matching the historical record. The image also contains the string `TALOS: root task reached seL4 user space` (see the patches below).

### Source ELF (not shipped)

`sel4test/build-polarfire/images/sel4test-driver-image-riscv-polarfire`: ELF64 RISC-V (RVC, double-float), statically linked, with debug info. 3,130,640 bytes, SHA-256 `6219c8a7cdfeced3b9a393fc77f5185f73a5d7442fda3c0fe45a8853a4792868`. Entry `0x80650000`. One LOAD segment at `0x80650000`, filesz `0x2ea738`, memsz `0x2f1000`. Built 2026-10-19 19:58 local time; the uImage was wrapped at 19:59. `readelf` output was checked at assembly.

## Source revisions

The build tree is a Google `repo` checkout of [`seL4/sel4test-manifest`](https://github.com/seL4/sel4test-manifest) at manifest commit `11c9090d597e20d9a39474ec94be9f33f2964d6b`. The resolved, SHA-pinned manifest is shipped as [`source/sel4test-manifest-pinned.xml`](../source/sel4test-manifest-pinned.xml), an unmodified copy of `.repo/manifests/default.xml`, BSD-2-Clause, © seL4 Project.

| Path | Upstream | Pinned SHA | Local state at assembly |
|---|---|---|---|
| `kernel` | seL4 | `0f108291103d2797fc604fba71a1774d0ac20975` (`16.0.0-49-g0f1082911`) | **modified + 2 untracked**: see patch |
| `projects/sel4test` | sel4test | `b00d84fca8890e34f6007f104372fec5e82a23d1` | **modified**: see patch |
| `tools/seL4` | seL4_tools | `f1f63d93301cf491abc2d38ffb1a97803c218b31` | clean |
| `projects/seL4_libs` | seL4_libs | `262a34dcb2f3285be01df9e5404d911132d567a6` | clean |
| `projects/util_libs` | util_libs | `8dd23f736664fe61aefc25ea45ffff8127bcdf2b` | clean |
| `projects/sel4_projects_libs` | sel4_projects_libs | `fe2647c2582cd22a83e07491bb281ce061324b81` | clean |
| `projects/sel4runtime` | sel4runtime | `86489cf6efab9f314964e79468c036e9035394c7` | clean |
| `projects/musllibc` | musllibc | `b0005f86fecbd6d0257b15363a5b013446914265` | clean |
| `tools/nanopb` | nanopb | `cad3c18ef15a663e30e3e43e3a752b66378adec1` (0.4.9.1) | clean |
| `tools/opensbi` | opensbi | `234ed8e427f4d92903123199f6590d144e0d9351` (v0.9) | clean (unused: `UseRiscVOpenSBI=OFF`) |

"Clean" means `git status --short` printed nothing. All HEADs match the pinned manifest revisions.

## Source changes (patches)

| Patch | Applies to | Contents |
|---|---|---|
| [`patches/kernel/0001-polarfire-add-discovery-kit-board.patch`](../patches/kernel/0001-polarfire-add-discovery-kit-board.patch) | `kernel` @ `0f10829…` | `config.cmake`: `KernelPolarfireBoard` choice (`icicle` default, `discovery`). New `src/plat/polarfire/overlay-discovery.dts`. New `tools/dts/mpfs_discovery.dts` (identical to `board/discovery/discovery.dts`) |
| [`patches/sel4test/0001-sel4test-driver-talos-banner.patch`](../patches/sel4test/0001-sel4test-driver-talos-banner.patch) | `projects/sel4test` @ `b00d84f…` | prints `TALOS: root task reached seL4 user space` at the start of the driver's `main()` |

The patches were generated read-only (`git diff`, plus `git diff --no-index /dev/null <file>` for untracked files, without staging). **They were verified** by applying them to fresh scratch clones checked out at the pinned SHAs (`git apply`, `patch -p1`) and comparing every resulting file with `cmp` against the working tree: all four files were identical. The `main.c` change was **not** listed in the original bring-up notes; it was found during assembly. Since its string is in the shipped image, it belongs to the verified build. See [patches/README.md](../patches/README.md) for how to apply them.

## Build configuration

From `board/discovery/build.sh` (copied unchanged, SHA-256 `88703dbf…f4393e`), run inside the container from `sel4test/build-polarfire/`:

```sh
../init-build.sh -DPLATFORM=polarfire -DKernelPolarfireBoard=discovery \
  -DRELEASE=OFF -DSMP=OFF -DUseRiscVOpenSBI=OFF -DElfloaderImage=uimage \
  -DLibSel4PlatSupportUseDebugPutChar=ON
ninja
../tools/seL4/cmake-tool/helpers/make-uimage <objcopy> <readelf> \
  images/sel4test-driver-image-riscv-polarfire riscv \
  images/sel4test-driver-image-riscv-polarfire.uImage
```

Values read from `build-polarfire/CMakeCache.txt` at assembly:

```text
PLATFORM=polarfire               KernelPlatform=polarfire      KernelSel4Arch=riscv64
KernelPolarfireBoard=discovery   CMAKE_BUILD_TYPE=Debug        RELEASE=OFF
SMP=OFF                          KernelMaxNumNodes=1           SIMULATION=OFF
UseRiscVOpenSBI=OFF              LibSel4PlatSupportUseDebugPutChar=ON
ElfloaderImage=elf               (requested uimage; overridden by sel4test, then wrapped by make-uimage)
KernelDebugBuild=ON              KernelPrinting=ON             KernelVerificationBuild=OFF
Sel4testHaveCache=ON             Sel4testHaveTimer=OFF
```

- `UseRiscVOpenSBI=OFF`: HSS already provides M-mode SBI; U-Boot enters the payload in S-mode.
- `LibSel4PlatSupportUseDebugPutChar=ON`: user-level output goes via `seL4_DebugPutChar` → kernel → SBI console, so user space never touches MMUART3, which is disabled on this board.
- C compiler version recorded by CMake: **GCC 14.2.0** (`riscv64-unknown-elf-`, from `/usr/bin` inside the container). Ninja from `/usr/bin/ninja` inside the container.

**Toolchain container:** a `user_img-<user>` image built with `make user` from [`seL4/seL4-CAmkES-L4v-dockerfiles`](https://github.com/seL4/seL4-CAmkES-L4v-dockerfiles). The local checkout was at commit `285ed6985036e62e0db59cc92c242efcf60ae6e7`. The image digest was not recorded.

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
| Image | load/entry `0x80650000`; staged by U-Boot at `0x8e000000` (`scriptaddr`) |
| Layout (historical, QEMU run) | kernel `0x80200000–0x80224000`, DTB `0x80224000–0x8022a000`, rootserver `0x8022a000–0x80630000`, elfloader `0x80650000–0x80941000` |

`board/discovery/discovery.dtb` (SHA-256 `22af0067…a199f6`) and `.dts` (`c56db1da…b4a67`) are identical to the developer's milestone copies. The `.dts` is also identical to `kernel/tools/dts/mpfs_discovery.dts`. Their file timestamps were updated later (2026-10-20 03:05 local) without any content change compared with the copy the kernel build used.

## Board firmware observed

| Item | Value | Evidence |
|---|---|---|
| Linux image | Linux4Microchip **2026.04.1** (kernel 6.18.17) | **Verified at assembly**: `/lib/modules/6.18.17-linux4microchip-2026.04.1-g7fbe4f69684d` on the seL4 card's root partition (read only) |
| U-Boot | `2025.07-linux4microchip-2026.04` | **Verified at assembly**: `u-boot,version` in the board-extracted DTS |
| FPGA reference design | `microchip,mpfs-disco-kit-reference-rtl-v2507` | **Verified at assembly**: root `compatible` in the board-extracted DTS |
| HSS | 0.99.53 | Historical record only (the bring-up log) |
| SBI | spec v2.0, impl ID `0x8`, impl version `0x10002` | Historical record only |
| `boot-linux.scr` | from Linux4Microchip 2026.04.1 image (header date 2026-04-29) | Verified at assembly (file + rootfs version) |

Release-page URLs for these exact versions were **not** verified. Teammates are pointed to the official release index pages instead.

## Rebuilding

Teammates do not need to rebuild. Prerequisites (Docker, `repo`, disk space, the pinned toolchain image) are listed in [SETUP.md](SETUP.md#docker-and-build-prerequisites-only-for-rebuilding-images).

### Experimental image (tested end to end)

```bash
experimental/scripts/build-experimental.sh /path/to/new-empty-dir [--update-repo]
```

The script does `repo init -u https://github.com/seL4/sel4test-manifest.git -b 11c9090d597e20d9a39474ec94be9f33f2964d6b` and `repo sync -c`. It checks that the fetched manifest is byte-identical to `source/sel4test-manifest-pinned.xml` and that every project is at its pinned SHA. It then applies the patches and builds in `trustworthysystems/camkes@sha256:77dcf9c7…` with the checkout mounted at `/build/sel4test` and `-ffile-prefix-map=/build/sel4test/=`. Two independent runs produced byte-identical images. See [experimental/reports/BUILD_REPORT.md](../experimental/reports/BUILD_REPORT.md).

### Verified baseline (manual reconstruction)

The verified image came from the developer's working tree, not from a scripted clean build. Its source and configuration are fully recorded, but **it cannot be reproduced byte-for-byte**, because it embeds that machine's absolute paths. To rebuild an equivalent image:

```bash
mkdir sel4test && cd sel4test
repo init -u https://github.com/seL4/sel4test-manifest.git -b 11c9090d597e20d9a39474ec94be9f33f2964d6b
repo sync -c
cmp .repo/manifests/default.xml <this-repo>/source/sel4test-manifest-pinned.xml   # must be identical
git -C kernel apply <this-repo>/patches/kernel/0001-polarfire-add-discovery-kit-board.patch
git -C projects/sel4test apply --whitespace=nowarn <this-repo>/patches/sel4test/0001-sel4test-driver-talos-banner.patch
mkdir -p board && cp -r <this-repo>/board/discovery board/
SEL4_DOCKER_IMAGE=trustworthysystems/camkes@sha256:77dcf9c7927c138d88434d812d8bd8b86455f9418d0895682250745b192e291e \
  board/discovery/build.sh
```

`repo init -b <manifest SHA>` was tested and yields the identical manifest. `build.sh` defaults to a per-user image `user_img-<user>` built with `make user` from `seL4/seL4-CAmkES-L4v-dockerfiles`. That image has the same toolchain versions as the pinned `trustworthysystems/camkes` image (checked: GCC 14.2.0, CMake 3.31.6, Ninja 1.12.1, mkimage 2025.01). Running `build.sh` as-is with the pinned image was **not** tested, because that image has no account for your UID; `build-experimental.sh` handles this by setting `HOME=/tmp`. **Any rebuilt image is a new, unverified image** until it passes 118/49 on hardware.

## Privacy and publication notes

Full audit: [experimental/reports/PRIVACY_AUDIT.md](../experimental/reports/PRIVACY_AUDIT.md).

- **Verified baseline (`images/sel4.uImage`)**: embeds 594 absolute paths that include the developer's home directory and username, plus the original board's MAC address `00:04:a3:6d:f8:11`, in its embedded DTB. This can't be fixed without changing the verified bytes, so it is kept as-is for recovery and comparison, and **must not be described as sanitized**.
- **Board DTS/DTB and `patches/kernel/0001`**: contain the same MAC. They must stay as they are to reproduce the verified build's sources.
- **Experimental image**: no username, home directory, hostname, IP or email strings, and the MAC is zeroed. The only absolute path is `/build/reproducible-path/gcc-riscv64-unknown-elf-19/…`, which comes from the upstream toolchain's prebuilt `libgcc` and is also present in the baseline.
- **Text documents**: usernames replaced with `<user>`, the private workspace path shortened, the laptop model generalised, and the main TALOS repository's name omitted (owner decision: keep it out of this repository) (`context/`, `docs/BRINGUP_GUIDE.md`, `board/discovery/bringup.md`).
- Not included: credentials, SD root filesystem, `.wic`, `fitImage`, build trees, `.git`/`.repo` internals, `old-host-cmake-attempt/`, the large local source snapshot.

## Licensing and attribution

Third-party licences, the copyright notices required for binary redistribution, and the GPL source mechanism are in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), with full texts in [LICENSES/](../LICENSES/). Summary:

- The images contain **GPL-2.0-only** code (seL4 kernel, ELF loader) and one **GPL-2.0-or-later** file (`util_libs/libfdt/fdtget.c`). The rest is BSD-2/3-Clause, MIT (sel4runtime, util_libs, musl) and Zlib (nanopb). The static `libgcc` is covered by the GCC Runtime Library Exception.
- **GPL source:** publish `experimental/scripts/make-source-archive.sh`'s output (pristine pinned sources + all patches + build scripts, reproducible, 4.2 MB) **as a release asset next to the binaries**. Links to upstream alone are not relied on.

**Open questions (release blockers until decided):**

1. **TALOS licence:** no licence has been chosen for the team's own docs and scripts. Kernel patches are necessarily GPL-2.0-only. The owner/team must pick one for the rest.
2. **Board DTS licence:** decompiled from Microchip firmware with no tag. The upstream Linux source for this board, `mpfs-disco-kit.dts`, is "(GPL-2.0 OR MIT)", © Microchip Technology Inc., but this exact blob also contains U-Boot/HSS fix-ups. Not confirmed.
3. **Verified-baseline privacy:** the owner must accept publishing the embedded paths and MAC, or omit the baseline binary from a public release.

This is an engineering assessment, **not legal advice**.
