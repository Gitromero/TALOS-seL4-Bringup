# seL4 Hardware Bring-Up — PolarFire SoC Discovery Kit

**Project:** TALOS capstone  
**Target:** Microchip MPFS-DISCO-KIT, RISC-V 64-bit  
**Result:** seL4 + sel4test booted on physical hardware (**118 tests passed, 49 disabled**), first by hand and then fully automatically from a reproducible image; a `no_std` Rust root task running on seL4; images network-booted from U-Boot  
**Date:** October 2026

> **About this copy (read first).** Sections 1–15 are the original bring-up engineering log; sections 16–20 continue it from the repository's first revision to the current state. Sections 1–15 were copied into the TALOS bring-up repository with three kinds of changes: (1) local usernames in paths/Docker image names were replaced with `<user>` and the host laptop model was generalised; (2) the original "Appendix A" (the verbatim Claude prompt used for the port) was left out of this repository; (3) short **"Update (repository assembly)"** notes were added where later inspection of the real SD card and source tree superseded or sharpened a statement. Everything else is the historical text. Where this guide and [`BUILD_PROVENANCE.md`](BUILD_PROVENANCE.md) disagree, `BUILD_PROVENANCE.md` reflects the files actually shipped in this repository.
>
> Teammates who only want to boot seL4 should use the [root README](../README.md) instead; this file is background.
>
> **Path convention:** All project paths in this guide are relative to the original developer workspace `sel4_sandbox/` (not this repository), unless stated otherwise. This guide distinguishes the original Claude preparation log (written before hardware testing) from the subsequent, verified physical-board result.

## 1. Objective and result

We had already compiled and tested seL4 in QEMU. The next milestone was to port its PolarFire support to the **Discovery Kit** and run seL4 on the real board without replacing its working HSS firmware, FPGA configuration, or original Linux SD card. The successful chain was:

```text
PolarFire SoC → HSS → U-Boot → seL4 elfloader → seL4 kernel → sel4test
```

The physical board's COM5 console ended with:

```text
Test suite passed. 118 tests passed. 49 tests disabled.
All is well in the universe
```

This confirms the enabled test suite passed on hardware. Disabled tests were not executed; it is not proof that every peripheral, SMP feature, or SBI extension works.

## 2. Hardware, firmware, and host

| Component | Verified or recorded details |
|---|---|
| Board | Microchip PolarFire SoC Discovery Kit (MPFS-DISCO-KIT) |
| Host | Linux Mint 22.3, x86-64 laptop |
| Firmware | HSS 0.99.53 |
| U-Boot | `2025.07-linux4microchip-2026.04` |
| Existing Linux | Linux4Microchip 2026.04.1 |
| SBI | Specification v2.0; implementation ID `0x8`, version `0x10002` |
| HSS console | Windows COM4 |
| U-Boot, Linux, seL4 console | Windows COM5 |
| Existing Linux card | Preserved unchanged |
| seL4 test card | Separate spare microSD with FAT boot partition |

HSS sometimes required selecting `sdcard` and then `boot` to proceed to U-Boot. We used the existing firmware; **we did not flash HSS or FPGA fabric**.

## 3. Working directory and source tree

```text
sel4_sandbox/
├── sel4test/
│   ├── .repo/
│   ├── board/discovery/
│   │   ├── discovery.dtb
│   │   ├── discovery.dts
│   │   ├── build.sh
│   │   └── bringup.md
│   ├── cbuild/                         # pre-existing QEMU build, untouched
│   ├── build-polarfire/                # physical-board build
│   ├── kernel/
│   ├── projects/
│   └── tools/
└── milestones/
    └── sel4test-polarfire/            # preserved milestone
```

The seL4 checkout uses a `repo` manifest and nested source repositories; the `sel4test/` directory was **not** itself a top-level Git repository. The kernel subtree does have Git history. Preserve local changes and untracked files, not just commit hashes.

## 4. Initial inspection of the board

The board booted its original Linux successfully. We extracted the actual live firmware device tree from `/sys/firmware/fdt` and converted it to readable DTS with `dtc`. The resulting files were kept at:

