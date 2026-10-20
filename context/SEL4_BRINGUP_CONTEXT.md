# TALOS / PolarFire Discovery seL4 Bring-up — Context Handoff

> **Repository copy.** Sections up to "Immediate next task" are the original handoff text, unchanged except that the local username in paths/image names is replaced with `<user>`, the private workspace path is shortened, and the main repository's name is omitted. Statements there are *historical*. The section **"Verified at repository assembly (2026-10-20)"** at the end records what was re-checked against real files, and it takes precedence where they differ.

**Status:** Successful physical-board seL4 boot and sel4test execution. **118 tests passed, 49 tests disabled.** Rust runtime/Hello World is **not yet implemented**. This is a handoff of prior work, not proof of the current state of any filesystem; verify all paths and binaries locally.

## Project and hardware

- Sponsored capstone concept: Rust APEX/ARINC 653-inspired user-space runtime on seL4, targeting Microchip PolarFire SoC Discovery Kit (`MPFS-DISCO-KIT`, also referenced as 150-MPFS-DISCO-KIT-ND).
- Existing repository: the team's main TALOS runtime repository (name intentionally omitted from this repository); bring-up should be a separate GitHub-ready repo, not mixed with Rust runtime code.
- Host: Linux Mint, workspace `sel4_sandbox/sel4test` under the developer's home directory (confirm on host). User prefers documentation paths shortened to `sel4_sandbox/...`.
- Two serial channels observed on Windows: COM4 HSS, COM5 U-Boot/seL4; these are examples, not universal port assignments.
- The original Linux SD card was preserved; a spare 64GB SD card was used for seL4 bring-up. HSS/FPGA were not reflashed during the successful seL4 experiment itself.

## Verified boot outcome and image

- Physical boot path: HSS -> U-Boot -> legacy U-Boot `sel4.uImage` -> seL4 -> sel4test.
- Working ELF: `sel4test/build-polarfire/images/sel4test-driver-image-riscv-polarfire`; ELF entry/load `0x80650000`; file size of LOAD segment `0x2ea738`, memory size `0x2f1000`.
- Working uImage: `sel4test/build-polarfire/images/sel4test-driver-image-riscv-polarfire.uImage`; image load/entry `0x80650000`; payload 3,057,464 bytes, 3,057,528 bytes including legacy header. A copy was placed on SD FAT boot partition as `sel4.uImage`.
- FAT boot partition mounted on host as `/media/<user>/boot` during successful work; device was `/dev/sda1` at the time, but device/mount names can change.
- Boot partition contained `fitImage`, `boot.scr`, `boot-linux.scr` (backup), `uboot.env`, and `sel4.uImage`.
- Original Linux U-Boot boot script was backed up as `boot-linux.scr`. A custom `boot.scr` was used because the user **could not reliably interrupt U-Boot over serial**. It loaded the seL4 uImage at `0x8e000000` and validated it, but **did not automatically execute seL4**. Eventually the `RISC-V #` U-Boot prompt became available.
- Successful manual U-Boot flow: `load mmc 0:1 0x8e000000 sel4.uImage`; `iminfo 0x8e000000`; `bdinfo` to locate `fdt_blob`; `fdt addr <FDT_ADDRESS>`; `fdt header`; `bootm 0x8e000000 - <FDT_ADDRESS>`.
- One successful `bdinfo` reported `fdt_blob = 0xbf333da0`. **Do not hardcode this across boots/boards.** Booting with `bootm 0x8e000000` without the FDT failed (`Device tree not found or missing FDT support`) and required a reset.
- Expected sel4test output: `Test suite passed. 118 tests passed. 49 tests disabled. All is well in the universe.`
- Same ELF smoke-tested on QEMU: 113+ tests without failures before a 60-second timeout; this was not a full completed QEMU run.

## Build and source changes

- All actual RISC-V builds performed inside Docker `user_img-<user>` from `seL4-CAmkES-L4v-dockerfiles` (`make user`); toolchain RISC-V GCC 14.2.0, Ninja, dtc, mkimage. Host lacks the required cross-compiler/Ninja.
- Existing script: `sel4test/board/discovery/build.sh`, which invokes Docker with host path and UID mapping.
- `sel4test/cbuild/` is an untouched prior QEMU build; failed host CMake attempt moved into `sel4test/board/discovery/old-host-cmake-attempt/`.
- `sel4test/kernel/src/plat/polarfire/config.cmake`: added `KernelPolarfireBoard` choice, `icicle` default versus `discovery`.
- `sel4test/kernel/tools/dts/mpfs_discovery.dts`: copied from `sel4test/board/discovery/discovery.dts`, extracted from physical board `/sys/firmware/fdt`.
- `sel4test/kernel/src/plat/polarfire/overlay-discovery.dts`: memory alias removal, CLINT/PLIC mappings and compatibility, reserve initial 2MiB.
- Build configuration from `build.sh`:
  ```sh
  ../init-build.sh -DPLATFORM=polarfire -DKernelPolarfireBoard=discovery \
    -DRELEASE=OFF -DSMP=OFF -DUseRiscVOpenSBI=OFF -DElfloaderImage=uimage \
    -DLibSel4PlatSupportUseDebugPutChar=ON
  ninja
  ```
