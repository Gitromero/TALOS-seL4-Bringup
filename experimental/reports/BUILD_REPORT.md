# Experimental build report

**Date:** 2026-10-20 · **Script:** [`../scripts/build-experimental.sh`](../scripts/build-experimental.sh) · **Hardware status:** not tested on a Discovery Kit

## Result

| Artifact | Size (bytes) | SHA-256 |
|---|---:|---|
| `experimental/images/sel4-experimental.uImage` | 3,021,688 | `2c98607641ea3418f39e3b4396c9fd97afdd982b151a3b7a783408a41b887d27` |
| `experimental/boot/boot-auto.scr` | 3,046 | see [`../images/SHA256SUMS`](../images/SHA256SUMS) (regenerated whenever `boot-auto.cmd` changes) |
| ELF before wrapping (not shipped; has debug info) | 3,093,024 | `b670beb9397de118813f8dd22d33ee2c2b1ab7ac597de07f3400876782a857d8` |

`dumpimage -l` on the uImage:

```text
Created:      2026-09-22 16:02:56 UTC   (SOURCE_DATE_EPOCH = manifest commit time)
Image Type:   RISC-V Linux Kernel Image (uncompressed)
Data Size:    3021624 Bytes
Load Address: 80640000
Entry Point:  80640000
Header CRC 0x5521EB2D, Data CRC 0x52F4EE80
```

ELF: entry `0x80640000`, one LOAD segment at `0x80640000` with filesz `0x2e1b38` and memsz `0x2e8000` (`readelf`). The image is **not identical** to the verified baseline (`29d926e4…`), as intended.

## Inputs

| Input | Value |
|---|---|
| Manifest | `seL4/sel4test-manifest` @ `11c9090d597e20d9a39474ec94be9f33f2964d6b`; fetched `default.xml` is byte-identical to `source/sel4test-manifest-pinned.xml` |
| Project revisions | all ten projects verified at their manifest SHAs after `repo sync -c` (kernel `0f108291…`, sel4test `b00d84fc…`, seL4_tools `f1f63d93…`, seL4_libs `262a34dc…`, util_libs `8dd23f73…`, sel4_projects_libs `fe2647c2…`, sel4runtime `86489cf6…`, musllibc `b0005f86…`, nanopb `cad3c18e…`, opensbi `234ed8e4…`) |
| Patches | `patches/kernel/0001` and `patches/sel4test/0001` (same as the verified baseline), plus `experimental/patches/kernel/0002` (MAC → zeros) |
| Toolchain | `trustworthysystems/camkes@sha256:77dcf9c7927c138d88434d812d8bd8b86455f9418d0895682250745b192e291e`: riscv64-unknown-elf-gcc 14.2.0, CMake 3.31.6, Ninja 1.12.1, dtc 1.7.2, mkimage 2025.01. These are the same versions as the per-user image used for the verified build. |
| Build path | checkout mounted at `/build/sel4test` in the container |
| Path remapping | `-ffile-prefix-map=/build/sel4test/=` for C, C++ and ASM |
| Timestamps | `SOURCE_DATE_EPOCH=1790092976` (uImage and script headers) |
| CMake options | `-DPLATFORM=polarfire -DKernelPolarfireBoard=discovery -DRELEASE=OFF -DSMP=OFF -DUseRiscVOpenSBI=OFF -DElfloaderImage=uimage -DLibSel4PlatSupportUseDebugPutChar=ON` (identical to the verified `board/discovery/build.sh`) |

## Equivalence with the verified build

- **Configuration:** every non-path CMake cache value is identical between the verified build tree and the clean build. The only differences are three variables holding absolute paths (`LWIP_HELPERS`, `NANOPB_SRC_ROOT_FOLDER`, `PLATSUPPORT_HELPERS`).
- **Generated kernel platform configuration:** all **11** files under `kernel/gen_headers` and `kernel/gen_config` are **byte-identical**. These include the memory regions (`0x80200000–0x84000000`, `0x8a000000–0x92000000`), the kernel devices (CLINT, PLIC), the IRQ count and the timer frequency.
- **Embedded device tree:** decompiling the DTB inside each image and diffing gives exactly one difference: `local-mac-address` on `ethernet@20110000`, changed from `00 04 a3 6d f8 11` to `00 00 00 00 00 00`. MMUART4 console, memory nodes, `seL4,kernel-devices`, CLINT `riscv,clint0` and the 2 MiB SBI reservation are unchanged.
- **Load address:** the ELF loader moved from `0x80650000` to `0x80640000`, because the payload is 35,840 bytes smaller once the path strings are shorter. The rootserver and kernel layout are computed by the ELF loader at boot. Under QEMU this layout boots and passes the full suite. **On hardware it is untested.**

## Reproducibility

| Check | Result |
|---|---|
| Two independent runs (separate empty work dirs, fresh `repo sync` from GitHub each time) | **byte-identical** `sel4-experimental.uImage` and ELF |
| `boot-auto.scr` regenerated from `boot-auto.cmd` with the pinned container's `mkimage` | payload equals `boot-auto.cmd` byte-for-byte (`tail -c +73 \| cmp`) |
| Corresponding-source archive (`make-source-archive.sh`) built from both checkouts | **byte-identical** (`306cbfaf…`, 4.2 MB); file counts per project equal `git ls-tree` |

Limits: reproducibility depends on the toolchain image staying pullable by digest and on GitHub serving the pinned commits. It was checked on one host (x86-64 Linux, Docker). The verified baseline cannot be reproduced byte-for-byte because it embeds the original absolute paths.

## Resource use

About 214 MB per work directory (sources + `.repo` + build), plus about 10 GB for the toolchain image.