```text
sel4test/board/discovery/discovery.dtb
sel4test/board/discovery/discovery.dts
```

A reproducible extraction procedure **on the running board**, provided `dtc` is installed, is:

```bash
cp /sys/firmware/fdt /tmp/discovery.dtb
dtc -I dtb -O dts -o /tmp/discovery.dts /tmp/discovery.dtb
```

Copy the resulting files back to `sel4test/board/discovery/`. These commands describe how to repeat extraction; the original transfer command was not retained.

### Hardware facts from the extracted DTS

| Item | Actual board | seL4 configuration |
|---|---|---|
| Boot hart | Hart 1; hart 0 is E51/disabled | `FIRST_HART_ID 1` |
| Timebase | `0xf4240` = 1 MHz | `TIMER_FREQUENCY 1000000` |
| PLIC | `0x0c000000`, `sifive,plic-1.0.0`, 186 sources | `MAX_IRQ 186`, `riscv_plic0` |
| CLINT | `0x02000000`, `sifive,clint0` | Overlay adds `riscv,clint0` compatibility |
| Console | MMUART4 `0x20106000`, `ns16550a`, 115200, 32-bit registers, shift 2 | Debug output through SBI |
| MMUART3 | `0x20104000`, disabled | Avoided by debug-putchar setting |

### DDR aliases and memory safety

The MSS exposes DDR through multiple address windows. We deliberately did **not** tell seL4 that all aliases were independent RAM:

| Range | Meaning / treatment |
|---|---|
| `0x80000000–0x84000000` | 64 MiB cached-low RAM; first 2 MiB reserved for firmware |
| `0x84000000–0x8A000000` | Reserved/fabric buffer; not available RAM |
| `0x8A000000–0x92000000` | 128 MiB cached-low RAM |
| `0xC4000000` (96 MiB) | Noncached alias / DMA pool; excluded |
| `0x1022000000` (480 MiB) | Cached-high alias, includes HSS buffer near `0x103FC00000`; excluded |
| `0x1412000000` (256 MiB) | Noncached alias / DMA pool; excluded |

The first hardware image used only the two cached-low slices. The seL4 elfloader, kernel, DTB, and rootserver were placed within the first 64 MiB bank.

## 5. Claude Code task and what changed

The full original Claude Code prompt was preserved verbatim in the original guide's Appendix A and as `claude-original-prompt.md` in the developer's local milestone directory (not included in this repository). It instructed Claude to inspect the repository, adapt the existing PolarFire/Icicle support to the Discovery Kit, produce a bootable image, avoid touching QEMU and the original SD card, and maintain `sel4test/board/discovery/bringup.md`.

The actual implementation recorded in `bringup.md` was:

1. `sel4test/kernel/src/plat/polarfire/config.cmake`: added `KernelPolarfireBoard` choice, retaining `icicle` as default and adding `discovery`.
2. `sel4test/kernel/tools/dts/mpfs_discovery.dts`: copied the extracted board DTS.
3. `sel4test/kernel/src/plat/polarfire/overlay-discovery.dts`: removed unsafe aliased memory nodes, configured `seL4,kernel-devices` for CLINT/PLIC, fixed CLINT compatible string, and reserved 2 MiB at `0x80000000`.
4. `sel4test/board/discovery/build.sh`: orchestrated the Docker build and wrapped the final ELF as a U-Boot legacy image.
5. `sel4test/board/discovery/bringup.md`: tracked findings, commands, artifacts, and pre-hardware blockers.

> **Update (repository assembly):** inspecting the source tree found one more local change that this list omitted: `projects/sel4test/apps/sel4test-driver/src/main.c` prints `TALOS: root task reached seL4 user space` at the start of `main()`. The string was present in the first image (`sel4.uImage`), so this change is part of the verified build. It is captured in [`patches/sel4test/`](../patches/sel4test/) and is in the current image too.

### Why not use the Icicle DTS unchanged?

The upstream PolarFire configuration used `mpfs_icicle.dts` and assumed a contiguous 1 GiB RAM window. The Discovery Kit's firmware DT had different usable-memory windows, aliases, and UART configuration. A separate `discovery` board choice avoided changing the existing Icicle default.

