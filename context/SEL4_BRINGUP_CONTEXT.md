# TALOS / PolarFire Discovery seL4 Bring-up — Context Handoff

> **Repository copy.** Sections up to "Immediate next task" are the original handoff text, unchanged except that the local username in paths/image names is replaced with `<user>`, the private workspace path is shortened, and the main repository's name is omitted. Statements there are *historical*. The sections from **"Verified at repository assembly (2026-10-20)"** onward record later, re-checked work and take precedence where they differ. **Current state: see the dated updates at the end; the latest wins.**

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

### Update 2026-10-21: current state (supersedes the above where they differ)

- **Image:** the clean experimental build passed on the board: installed with its autoboot script, it booted with no typing and printed `118 tests passed. 49 tests disabled.` It is now the repository's only image, renamed `images/sel4test.uImage` (same bytes, SHA-256 `2c986076…`, load `0x80640000`). The autoboot script is `boot/boot-auto.scr` (only the image name and banner changed). The first image `sel4.uImage` and staging script `boot-sel4.scr` were removed (git history). `experimental/` was folded into `images/`, `boot/`, `patches/`, `scripts/`, `reports/`.
- **Rebuild:** `scripts/build-sel4test.sh <empty-dir>` reproduced the image byte-for-byte again on 2026-10-21.
- **Linux serial:** the board's FT4232H (`1514:2008`) gets only interface 2 bound by default. `echo 1514 2008 > /sys/bus/usb-serial/drivers/ftdi_sio/new_id` (root) binds all: `ttyUSB1` = HSS (`>>`), `ttyUSB2` = U-Boot/seL4, `ttyUSB0` = JTAG. Only one program may read a port at a time.
- **Network boot:** U-Boot has gigabit Ethernet, `dhcp`, `ping`, `tftpboot` (no `wget`). `tftp/serve.sh` runs dnsmasq TFTP in Docker; the host firewall needs inbound UDP 69 allowed; don't use `--tftp-single-port`. See `docs/NETBOOT.md`.
- **Rust:** `rust-root-task/` builds a `no_std` rust-sel4 root task with the sel4test kernel configuration and the C elfloader. On the board it printed `Hello from Rust on seL4!` and `TALOS: Rust root task running, 50 untyped regions available`.
- **`bdinfo`:** `fdt_blob = 0xbf333da0` in every session so far; still read it each time.
- **Next:** see the 2026-10-22 update.

### Update 2026-10-22

- **Scope:** this repository is the PolarFire Discovery Kit bring-up only; `rust-root-task/` remains a minimal toolchain check.
- **Board MAC:** zeroed in `board/discovery/discovery.dts/.dtb` and `patches/kernel/0001` (the separate `0002` patch was folded in). A clean rebuild is still byte-identical (`2c986076…`). The original MAC remains in git history, so publish from a fresh history. This resolves the "Publication cautions" item above.
- **Board checks:** repeated cold boots confirmed. User LEDs driven from U-Boot by GPIO register writes; peripheral map in `docs/PERIPHERALS.md`.
- **Still open on the board:** autoboot fallback to Linux, the renamed autoboot script, the pinned-checkout Rust image.

### Update 2026-10-25: hands-off workflow (supersedes the above where they differ)