- `UseRiscVOpenSBI=OFF`: HSS provides SBI. `LibSel4PlatSupportUseDebugPutChar=ON`: user output routed through kernel debug putchar/SBI rather than disabled UART3. The `ElfloaderImage=uimage` request was overridden to `elf` by sel4test; build script wrapped ELF with `tools/seL4/cmake-tool/helpers/make-uimage`.
- Relevant CMakeCache values: `PLATFORM=polarfire`, `KernelPlatform=polarfire`, `KernelArch=riscv`, `KernelSel4Arch=riscv64`, `CMAKE_BUILD_TYPE=Debug`, `SIMULATION=OFF`, `Sel4testHaveCache=ON`, `Sel4testHaveTimer=OFF`, `Sel4testSimulation=OFF`; `SMP=OFF`, `KernelMaxNumNodes=1`.

## Board hardware facts discovered

- Boot hart 1; timebase 1 MHz.
- PLIC base `0x0c000000`, `ndev=186`; CLINT base `0x02000000`.
- Working console MMUART4 at `0x20106000`; MMUART3 at `0x20104000` disabled.
- Usable cached low memory: `0x80000000–0x84000000` (64MiB), `0x8a000000–0x92000000` (128MiB). First 2MiB at `0x80000000` reserved for firmware; exclude noncached aliases/high memory/HSS buffers.

## Team deployment plan (current request)

- Five other team members have **blank SD cards**, not an installed Linux image.
- They should follow Avnet's PolarFire Discovery QuickStart **through Section 5, Step 3**, then use a separate TALOS bring-up GitHub repo to copy the **already verified** `sel4.uImage` and the **verified** SD boot script.
- Avnet guide: https://github.com/avnet-iotconnect/iotc-python-lite-sdk-demos/blob/main/microchip-polarfire-soc-dk/README.md
- Avnet steps 1–5.3 include hardware/USB/Ethernet, FlashPro/FPGA setup, downloading and flashing official Linux4Microchip `.wic` SD image, serial terminal at 115200 8N1, and identifying serial ports. **Stop before IoTConnect onboarding**. Note: FPGA reflashing is a board-changing step; teammates must follow official directions and verify correct hardware image, not automate it.
- The user does **not** want a 64GB disk image distributed; keep Linux base official and layer our small seL4 files on top.
- The user **does not** want autoboot developed yet. The verified boot script and manual FDT/bootm instructions are the baseline.
- Claude Code should create a new local bring-up repository with README, concise beginner instructions, original working binaries, checksums, backup/restore procedures, source/patches, build provenance, troubleshooting and explicit validation; **no commit, push, remote creation, or changes to existing working sources/SD**. User will commit.
- Never claim a binary or source revision is verified without inspecting actual files. Do not fabricate missing boot script source, Git revision, downloads, or firmware compatibility.

## Future work (not in this handoff)

- Optional reliable automatic boot script (needs hardware testing, dynamic valid FDT handling).
- Rust `no_std` user-space hello-world / seL4 Rust bridge, capabilities, isolated partition, APEX-style runtime.

## Immediate next task after repository assembly

Develop and validate a fully automatic seL4 U-Boot boot script. The current working script is only a staging/manual-boot solution. The future autoboot should locate a valid FDT dynamically, load the verified `sel4.uImage`, execute `bootm` without serial interaction, and retain a recoverable Linux boot option. Test repeated cold boots before recommending it to teammates. Do not conflate this planned work with the verified 118-test manual boot.

---

## Verified at repository assembly (2026-10-20)

Checked read-only against the developer workstation and the working seL4 SD card. Full detail: [`docs/BUILD_PROVENANCE.md`](../docs/BUILD_PROVENANCE.md).

### Artifacts