## 6. Docker toolchain and build

**Important correction:** The host did **not** have Ninja or the RISC-V cross-compiler installed. The working QEMU build had been made inside Docker image `user_img-<user>`, from `seL4-CAmkES-L4v-dockerfiles` (`make user`). The image supplied RISC-V GCC `riscv64-unknown-elf-` **14.2.0**, Ninja, `dtc`, and `mkimage`.

The first host-side attempt failed due to missing GCC and Ninja. That attempt was moved to:

```text
sel4test/board/discovery/old-host-cmake-attempt/
```

It was **not deleted**. The original `sel4test/cbuild/` QEMU build was left untouched.

### Recommended repeatable entry point

From `sel4_sandbox/`, inspect and run the preserved wrapper:

```bash
sed -n '1,240p' sel4test/board/discovery/build.sh
bash sel4test/board/discovery/build.sh
```

The wrapper mounts the checkout at its host path and runs as the host UID, so generated files do not become root-owned. Its exact implementation is preserved in the source snapshot and milestone copy. Prefer it over inventing a new Docker command.

### Recorded configure-and-build commands (inside the container)

Run from `sel4test/build-polarfire/`:

```bash
../init-build.sh \
  -DPLATFORM=polarfire \
  -DKernelPolarfireBoard=discovery \
  -DRELEASE=OFF \
  -DSMP=OFF \
  -DUseRiscVOpenSBI=OFF \
  -DElfloaderImage=uimage \
  -DLibSel4PlatSupportUseDebugPutChar=ON
ninja
```

- `UseRiscVOpenSBI=OFF`: HSS already supplies M-mode SBI services; U-Boot hands off in S-mode.
- `LibSel4PlatSupportUseDebugPutChar=ON`: userspace printing uses `seL4_DebugPutChar` → kernel → SBI, rather than disabled MMUART3.
- `SMP=OFF`: initial single-core configuration.
- `RELEASE=OFF`: debugging enabled.
- `ElfloaderImage=uimage` was **overridden to ELF** by sel4test's `ApplyData61ElfLoaderSettings`; `build.sh` subsequently used `tools/seL4/cmake-tool/helpers/make-uimage` to wrap the ELF.

### Effective CMake cache settings

Recovered from `sel4test/build-polarfire/CMakeCache.txt` after the successful build:

```text
PLATFORM=polarfire
KernelPlatform=polarfire
KernelArch=riscv
KernelSel4Arch=riscv64
CMAKE_BUILD_TYPE=Debug
SIMULATION=OFF
Sel4testAllowSettingsOverride=OFF
Sel4testHaveCache=ON
Sel4testHaveTimer=OFF
Sel4testSimulation=OFF
```

The cache also identified `build-polarfire/gcc.cmake`, `/usr/bin/riscv64-unknown-elf-gcc-ar`, and `/usr/bin/riscv64-unknown-elf-gcc-ranlib` **inside the container**. `Sel4testHaveTimer=OFF` refers to the test framework's timer support, not necessarily to absence of kernel timing.

## 7. Generated images and layout

Under `sel4test/build-polarfire/images/`:

```text
sel4test-driver-image-riscv-polarfire         # ELF64 RISC-V
sel4test-driver-image-riscv-polarfire.uImage  # legacy U-Boot image
```

ELF details recorded by Claude:

- Entry point: `0x80650000`
- LOAD segment address: `0x80650000`
- File size of LOAD segment: `0x2ea738`
- Memory size of LOAD segment: `0x2f1000`

Legacy image header, later verified by U-Boot:

```text
Image Type: RISC-V Linux Kernel Image (uncompressed)
Data Size: 3057464 Bytes
Load Address: 80650000
Entry Point: 80650000
Verifying Checksum ... OK
```

The `.uImage` was **3,057,528 bytes** including the 64-byte header. The ELFloader image is labeled as a Linux kernel for U-Boot compatibility; the payload boots seL4.

Recorded physical image layout from the earlier QEMU smoke test:

```text
kernel:     0x80200000–0x80224000
DTB:        0x80224000–0x8022a000
rootserver: 0x8022a000–0x80630000
elfloader:  0x80650000–0x80941000
```

All lie in the first 64 MiB RAM bank, with the firmware reservation below `0x80200000`.

## 8. QEMU smoke test before hardware

The same ELF was tested with:

```bash
qemu-system-riscv64 -machine virt -smp 2 -m 2G -bios default -kernel <ELF>
```

The elfloader switched to hart 1 using HSM, seL4 booted, both memory regions were reported, and userspace printed:

```text
TALOS: root task reached seL4 user space
```

sel4test completed more than 113 tests without reported failures before a 60-second timeout. **This was a smoke test only**, not evidence of board firmware/SBI compatibility. The later hardware run is the definitive result.

## 9. Prepare the spare SD card

We retained the original Linux card and used a separate spare card. Its FAT boot partition appeared on the laptop as `/dev/sda1` and mounted at `/media/<user>/boot` **in that session**. Do not assume those device names remain the same.

After verifying the mount with `lsblk`, the seL4 image was copied to the FAT boot partition as `sel4.uImage`:

```bash
cp sel4test/build-polarfire/images/sel4test-driver-image-riscv-polarfire.uImage \
  /media/<user>/boot/sel4.uImage
sync
```

The spare card retained the Linux `fitImage` and `uboot.env`. Its original Linux `boot.scr` was backed up as `boot-linux.scr`. A modified `boot.scr` was used to **load and validate** the seL4 image at `0x8e000000` without automatically executing it. The essential U-Boot operations were:

```text
load mmc 0:1 0x8e000000 sel4.uImage
iminfo 0x8e000000
```

The original script used the Linux `fitImage` and `bootm start/loados/ramdisk/prep/go`. The exact custom `boot.scr` source and compilation command were not captured; preserve the working file from the spare card if you want to reproduce the automatic load step. Manual U-Boot commands below are sufficient for booting.

> **Update (repository assembly):** the working `boot.scr` and `boot-linux.scr` were copied byte-for-byte from the spare card. Their text was extracted from the legacy-image payloads, and rebuilding that text with `mkimage` (using the original header timestamp) reproduced **both binaries byte-for-byte**. The staging script loaded `sel4.uImage` to `${scriptaddr}` and did not run `bootm`; the card's saved `uboot.env` sets `scriptaddr=0x8e000000`. The staging script was shipped as `boot/boot-sel4.scr` in the repository's first revision and has since been replaced by the autoboot script (§16); it is in git history. [`boot/boot-linux.scr`](../boot/boot-linux.scr) is still shipped.

## 10. U-Boot hardware boot and first failure

Connect to COM5, boot the board, and reach the `RISC-V #` prompt. The HSS firmware console is COM4.

The image was loaded manually:

```text
RISC-V # load mmc 0:1 0x8e000000 sel4.uImage
3057528 bytes read in 48 ms (60.7 MiB/s)
```

The **first** boot attempt used:

```text
RISC-V # bootm 0x8e000000
```

U-Boot validated the image, then failed:

```text
Working FDT set to 0
Loading Kernel Image to 80650000
Device tree not found or missing FDT support
    ### ERROR ### Please RESET the board ###
```

This happened **before seL4 executed**. Because the legacy image was marked as a RISC-V Linux kernel, U-Boot expected an FDT argument. We reset and loaded the image again.

## 11. Resolve FDT and boot successfully

Inspect U-Boot's current board information:

```text
RISC-V # bdinfo
```

On the successful session, `bdinfo` reported:

```text
fdt_blob = 0xbf333da0
```

We selected and validated it:

```text
RISC-V # fdt addr 0xbf333da0
Working FDT set to bf333da0
RISC-V # fdt header
magic:                  0xd00dfeed
totalsize:              0x5065 (20581)
version:                17
last_comp_version:      16
```

Then booted:

```text
RISC-V # bootm 0x8e000000 - 0xbf333da0
```

The arguments are the legacy image address, a `-` indicating no initrd, and the valid FDT address. **Do not hardcode the FDT address for future sessions**: read the current `fdt_blob` from `bdinfo` and validate it first. The FDT passed here satisfies U-Boot's boot contract; the seL4 kernel was also compiled with its board-specific DTS.