- **Linux serial, corrected:** after the `new_id` fix, `ttyUSB` numbers follow the order the channels were bound, not the interface order. On one host the U-Boot console stayed `ttyUSB0` and HSS became `ttyUSB2` until a replug. Never rely on `ttyUSB` numbers. Use `/dev/serial/by-id/*FlashPro5*-ifNN-port0` or the names from `host/udev/99-polarfire-discovery.rules`: `/dev/polarfire-hss` (if01), `-uboot` (if02), `-uart3` (if03), `-jtag` (if00). The rule also does the `new_id` binding on every plug-in. Install with `scripts/pf install-udev`.
- **Remote reset:** the HSS console stays live after boot and has a `RESET` command (`help` lists `YMODEM BOOT RESET HELP VERSION UPTIME DEBUG MEMTEST QSPI EMMC MMC SDCARD PAYLOAD SPI RESUME ECC`). Sending `RESET` reboots the board into HSS → U-Boot. This is what makes network boot fully remote: only power-cycling and SD card swaps need someone at the board.
- **New tools** (all in the repo, no host-specific setup beyond Docker and `dialout`):
  - `scripts/network-flash.sh <image>`: checks the image header and load-address overlap, stages it in `tftp/root/`, starts the TFTP server and test-fetches block 1, sends HSS `RESET`, stops autoboot, then runs `setenv autoload no` / `dhcp` (3 tries) / `tftpboot` (2 tries, byte count checked) / `crc32` (compared with the host's CRC-32) / `iminfo` / `bootm 0x8e000000 - ${fdtcontroladdr}`. It watches for `Test suite passed` (auto-detected for sel4test images), `--expect REGEX`, or `--idle` silence. Exit 0 pass, 1 image failure, 2 host problem, 3 board/U-Boot problem, 4 timeout. Logs go to `logs/` (git-ignored). RAM only: no `saveenv`, the SD card is never written.
  - `scripts/serial-share.py`: a broker that owns a serial port and copies its output to every client (a Unix socket under `$XDG_RUNTIME_DIR/serial-share/`), so a console and `network-flash.sh` can watch the same port. It starts on demand, exits about 3 s after the last client leaves, and records its PID next to the socket so tools can tell it apart from programs that don't share. `network-flash.sh` always goes through it and refuses to start if anything else (e.g. plain `picocom`) holds a port.
  - `scripts/pf`: one front end for teammates: `status`, `flash [image]`, `console`, `hss`, `reset [-y]`, `tftp`, `install-udev`.
- **Verified on the board (2026-10-25, the team's kit, Linux4Microchip 2026.04.1 firmware as recorded above):**
  - `network-flash.sh images/sel4test.uImage`, run over SSH with nobody at the board: `PASSED: Test suite passed. 118 tests passed. 49 tests disabled.`, CRC32 `eb98aed0` matched. Repeated about 5 times, all passed.
  - The same with a shared console open during the flash: the console saw the identical run (all test lines) and stayed open.
  - HSS `RESET` sent through the share broker while an HSS console was open: the reset and the HSS boot were visible in that console.
  - A non-sharing program holding the U-Boot port makes `network-flash.sh` refuse immediately (exit 2).
  - The udev rule on Debian 13 (kernel 6.12): all four channels bound, the `/dev/polarfire-*` names correct.
- **Not yet run on the board:** `scripts/pf` itself. It was written after the board left. It calls the same `network-flash.sh` and `serial-share.py` that were verified, and only `pf status` was run (with the board attached). Also untested: `network-flash.sh --console`, `--no-reset`, `--expect` on a non-sel4test image (e.g. the Rust root task), and `--idle` mode. Try these first when the board is back.
- **Network boot environment notes:** the board got a DHCP lease from an ordinary home/lab router in about 20 ms. A 3 MB image transfers in a few seconds over wired Ethernet. The TFTP server binds to the host's default-route interface (`IFACE=` overrides it).
- **Next:** run the untested `pf` paths above. Then use `scripts/pf flash <image> --expect '<banner>'` as the inner loop for root-task work, e.g. `--expect 'Hello from Rust on seL4!'` for `rust-root-task/`.

### Update 2026-10-26: loading images into RAM over USB (serial YMODEM)

- **What "USB" means on this kit:** the only USB link is USB-C #1 → FT4232H. The SoC's USB OTG (MUSB, `0x2020_1000`) is `status = "disabled"` in the device tree, and the board's U-Boot (2025.07-linux4microchip-2026.04) has **no** `usb`, `ums`, `dfu` or `fastboot` commands. U-Boot does have `loadx`, `loady` and `loadb`. HSS has a `YMODEM` command, but it is for writing eMMC/QSPI: don't use it (FPGA/HSS rule).
- **Verified on the board (2026-10-26, RAM only, nothing written):** `loady 0x8e000000 <baud>` on the U-Boot console, with a host YMODEM sender (1K blocks, CRC-16), then `crc32 0x8e000000 ${filesize}` (`loady` sets `filesize` but **not** `fileaddr`), `iminfo`, `bootm 0x8e000000 - ${fdtcontroladdr}`. `images/sel4test.uImage` (3,021,688 bytes): CRC32 `eb98aed0` matched every time, 0 retries, and booted to `118 tests passed. 49 tests disabled.`

  | Baud | FTDI latency timer | Transfer time |
  |---|---|---|
  | 921600 | 16 ms (default) | 47.2 s |
  | 1500000 | 16 ms (default) | 47.2 s |
  | 921600 | 1 ms | 35.4 s |
  | 1500000 | 1 ms | 23.6 s (also booted) |
  | 3000000 | 1 ms | fails: no `C` from the receiver |

- **Findings:** with the default 16 ms latency timer, YMODEM is limited by ACK round trips (16.0 ms × 2951 blocks), whatever the baud rate. A regular user can set `ASYNC_LOW_LATENCY` with `TIOCSSERIAL` (ftdi_sio then uses a 1 ms timer until replug), no root needed. The UART clock is 150 MHz, so U-Boot's 16550 divisor gives 937500 for 921600 and 1562500 for 1500000. Both work.
- **Tools now in the repo (same day):** `scripts/usb-flash.sh` (YMODEM via `loady`, default 1.5 Mbaud, 1 ms latency during the transfer, one retry, same options/exit codes/log style as `network-flash.sh` plus `--baud`). **`scripts/pf flash` is now USB; `pf flash --lan` is the old network boot.** `scripts/serial-share.py` gained a control socket (`<tty>.ctl`: `baud N`, `lowlat 0|1`, one holder, settings restored when it disconnects) and a queued port writer (it used to drop bytes on a partial non-blocking write). Docs: new `docs/FLASHING.md` (USB first, then network) and `docs/SHARED_CONSOLE.md` (people, scripts and agents on one port); README, NETBOOT, SETUP, TROUBLESHOOTING, rust-root-task, CLAUDE.md now treat USB as the default.
- **Verified on the board (2026-10-26) with those tools:** `pf flash` with a second shared client watching (23.6 s transfer, 118 passed; the watcher saw everything); `--baud 921600 --expect 'All is well in the universe'`; `--no-reset --baud 115200` (268 s); Ctrl-C mid-transfer (exit 130, port back to 115200/16 ms, next `pf flash` passed); `pf flash --lan` regression after the broker change (passed).
- **Not run on the board yet:** `pf flash --console`, the manual picocom/`sb` and Tera Term YMODEM steps in `docs/FLASHING.md`. TFTP is still faster (a few seconds) when Ethernet is available.

### Update 2026-10-27: Anduril-TALOS LED image over USB

- **Built:** Anduril-TALOS `nix build .#c-led-image-mpfs-disco-kit` (at `beddb8b`). On a Linux host the Nix sandbox has no `/usr/bin/env`, so the kernel's `cpp_gen.sh` failed; adding `patchShebangs source` after the staged sources in Anduril-TALOS `nix/c-system.nix` fixed it (not committed there yet). `image.elf` (SHA-256 `a938addc…`, load/entry `0x80520000`) was wrapped with the kernel tree's `make-uimage`, as for sel4test: 1,723,720 bytes, SHA-256 `e86f369f…`.
- **Verified on the board (2026-10-27, RAM only):** `scripts/pf flash <talos-led.uImage> --expect 'TALOS_LED partition=\d+ led=3'`: CRC32 `88fc1a4e` matched, elfloader on hart 1 used the DTB bundled in its CPIO, CapDL loader done, `TALOS_CLOCK ready`, partitions 1–3 `pm ready`, clock IRQs and `TALOS_LED` lines for LED1/2/3. So the TALOS image boots through U-Boot `bootm` too, not only as an HSS payload as Anduril-TALOS `docs/hardware.md` describes.
- **Not checked:** the physical LEDs (nobody at the board) and the 250/500/750 ms periods over a longer run. Console lines from different partitions can interleave mid-line.