- `sel4.uImage` on the SD card = `build-polarfire/images/….uImage` = milestone `sel4test-working.uImage`, all byte-identical. SHA-256 `29d926e476074f026c166d6032ad384d511e93dfaaa1c24b62fbed03549531f5`, 3,057,528 B, legacy RISC-V "Linux Kernel" image, load = entry = `0x80650000`, payload 3,057,464 B. Shipped as `images/sel4.uImage`.
- The SD card's verified `boot.scr` (SHA-256 `8aabe37f…f349fb`, 324 B) is shipped byte-for-byte as `boot/boot-sel4.scr`. The Linux original `boot-linux.scr` (`322ee521…db0060`, 291 B) is shipped as `boot/boot-linux.scr`.
- **The verified boot-script source is now known.** The handoff said it was not captured. It was extracted from the payload, and rebuilding with `mkimage` (original timestamp) is byte-identical (`boot/boot-sel4.cmd`). It does `load mmc 0:${distro_bootpart} ${scriptaddr} sel4.uImage` → `iminfo ${scriptaddr}` → echo. **There is no `bootm`.** It returns to U-Boot distro boot, which then tries EFI and DHCP before falling to `RISC-V #`. That is the likely reason the prompt appeared "eventually" (inferred from the env, not observed step by step).
- The card's `uboot.env` sets `scriptaddr=0x8e000000` (the source of the `0x8e000000` address), `fdt_addr_r=0x8a000000`, `kernel_addr_r=0x80200000`, `bootdelay=2`, `boot_targets= mmc0 dhcp`.

### Source

- `repo` manifest `seL4/sel4test-manifest` @ `11c9090d597e20d9a39474ec94be9f33f2964d6b`. Kernel @ `0f108291103d2797fc604fba71a1774d0ac20975`, sel4test @ `b00d84fca8890e34f6007f104372fec5e82a23d1`, seL4_tools @ `f1f63d93301cf491abc2d38ffb1a97803c218b31`. Every other project was clean at its pinned SHA.
- **Additional change missing from the handoff:** `projects/sel4test/apps/sel4test-driver/src/main.c` prints `TALOS: root task reached seL4 user space`. The string is in the shipped image, so it is part of the verified build. Captured as `patches/sel4test/0001-…`.
- Kernel changes are exactly as the handoff describes, and are captured as `patches/kernel/0001-…`. Both patches apply to clean clones at the pinned SHAs and reproduce the working files byte-for-byte.
- `CMakeCache.txt` confirms `KernelPolarfireBoard=discovery`, `UseRiscVOpenSBI=OFF`, `LibSel4PlatSupportUseDebugPutChar=ON`, `ElfloaderImage=elf` (wrapped afterwards by `make-uimage`), Debug, `SMP=OFF`, `KernelMaxNumNodes=1`, `Sel4testHaveTimer=OFF`. The CMake-recorded compiler is GCC 14.2.0. The dockerfiles checkout is at `285ed6985036e62e0db59cc92c242efcf60ae6e7`.

### Board / firmware

- Linux4Microchip **2026.04.1** confirmed on the card's rootfs (`/lib/modules/6.18.17-linux4microchip-2026.04.1-…`). U-Boot `2025.07-linux4microchip-2026.04` and FPGA reference design `…-reference-rtl-v2507` confirmed from the board-extracted DTS. HSS 0.99.53 remains historical only.
- Expected final lines (from `main.c`): `Test suite passed. 118 tests passed. 49 tests disabled.` then `All is well in the universe`, **with no trailing period**.
- Avnet guide: Section 5 Step 3 = "observe 3 COM port entries". Step 4 ("select the middle-numbered port") is where teammates stop. The middle port is the Linux/U-Boot console, consistent with the COM5 observation.

### Publication cautions

- The verified binary embeds 594 absolute build paths, including the local username (assertion `__FILE__` strings), and the original board's MAC address (from the extracted DTS). Changing either requires a rebuild, which would be a new, unverified image. This is the owner's decision.

### Next milestone (unchanged in intent, now explicit)

1. **Automatic seL4 U-Boot boot script.** Load the verified `sel4.uImage`, find and validate the FDT at run time (not `0xbf333da0`), `bootm` automatically, keep a Linux recovery path, and pass repeated cold-boot testing before replacing `boot-sel4.scr` as the recommended script. Not started in this repository.
2. Then the Rust `no_std` user-space work (future scope).

### Update 2026-10-20: experimental build and autoboot candidate

- Clean, reproducible experimental image built from GitHub at the pinned SHAs. It uses the same patches and settings, a generic build path with prefix maps, and a zeroed board MAC. It is privacy-audited and passes 118/49 **under QEMU only**. Its load/entry address is `0x80640000` (smaller payload). See `experimental/`.
- Autoboot candidate `experimental/boot/boot-auto.cmd`:
  - uses `${fdtcontroladdr}`, which U-Boot v2025.07 sets from the same `gd->fdt_blob` that `bdinfo` prints
  - validates the FDT, checks overlap, loads at `0x8e000000`, checks the CRC
  - clears `fdt_high` so `bootm` relocates the FDT
  - falls back to `boot-linux.scr` on any failure

  It was tested end to end with U-Boot 2025.10 in QEMU, including every failure branch, and is **not tested on the board**. The verified `boot-sel4.scr` and manual procedure remain the baseline.
- Finding: U-Boot ≥ 2025.10 with `fdt_high` set to all ones rejects the in-place FDT (`Failed to reserve memory for fdt`). The board's saved environment does not set `fdt_high`.