This command successfully handed control to seL4 on the physical Discovery Kit.

## 12. Physical sel4test results

The board's COM5 console showed seL4 userspace and the sel4test suite running, including thread/TLS, VSpace, and other tests. Some tests intentionally triggered kernel diagnostics such as invalid vspace roots or unavailable ASID pools; the corresponding tests passed.

Final output:

```text
Test suite passed. 118 tests passed. 49 tests disabled.
All is well in the universe
```

| Result | Count |
|---|---:|
| Passed | 118 |
| Disabled | 49 |
| Reported failures | 0 |

The successful execution demonstrates that the required firmware/SBI operations for this configuration, kernel startup, userspace startup, and enabled sel4test cases worked. It does **not** prove every legacy SBI operation, timer test, SMP path, or peripheral is supported.

## 13. Preserve the complete working milestone

**Do this before starting Rust development.** The archive script accompanying this guide is `preserve_sel4_milestone.sh`. Place it and the accompanying `BRINGUP_GUIDE.md` and `claude-original-prompt.md` under `sel4_sandbox/` and run:

```bash
cd sel4_sandbox
bash preserve_sel4_milestone.sh
```

It creates `milestones/sel4test-polarfire/` and preserves:

- The exact working `.uImage` and its SHA-256 checksum.
- `build-polarfire/CMakeCache.txt` and `gcc.cmake` if present.
- **All of `board/discovery/`**, including `build.sh`, `bringup.md`, `discovery.dts`, `discovery.dtb`, and the old host attempt.
- The three relevant kernel configuration/DTS files as separately accessible copies.
- A full `sel4test/` source snapshot, excluding generated `cbuild/` and `build-polarfire/` directories and the old host build attempt from the compressed archive.

The source archive captures the nested repositories' current files, including local changes. It can be large, especially if `.repo/` contains repository object stores; check available disk space first. It is a **snapshot**, not a substitute for version-controlled review. Keep the original source tree untouched.

The script also copies `BRINGUP_GUIDE.md` and `claude-original-prompt.md` into the milestone folder when those files are alongside the script.

If the spare SD card is still mounted, optionally preserve its exact working boot scripts and image separately:

```bash
cp /media/<user>/boot/boot.scr milestones/sel4test-polarfire/boot.scr
cp /media/<user>/boot/boot-linux.scr milestones/sel4test-polarfire/boot-linux.scr
```

Only do this after verifying the correct mount and file names. Do not modify the original Linux SD card.

> **Update (repository assembly):** the milestone script and archive above exist only on the original developer's machine. This repository instead ships minimal patches against pinned upstream SHAs and an image rebuilt from them (§16); see [`BUILD_PROVENANCE.md`](BUILD_PROVENANCE.md).

### Verify preservation

```bash
cd milestones/sel4test-polarfire
sha256sum -c SHA256SUMS
ls -lh sel4test-working.uImage source-snapshot.tar.gz
ls board/discovery/
```

## 14. Known-good manual reboot recipe

At COM5's `RISC-V #` prompt:

```text
load mmc 0:1 0x8e000000 sel4.uImage
iminfo 0x8e000000
bdinfo
fdt addr <CURRENT_FDT_BLOB_ADDRESS>
fdt header
bootm 0x8e000000 - <CURRENT_FDT_BLOB_ADDRESS>
```

`<CURRENT_FDT_BLOB_ADDRESS>` is a placeholder, **not literal U-Boot syntax**. On the successful session it was `0xbf333da0`.

## 15. Stopping point and next milestone

**Completed:** seL4/sel4test hardware bring-up; 118 enabled tests passed on the Discovery Kit. Preserve the working binary, source tree, Docker wrapper, board configuration, and original prompt before continuing.

**Next, but not part of this milestone:** build a separate `no_std` Rust seL4 root task that prints `Hello from Rust on seL4!` on COM5. Keep the passing sel4test image as a recovery baseline. IPC and isolated partitions come later.

---

