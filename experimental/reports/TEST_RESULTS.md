# Test results

**Date:** 2026-10-20. Every test below ran on the workstation, in QEMU, or against disposable FAT images. **No test was run on a physical Discovery Kit, and the working SD card was never written** (its file hashes were identical before and after all testing).

Legend: ✅ passed · ❌ failed · ⏳ not performed (needs hardware) · ➖ not applicable

## Summary

| Area | Test | Result |
|---|---|---|
| Build | Clean build from pinned sources completes | ✅ (twice) |
| Build | Two independent builds byte-identical | ✅ |
| Build | All 10 projects at pinned SHAs; manifest identical to `source/` copy | ✅ |
| Patches | `patches/kernel/0001` + `patches/sel4test/0001` apply to fresh GitHub checkouts at pinned SHAs | ✅ |
| Patches | Patched files equal the original working tree (config.cmake, overlay, main.c identical; DTS differs only by the intended MAC line) | ✅ |
| Image | `dumpimage -l`/`file`: legacy RISC-V kernel uImage, load = entry = `0x80640000`, ELF entry/LOAD agree | ✅ |
| Image | Not identical to the verified image (`2c98…` ≠ `29d9…`) | ✅ |
| Image | `sha256sum -c` for `images/` and `experimental/images/` | ✅ |
| Image | U-Boot `iminfo` header + data CRC (QEMU U-Boot 2025.10) | ✅ `Verifying Checksum ... OK` |
| Device tree | Embedded DTB extracted and decompiled by `dtc` without errors; diff vs. baseline = MAC only | ✅ |
| Device tree | Generated kernel platform config (11 files) identical to verified build | ✅ |
| Privacy | Audit of all shipped binaries ([PRIVACY_AUDIT](PRIVACY_AUDIT.md)) | ✅ experimental clean; baseline not clean (expected, documented) |
| QEMU | Experimental ELF on QEMU `virt` (OpenSBI): full sel4test | ✅ `Test suite passed. 118 tests passed. 49 tests disabled.` |
| QEMU | **Autoboot via real U-Boot** (2025.10, QEMU), no input: script → `bootm` → seL4 → sel4test | ✅ 118 passed / 49 disabled, about 50 s |
| Autoboot | Script source ↔ `.scr` payload byte-identical; `mkimage` generation | ✅ |
| Autoboot | Every script branch exercised under QEMU U-Boot (table below) | ✅ |
| Installer | 79 checks on disposable loop-mounted FAT images (list below) | ✅ 79/79 |
| Installer | Mutation tests: harness detects removal of CRLF handling (2 failures) and of the backup guard (6 failures) | ✅ |
| Source archive | Corresponding-source archive builds; byte-identical from two checkouts; complete vs. `git ls-tree` | ✅ |
| Hardware | Anything on a physical Discovery Kit | ⏳ see [hardware test plan](../README.md#hardware-test-plan-in-this-order-record-full-serial-logs) |

## QEMU environment

`qemu-system-riscv64` 8.2.2 (Ubuntu), `-machine virt -smp 2 -m 2G -bios default` (QEMU's built-in OpenSBI), U-Boot `2025.10-0ubuntu0.24.04.4` `qemu-riscv64_smode` (Ubuntu `u-boot-qemu` package, extracted without installing), virtio disk with an MBR and a bootable FAT partition holding `boot.scr`, `boot-linux.scr`, a dummy `fitImage`, and the image.

**What QEMU does and does not show.** QEMU `virt` is not a PolarFire SoC. It shares the memory base, PLIC and CLINT addresses, and the image's kernel uses its built-in Discovery Kit configuration. It shows that the image is well-formed, that the ELF loader, kernel and user space start, that sel4test passes, and that the U-Boot script logic and `bootm` hand-off work. It does **not** show HSS SBI compatibility, MMUART4, real board memory reservations, the board's U-Boot build options, or timing.

## Autoboot script branches (QEMU, U-Boot 2025.10)

The overlap, invalid-FDT and unset-FDT cases used a test-only wrapper `boot.scr` that changes the environment and then sources the unmodified `boot-auto.scr`.

| Scenario | Script output | Outcome |
|---|---|---|
| Normal | `FDT at 0xfeead700, 0x16e6 bytes` → `image range ends below FDT` → `Verifying Checksum ... OK` → `booting seL4` → `Loading Device Tree to …fdea1000 … OK` | seL4 boots, sel4test 118/49 ✅ |
| FDT below image (moved to `0x8a000000`) | `FDT ends below image range` → boot | sel4test 118/49 ✅ |
| FDT overlapping image (moved to `0x8e100000`) | `image range overlaps the FDT` | Linux fallback ✅ |
| Invalid FDT (zeros) | `no valid FDT at 0x8e100000` | Linux fallback ✅ |
| `fdtcontroladdr` unset | `fdtcontroladdr is not set` | Linux fallback ✅ |
| Image missing | `sel4-experimental.uImage not found` | Linux fallback ✅ |
| Image corrupted (1 byte) | `Bad Data CRC` → `image check failed` | Linux fallback ✅ |
| Image missing and no `boot-linux.scr` | `boot-linux.scr not found, no fallback available` | stops at U-Boot ✅ |

In every fallback case `boot-linux.scr` was loaded and sourced. It then failed only because the test disk's `fitImage` is a dummy (`Wrong Image Type`), so the script printed `boot-linux.scr returned without booting Linux`.

**Defect found and fixed during testing:** the first version passed `${fdtcontroladdr}` straight to `bootm`. QEMU's U-Boot environment sets `fdt_high=0xffffffffffffffff` ("use FDT in place"), and U-Boot ≥ 2025.10 then fails with `Failed to reserve memory for fdt` / `FDT creation failed! hanging...`, because U-Boot has already reserved that memory (`boot/image-fdt.c`, compared between v2025.07 and v2025.10). The script now clears `fdt_high` in RAM before `bootm`, so U-Boot copies the FDT to free memory. That is also the path the board's saved environment takes, since it has no `fdt_high`. Two earlier defects were also fixed before testing: a `;` inside an `echo` (a hush command separator) and a misleading final message.

**Note for the verified manual procedure:** the same U-Boot change means that on any future firmware with U-Boot ≥ 2025.10 **and** `fdt_high` set to all ones, `bootm 0x8e000000 - <fdt_blob>` would fail. `setenv fdt_high` before `bootm` avoids it. The tested board's environment does not set `fdt_high`.

## Installer

Tool: [`scripts/test-installer.sh`](../../scripts/test-installer.sh). Each scenario gets a fresh 64 MiB FAT image, attached with `udisksctl loop-setup` and mounted. The harness confirms each loop device is backed by its own temp file before use.

== 1. fresh install
- dry run exits 0
- dry run wrote nothing
- apply exits 0
- boot-linux.scr = Linux script
- boot.scr = verified seL4 script
- sel4.uImage matches
- no temp files left
== 2. reinstall
- second apply exits 0
- backup still Linux script
- --verify exits 0
- --verify reports image match
== 3. seL4 boot.scr with missing backup
- refuses
- card unchanged
== 4. backup that is a TALOS script
- refuses
- card unchanged
== 5. invalid boot scripts on the card
- garbage boot.scr refused
- card unchanged
- garbage boot-linux.scr refused
- card unchanged
== 6. corrupted checksum file
- wrong hash refused
- missing entry refused
- truncated hash refused
- empty checksum file refused
- card unchanged
== 7. CRLF checksum file (Windows checkout)
- CRLF: seL4 boot.scr without backup still refused
- CRLF: card unchanged (backup not clobbered)
- CRLF: normal install succeeds
- CRLF: backup is the Linux script
== 8. missing or corrupted repository image
- missing image refused
- corrupted image refused
- card unchanged
== 9. full filesystem
- install fails
- boot.scr still Linux
- backup is Linux script
- no temp files left
- no partial sel4.uImage
- retry after freeing space succeeds
- boot.scr now seL4
== 10. interrupted installation
- abort at after-backup: interrupted (rc=99)
- abort at after-backup: boot.scr still Linux
- abort at after-backup: backup intact
- abort at after-backup: rerun succeeds
- abort at after-backup: boot.scr now seL4
- abort at after-backup: temp files cleaned
- abort at before-rename:sel4.uImage: interrupted (rc=99)
- abort at before-rename:sel4.uImage: boot.scr still Linux
- abort at before-rename:sel4.uImage: backup intact
- abort at before-rename:sel4.uImage: rerun succeeds
- abort at before-rename:sel4.uImage: boot.scr now seL4
- abort at before-rename:sel4.uImage: temp files cleaned
- abort at after-image: interrupted (rc=99)
- abort at after-image: boot.scr still Linux
- abort at after-image: backup intact
- abort at after-image: rerun succeeds
- abort at after-image: boot.scr now seL4
- abort at after-image: temp files cleaned
- abort at before-rename:boot.scr: interrupted (rc=99)
- abort at before-rename:boot.scr: boot.scr still Linux
- abort at before-rename:boot.scr: backup intact
- abort at before-rename:boot.scr: rerun succeeds
- abort at before-rename:boot.scr: boot.scr now seL4
- abort at before-rename:boot.scr: temp files cleaned
== 11. restore Linux
- restore exits 0
- boot.scr = Linux script
- backup kept
- restore without backup refused
- card unchanged
== 12. experimental install (explicit flag) and switching
- experimental apply exits 0
- boot.scr = autoboot candidate
- sel4-experimental.uImage matches
- backup is Linux script
- switch to baseline exits 0
- boot.scr = verified script
- backup still Linux script
- autoboot boot.scr without backup refused
- card unchanged
== 13. not a FAT mount point
- plain directory refused
- bad option refused
- --verify with --apply refused

The interrupted-installation scenarios use the installer's test-only `TALOS_TEST_ABORT_AT=<stage>` hook, which exits with status 99 at that point. The full-filesystem scenario fills a real FAT filesystem until `cp` hits `ENOSPC`.

## Not performed

| Test | Why |
|---|---|
| Any physical-board boot of the experimental image or autoboot script | No hardware access in this task. See the hardware test plan. |
| `fdtcontroladdr` = `bdinfo fdt_blob` on the board | Needs hardware (plan step 1). Supported only by U-Boot source analysis. |
| Board U-Boot command availability (`size`, `setexpr`, `fdt header get`) | Needs hardware (plan step 2). |
| Installer `--apply` on a physical SD card | Deliberately not done. Disposable images only. |
| Windows manual procedure | No Windows host. |
| Pulling the toolchain image by digest on a fresh machine | The digest was already present locally. Its RepoDigest matches the pinned value. |
| Linux boot via the fallback with a real `fitImage` | QEMU disk used a dummy `fitImage`. Plan step 6 covers it on hardware. |