> **Update:** both next steps are done. The automatic boot script is §16, and the Rust root task is §18.

---

# Part 2: from the first repository revision to Rust (October 2026)

Paths in sections 16–20 are relative to this repository unless stated otherwise.

## 16. Reproducible image and automatic boot

The first image could not be shared as-is: it embedded 594 absolute build paths containing the developer's username, plus the board's MAC address, and it could not be rebuilt byte-for-byte. It also needed `bootm` typed at `RISC-V #` on every boot.

**Clean, reproducible build.** [`scripts/build-sel4test.sh`](../scripts/build-sel4test.sh) fetches the pinned manifest into an empty directory, checks every project SHA, applies the patches in [`patches/`](../patches/README.md), and builds inside the pinned `trustworthysystems/camkes@sha256:77dcf9c7…` container with the checkout mounted at a generic path (`/build/sel4test`) and `-ffile-prefix-map`. The only source change beyond the first image zeroes the board MAC in the kernel's device tree (a separate patch `kernel/0002` at the time, later folded into `kernel/0001`). Result: `images/sel4test.uImage`, SHA-256 `2c986076…`, load/entry `0x80640000` (the ELF loader sits 64 KiB lower than before because the payload lost about 35 KB of path strings). Three independent builds were byte-identical. All 11 generated kernel platform configuration files are identical to the first build's.

**Automatic boot.** [`boot/boot-auto.cmd`](../boot/boot-auto.cmd) replaced the staging script. It finds the FDT itself from `${fdtcontroladdr}` (the value `bdinfo` prints as `fdt_blob`), checks it with `fdt addr`, checks that the image's load range doesn't overlap it, loads the image, checks its CRC with `iminfo`, clears `fdt_high` and runs `bootm 0x8e000000 - ${fdtcontroladdr}`. Any failed check falls back to `boot-linux.scr`. Every branch was exercised under QEMU with U-Boot 2025.10 ([test results](../reports/TEST_RESULTS.md)).

**On the board.** Installed on the SD card (image then named `sel4-experimental.uImage`, with `boot-auto.scr` as `boot.scr`), the board went from power-on to the end of sel4test with no typing:

```text
Test suite passed. 118 tests passed. 49 tests disabled.
All is well in the universe
```

This became the repository's only image. It was renamed `sel4test.uImage` (same bytes), the script's file name and banner were updated to match, and the first image and staging script were removed ([boot/README.md](../boot/README.md#history)). The installer still recognises both earlier scripts by hash.

## 17. Linux host as the serial console

**Finding.** On Linux only one serial port appeared: `/dev/ttyUSB0`. The board's USB-C connector #1 leads to an FTDI FT4232H (`1514:2008`, "Microsemi Embedded FlashPro5") with four channels: interface 0 is JTAG, interfaces 1–3 are UARTs. `ftdi_sio` had bound only interface 2.

**Fix.** Add the board's USB ID to the driver, which binds all four channels:

```bash
sudo sh -c 'echo 1514 2008 > /sys/bus/usb-serial/drivers/ftdi_sio/new_id'
```

`new_id` lives under `/sys/bus/usb-serial/`, not `/sys/bus/usb/drivers/ftdi_sio/`. The result, identified by what each port printed:

| Port | FT4232H interface | Role |
|---|---|---|
| `/dev/ttyUSB0` | 0 | JTAG channel, not a console |
| `/dev/ttyUSB1` | 1 | HSS console: answered Enter with `>>` (Windows COM4) |
| `/dev/ttyUSB2` | 2 | U-Boot / seL4 console (Windows COM5) |
| `/dev/ttyUSB3` | 3 | silent |

`/dev/serial/by-id/*FlashPro5*-if0N-port0` names stay stable across renumbering. The binding lasts until the board is unplugged. Consoles were opened with `picocom -b 115200 <port>` (exit `Ctrl-a Ctrl-x`).

**Lesson: one reader per port.** While `picocom` and a script both read the U-Boot port, each received only part of the output (Linux delivers each byte to one reader), which looked like a frozen console. Writing to the port from a script while `picocom` reads it works well.

**Getting to `RISC-V #`.** From `picocom`, pressing a key during `Hit any key to stop autoboot` stopped U-Boot before `boot.scr` ran. (During the original bring-up on Windows this had not been reliable.)

Details: [SETUP.md](SETUP.md#serial-console-on-a-linux-host).

## 18. Rust root task

seL4 has no shell: after boot the kernel starts exactly one user program, the root task. sel4test's root task runs the tests and then has nothing left to do, which is why the console goes quiet after the summary. To run our own code, the root task itself is replaced.

[`rust-root-task/`](../rust-root-task/README.md) builds a `no_std` Rust root task with [rust-sel4](https://github.com/seL4/rust-sel4) and packages it with the same kernel configuration and C elfloader as sel4test:

1. Configure the kernel from the patched pinned checkout with sel4test's options ([`cmake/settings.cmake`](../rust-root-task/cmake/settings.cmake)) and build `kernel.elf` and `libsel4.a`. Building `libsel4.a`, not just the kernel, is what generates all libsel4 headers.
2. Build the Rust program in the `sel4-rust-tutorial` image for target `riscv64gc-sel4-roottask` (FPU enabled in the kernel → `gc`), passing the kernel's source and generated libsel4 include directories in `SEL4_INCLUDE_DIRS`. The platform directory `libsel4/sel4_plat_include/polarfire` is required.
3. Let the C elfloader bundle kernel, DTB and the Rust ELF ([`cmake/CMakeLists.txt`](../rust-root-task/cmake/CMakeLists.txt) sets the `rootserver_image` target's `ROOTSERVER_IMAGE` property directly and adds `util_libs/libcpio`), then wrap it with `make-uimage` as for sel4test.

On the board (network-booted, §19):

```text
ELF-loading image 'kernel' to 80200000
ELF-loading image 'rootserver' to 8022a000
Bootstrapping kernel
Available phys memory regions: 2
  [80200000..84000000)
  [8a000000..92000000)
Booting all finished, dropped to user space
Hello from Rust on seL4!
TALOS: Rust root task running, 50 untyped regions available
```

The image that ran was built from the developer's local seL4 tree with the same settings. The repository's `build.sh` builds the same program against the clean pinned checkout.

## 19. Network boot from U-Boot

U-Boot on the board has working Ethernet (`ethernet@20110000`, gigabit) and the `dhcp`, `ping` and `tftpboot` commands (no `wget`). Serving images from the development computer over TFTP removes SD card swaps from the edit-build-boot loop.

- **Server:** dnsmasq in TFTP-only mode in Docker with host networking ([`tftp/`](../tftp/)), so no `sudo` is needed to run it.
- **Firewall:** the host's `ufw` dropped the board's requests (`[UFW BLOCK] … DPT=69` in the kernel log). One rule allowing inbound UDP 69 from the local subnet fixed it.
- **dnsmasq option to avoid:** with `--tftp-single-port`, dnsmasq received requests but every reply failed with `Network is unreachable`. Without it, normal TFTP works through the single firewall rule because the rest of each transfer is replies to flows the server opened.
- **Boot:**
  ```text
  setenv autoload no
  dhcp
  tftpboot 0x8e000000 <host-IP>:rust.uImage
  bootm 0x8e000000 - <fdt_blob>
  ```
  A 177,016-byte image transferred at 350–850 KiB/s over the host's Wi-Fi; U-Boot's `crc32` of the loaded image matched the host file's CRC-32. `bdinfo` reported `fdt_blob = 0xbf333da0` in every session.

Details: [NETBOOT.md](NETBOOT.md).

## 20. Current state and next steps

**Done:** reproducible seL4 + sel4test image that boots automatically from the SD card (118/49 on the board); Linux host serial setup; network boot; a Rust root task running on seL4 on the board.

**Not yet tested on the board:** the autoboot script's fallback to Linux; the renamed autoboot script; the Rust image built by the repository's script from the pinned checkout.

**Next, for this repository:** the open board checks above. `rust-root-task/` stays a minimal check that a Rust program runs on this board; the [seL4 Rust tutorial](https://sel4.github.io/seL4-rust-tutorial/) examples build the same way.
