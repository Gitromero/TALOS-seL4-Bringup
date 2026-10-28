# TALOS seL4 Bring-up: PolarFire SoC Discovery Kit

Take a **blank microSD card** to a **verified seL4 + sel4test boot** on a Microchip PolarFire SoC Discovery Kit (MPFS-DISCO-KIT). **No seL4 compilation required.** You copy two small files onto an official Linux SD card and power on. The board boots seL4 by itself.

> **Repository status:** assembled locally and **not published yet**. The GitHub URL below is a placeholder. See [Publication status](#publication-status).

## What works on the board

| Milestone | Status | Where |
|---|---|---|
| seL4 + sel4test, **automatic boot** from the SD card | ✅ **Hardware-verified:** `118 tests passed. 49 tests disabled.` with no typing | this page |
| Linux host as the serial console (all three UART ports) | ✅ Verified | [docs/SETUP.md](docs/SETUP.md#serial-console-on-a-linux-host) |
| Load and boot images **over USB** from your computer, no SD card swaps (`pf flash`) | ✅ Verified | [quick start](#loading-images-without-the-sd-card-quick-start), [full guide](docs/FLASHING.md) |
| The same over the network: DHCP + TFTP (`pf flash --lan`) | ✅ Verified | [quick start](#network-tftp), [full guide](docs/NETBOOT.md) |
| Shared serial consoles: people, scripts and AI agents on the same port at once | ✅ Verified | [docs/SHARED_CONSOLE.md](docs/SHARED_CONSOLE.md) |
| `no_std` **Rust** root task on seL4 (`Hello from Rust on seL4!`) | ✅ Verified (network boot) | [rust-root-task/](rust-root-task/README.md) |
| Peripheral map (addresses, IRQs, clocks); user LEDs driven by register writes | ✅ LEDs verified from U-Boot | [docs/PERIPHERALS.md](docs/PERIPHERALS.md) |

The image is built reproducibly from public, pinned sources ([scripts/build-sel4test.sh](scripts/build-sel4test.sh)); two clean builds are byte-identical. It contains no developer paths, and the board's MAC address is zeroed ([privacy audit](reports/PRIVACY_AUDIT.md)).

## Checklist

- [ ] **1.** Official setup: Avnet guide **through Section 5, Step 3**, and stop there ([§1](#1-start-with-the-official-linux-setup))
- [ ] **2.** Get this repository and check its hashes ([§2](#2-get-this-repository))
- [ ] **3.** On your computer: back up `boot.scr` to `boot-linux.scr`, then copy `sel4test.uImage` and the autoboot `boot.scr` onto the card's **FAT boot partition** ([§3](#3-install-onto-the-sd-cards-boot-partition))
- [ ] **4.** Put the card in the board, open the U-Boot/seL4 serial port, power on, and don't type anything ([§4](#4-boot))
- [ ] **5.** See `118 tests passed. 49 tests disabled.` ([§5](#5-confirm-success))

## 1. Start with the official Linux setup

Follow Avnet's [Microchip PolarFire SoC Discovery Kit QuickStart](https://github.com/avnet-iotconnect/iotc-python-lite-sdk-demos/blob/main/microchip-polarfire-soc-dk/README.md) **from the beginning through Section 5 "Device Setup", Step 3, inclusive**. Step 3 is *"Click File → New connection... → Serial and observe 3 COM port entries"*. **Stop there.** Do not do Step 4 onward (login, `pip install`, IoTConnect, demos).

The guide is written for Windows. It covers:

- **Hardware (Sections 2–3):** the kit, a quality microSD card and reader, USB-C to connector **#1**, Ethernet to connector **#2**.
- **FPGA update (Section 4):** program the Discovery Kit reference design `.job` with Microchip FlashPro Express. This changes the board, so follow the official instructions exactly.
- **Linux image (Section 4):** download the Discovery Kit `.wic.gz` from the [Linux4Microchip releases](https://github.com/linux4microchip/meta-mchp/releases), extract it and flash it to the microSD card.
- **Serial (Section 5, Steps 1–3):** **115200 baud, 8 data bits, 1 stop bit, no parity**, and three serial ports appear.

On a **Linux** computer, only one of the three ports may appear at first. The one-line fix is in [docs/SETUP.md](docs/SETUP.md#serial-console-on-a-linux-host).

**Versions.** The verified runs used Linux4Microchip **2026.04.1**, U-Boot **2025.07-linux4microchip-2026.04** and FPGA reference design **v2507**, plus HSS **0.99.53** (from the original bring-up log). Avnet says "latest", so you may get newer releases, which are **untested**. See [docs/FIRMWARE_COMPATIBILITY.md](docs/FIRMWARE_COMPATIBILITY.md) and please add your result there.

Before continuing, confirm that the board boots the official Linux and that you can see its serial output.

## 2. Get this repository

> **Placeholder:** `https://github.com/<TEAM-ORG>/TALOS-seL4-Bringup` is **not a real URL yet**. Use the link your team shares once the repository is published.

```bash
git clone https://github.com/<TEAM-ORG>/TALOS-seL4-Bringup.git   # placeholder URL
cd TALOS-seL4-Bringup
sha256sum -c images/SHA256SUMS
```

All three lines must say `OK`. Downloading the ZIP works too. On Windows, use PowerShell `Get-FileHash` ([docs/SETUP.md](docs/SETUP.md#verify-the-downloaded-files)). Checksums detect corruption, but they don't prove who made the files: see [docs/ARTIFACT_INTEGRITY.md](docs/ARTIFACT_INTEGRITY.md).

You need two files:

| Repository file | Copy to the SD card as | What it is |
|---|---|---|
| [`images/sel4test.uImage`](images/sel4test.uImage) | `sel4test.uImage` | seL4 + sel4test, the image that passed 118 tests on the board |
| [`boot/boot-auto.scr`](boot/boot-auto.scr) | `boot.scr` | U-Boot script that checks and boots the image automatically, and falls back to Linux if anything is wrong ([what it does](boot/README.md)) |

## 3. Install onto the SD card's boot partition

Power off the board, remove the microSD card and put it in your computer. The official image has a small **FAT partition labelled `boot`** (about 64 MiB) that contains `boot.scr`, `fitImage` and `uboot.env`. **Do not touch the large `root` (ext4) partition.**

### Linux host (recommended: the installer)

From the root of this repository, find the card's mounted `boot` partition and do a dry run, which checks everything and changes nothing:

```bash
BOOT=$(findmnt -nro TARGET -S LABEL=boot)
echo "BOOT=$BOOT"
scripts/install-to-boot.sh "$BOOT"
```

`BOOT` should be one path such as `/media/<you>/boot`. If it is empty, the partition isn't mounted: see [docs/SETUP.md](docs/SETUP.md#mounting-the-fat-boot-partition), or set it by hand, e.g. `BOOT=/media/$USER/boot`. If the dry run reports no problems, install (backs up the Linux `boot.scr`, installs, verifies):

```bash
scripts/install-to-boot.sh "$BOOT" --apply
```

The [installer](scripts/install-to-boot.sh) does the following:

- Checks the repository hashes, and that the target is a mounted FAT partition containing `boot.scr` and `fitImage`.
- Refuses to continue if `boot.scr` is already a TALOS script (current or from an earlier revision of this repository) and there is no Linux backup.
- **Never overwrites `boot-linux.scr`.**
- Writes each file to a temporary name, verifies it, and only then renames it into place, replacing `boot.scr` last. An interrupted run leaves a card that still boots Linux.

It passes 88 checks against disposable FAT images ([results](reports/TEST_RESULTS.md#installer)).

Then unmount before removing the card, e.g. `udisksctl unmount -b /dev/sdX1` (your device) or the file manager's *Eject*.

### Linux host, by hand

Point `BOOT` at the card's FAT boot partition and check it. Both files must be listed; otherwise **stop**, it is the wrong partition:

```bash
BOOT=$(findmnt -nro TARGET -S LABEL=boot)
ls -l "$BOOT/boot.scr" "$BOOT/fitImage"
```

**1. Back up the Linux boot script once.** If `strings "$BOOT/boot.scr" | grep -c TALOS` prints anything other than `0`, `boot.scr` is **not** the Linux script: stop.

```bash
if [ ! -e "$BOOT/boot-linux.scr" ]; then
  cp "$BOOT/boot.scr" "$BOOT/boot-linux.scr" && sync
fi
ls -l "$BOOT/boot-linux.scr"
```

`boot-linux.scr` must be listed before you continue.

**2. Install** (run from the root of this repository). `boot.scr` goes last, and the two hashes printed at the end must match the ones in `images/SHA256SUMS`:

```bash
cp images/sel4test.uImage "$BOOT/sel4test.uImage"
cp boot/boot-auto.scr "$BOOT/boot.scr"
sync
sha256sum "$BOOT/sel4test.uImage" "$BOOT/boot.scr"
grep -e sel4test.uImage -e boot-auto.scr images/SHA256SUMS
```

### Windows host

1. Open the drive named **boot** in File Explorer. It must contain `boot.scr` and `fitImage`. Windows may offer to *format* the other partition: **click Cancel**. Turn on *View → Show → File name extensions*.
2. **Back up first:** if there is no `boot-linux.scr` yet, right-click `boot.scr` → *Copy*, then *Paste* in the same folder (this creates `boot - Copy.scr`) and rename that copy to **`boot-linux.scr`**. Check it exists.
3. **Prepare the seL4 script on your computer, not on the card:** in your local copy of this repository, copy `boot\boot-auto.scr` to a scratch folder, e.g. your Desktop, and rename it there to **`boot.scr`**.
4. Copy `images\sel4test.uImage` onto the card.
5. Copy the renamed `boot.scr` from step 3 onto the card. When Windows asks, choose **Replace the file in the destination**. The original is safe as `boot-linux.scr`.
6. Optional check in PowerShell: `Get-FileHash E:\boot.scr, E:\sel4test.uImage` (use your drive letter) must match `images\SHA256SUMS`.
7. *Safely Remove Hardware / Eject* before pulling the card.

## 4. Boot

### Serial ports

The board shows **three** serial ports over USB-C, at **115200 8N1**:

| Console | What you see | Windows (one PC) | Linux |
|---|---|---|---|
| **HSS** (firmware) | Hart Software Services banner at power-on; `>>` prompt | COM4 | `/dev/ttyUSB1` |
| **U-Boot / Linux / seL4** | U-Boot, `RISC-V #`, seL4 and test output | COM5 (the middle-numbered port) | `/dev/ttyUSB2` |
| Third UART | Silent in this procedure | n/a | `/dev/ttyUSB3` |

Your numbers may differ. On Linux, `/dev/ttyUSB0` is the board's JTAG channel, not a console, and the three UARTs only appear after the fix in [docs/SETUP.md](docs/SETUP.md#serial-console-on-a-linux-host). Open each port in **one** terminal program only. Two programs on the same port each get part of the output.

### Power on

Insert the card, open the U-Boot/seL4 port, power on, and **don't type anything**. You should see, in order:

```text
=== TALOS seL4 autoboot ===
TALOS: FDT at 0x..., 0x... bytes
TALOS: image range ends below FDT
   Verifying Checksum ... OK
TALOS: booting seL4 with FDT 0x...
Starting kernel ...
ELF-loader started on (HART 1) (NODES 1)
...
TALOS: root task reached seL4 user space
```

Then sel4test runs for a while. If HSS stalls before U-Boot, typing `sdcard` and then `boot` on the **HSS** console helped during the original bring-up.

If any check in the script fails, it prints a `TALOS:` line saying which one and boots Linux from `boot-linux.scr` instead. See [Troubleshooting](docs/TROUBLESHOOTING.md#autoboot-messages).

## 5. Confirm success

Some tests deliberately print kernel error messages (for example `Attempted to invoke a null cap`). That is expected. The run ends with:

```text
Test suite passed. 118 tests passed. 49 tests disabled.
All is well in the universe
```

**Different counts are not "close enough".** They mean a different image or build, or different board behavior. Recheck the hashes, then share the full serial log and your firmware versions ([FIRMWARE_COMPATIBILITY.md](docs/FIRMWARE_COMPATIBILITY.md)).

After the summary nothing else runs: seL4 has no shell, and sel4test is the only program in the image. Reset or power-cycle the board to start again.

## Manual boot from the U-Boot prompt

You need the `RISC-V #` prompt to load images [by hand over USB or the network](#loading-images-without-the-sd-card-quick-start), or to boot the image from the card by hand. Press a key while U-Boot prints `Hit any key to stop autoboot`. This stops U-Boot before it runs `boot.scr`. Then paste these one line at a time:

```text
load mmc 0:1 0x8e000000 sel4test.uImage
iminfo 0x8e000000
fdt addr ${fdtcontroladdr}
fdt header
bootm 0x8e000000 - ${fdtcontroladdr}
```

- `iminfo` must show `Load Address: 80640000` and `Verifying Checksum ... OK`; `fdt header` must show `magic: 0xd00dfeed`. If either doesn't, stop and see [Troubleshooting](docs/TROUBLESHOOTING.md#load-or-iminfo-fails).
- `${fdtcontroladdr}` is U-Boot's own device tree address, the same value `bdinfo` prints as `fdt_blob` (`0xbf333da0` on our board in every session so far). The autoboot script uses it the same way.
- **Never leave out the FDT argument**: `bootm 0x8e000000` alone fails with `Device tree not found or missing FDT support` and needs a board reset.
- If the board was reset, anything loaded into RAM is gone: `load` again before `bootm`.

## Loading images without the SD card (quick start)

Instead of copying images to the SD card, send them from your computer into the board's RAM and boot them. This is the way to try a freshly built image. Nothing is written to the SD card, and a power cycle boots the card as before. Full guide: **[docs/FLASHING.md](docs/FLASHING.md)**.

### USB (default)

Needs only the USB-C cable in connector **#1**. From the repository root:

```bash
scripts/pf flash                       # images/sel4test.uImage
scripts/pf flash my.uImage --expect 'Hello from Rust on seL4!'
```

This resets the board through the HSS console, stops autoboot, sends the image with U-Boot's `loady` (YMODEM over the U-Boot serial port, 1.5 Mbaud), checks its CRC-32 on the board, boots it and waits for the result (exit code 0 on `Test suite passed`). The 3 MB sel4test image takes about 25 seconds to send. Verified on the board on 2026-10-26.

It works over SSH, so nobody has to be at the board. To watch it at the same time, open `scripts/pf console` in another terminal instead of picocom. A plain picocom would take bytes the script needs, so the script refuses to start while one is open ([why](docs/SHARED_CONSOLE.md)). Options, speeds and the manual `loady` steps: [docs/FLASHING.md](docs/FLASHING.md#1-usb).

### Network (TFTP)

Faster for large images: a few seconds for sel4test. Needs Docker on a Linux computer, and an Ethernet cable from connector **#2** to the same network (router) as your computer.

**Once per computer** (Ubuntu/Mint with `ufw`): allow TFTP from your local network through the firewall.

```bash
IFACE=$(ip route show default | awk '{print $5; exit}')
SUBNET=$(ip -4 route show dev "$IFACE" scope link | awk '{print $1; exit}')
echo "interface=$IFACE subnet=$SUBNET"
sudo ufw allow in on "$IFACE" from "$SUBNET" to any port 69 proto udp comment 'sel4 tftp'
```

**Then**, with the board's USB-C and Ethernet connected:

```bash
scripts/pf flash --lan                 # images/sel4test.uImage; same options as above
```

It starts the TFTP server itself and does the same reset, download, CRC check, boot and result check. `Loading: *T T T` means the firewall is still dropping the requests ([fix](docs/NETBOOT.md#3-allow-tftp-through-your-computers-firewall)). Manual `dhcp`/`tftpboot` steps and details: **[docs/NETBOOT.md](docs/NETBOOT.md)**.

## Day-to-day commands (`scripts/pf`)

Once the board is set up and plugged into a Linux computer (USB-C **#1**; Ethernet **#2** only for `pf flash --lan`), `scripts/pf` covers daily work. All of it works over SSH:

| Command | What it does |
|---|---|
| `scripts/pf status` | Read-only check: USB, serial channels, port names, who has them open, HSS alive, TFTP server, last result |
| `scripts/pf flash [image]` | [Load an image over USB](docs/FLASHING.md#1-usb) and boot it with no hands on the board (default `images/sel4test.uImage`), and report pass/fail |
| `scripts/pf flash --lan [image]` | The same over [Ethernet + TFTP](docs/NETBOOT.md#one-command-scriptsnetwork-flashsh) |
| `scripts/pf console` | U-Boot/Linux/seL4 console, [**shared**](docs/SHARED_CONSOLE.md): leave it open and run `pf flash` in another terminal to watch (exit `Ctrl-a Ctrl-x`) |
| `scripts/pf hss` | HSS firmware console, shared the same way |
| `scripts/pf reset [-y]` | Reset the board through the HSS console |
| `scripts/pf tftp [start\|stop\|status\|logs]` | The TFTP server used by `pf flash --lan` |
| `scripts/pf install-udev` | Once per computer (sudo): bind all four serial channels on plug-in and add `/dev/polarfire-{hss,uboot,uart3,jtag}` |

Optional: `alias pf="$PWD/scripts/pf"` (run from the repository root) in your shell startup file, then just `pf flash`.

## Restore normal Linux boot

Power off, put the card in your computer, mount the FAT boot partition, then from the repository root:

```bash
BOOT=$(findmnt -nro TARGET -S LABEL=boot)
scripts/install-to-boot.sh "$BOOT" --restore-linux --apply
```

Or by hand:

```bash
BOOT=$(findmnt -nro TARGET -S LABEL=boot)
cp "$BOOT/boot-linux.scr" "$BOOT/boot.scr" && sync
```

On Windows, copy `boot-linux.scr`, paste it, rename the copy to `boot.scr`, and replace the existing file. Eject safely and reboot. `sel4test.uImage` can stay on the card. This restores only the boot script. It does not undo the official FPGA programming, which is the intended board configuration. If `boot-linux.scr` is missing, see [Troubleshooting](docs/TROUBLESHOOTING.md#restore-linux-boot).

## Board peripherals

[docs/PERIPHERALS.md](docs/PERIPHERALS.md) maps the board's peripherals: address, interrupt, clock/reset bit, which ones the kernel or firmware owns, and how a seL4 program gets access to one. Each entry says whether it was checked on the board or only taken from documentation.

## Troubleshooting (short version)

| Symptom | Likely cause, and what to do |
|---|---|
| Only one serial port on Linux | The driver bound one UART. See [SETUP.md](docs/SETUP.md#serial-console-on-a-linux-host). |
| Output has gaps or the terminal looks frozen mid-boot | Two programs have the same port open. Close one, and use `scripts/pf console` ([shared](docs/SHARED_CONSOLE.md)). |
| No output at all | Wrong port or settings: try all ports at 115200 8N1 and check power. |
| Linux boots instead | `boot.scr` wasn't replaced, or the script fell back (look for a `TALOS:` line). Run `scripts/install-to-boot.sh "$BOOT" --verify`. |
| `TALOS: sel4test.uImage not found` | The image is missing from the FAT boot partition or has a different name. |
| `Device tree not found` | Manual boot without the FDT argument. Reset, reload, and use `bootm 0x8e000000 - ${fdtcontroladdr}`. |
| `Wrong Image Type for bootm command` | Nothing valid at `0x8e000000`, usually because the board was reset after loading. `load` (or `pf flash`) again. |
| Different test counts | Not this image or setup. See §5. |
| Still stuck after everything above (hangs, no boot, card not detected) | **Last resort:** with the board **still powered on**, pull the microSD card out and push it back in. Do this a few times. Then, on the **HSS** console (the `>>` prompt), type `sdcard` and then `boot`. It is not a real fix, but it has sometimes worked. |

Full details: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Copy/paste summary

1. On a Linux host with the card's FAT `boot` partition mounted, from this repository's root, run the installer:

   ```bash
   BOOT=$(findmnt -nro TARGET -S LABEL=boot)
   scripts/install-to-boot.sh "$BOOT" --apply
   ```

2. Eject the card, insert it in the board, open the U-Boot port (115200 8N1) and power on.
3. Wait for `Test suite passed. 118 tests passed. 49 tests disabled.`

## Not yet tested on hardware

This part of the autoboot script worked in QEMU ([results](reports/TEST_RESULTS.md)) but has not been exercised on the board:

- **Fallback to Linux** when a check fails (e.g. rename `sel4test.uImage` on the card and power on: expect `TALOS: sel4test.uImage not found` → `trying boot-linux.scr` → Linux).

Repeated cold boots (power removed) were confirmed on the board on 2026-10-22: each one autobooted into sel4test.

The board run used the autoboot script as it was before this repository's file rename: it loaded the same image bytes under the name `sel4-experimental.uImage`. The current script differs from it only in that file name and its banner line ([diff](boot/README.md#history)).

## Publication status

Prepared locally, and **not ready for public release** until these are resolved:

1. **Team licence:** no licence has been chosen for TALOS-authored docs and scripts (third-party licences are covered in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).
2. **GPL source:** publish the corresponding-source archive (`scripts/make-source-archive.sh`) next to the binary in each release.
3. **Device tree licence:** the licence of the board-extracted DTS is assumed to be the upstream "(GPL-2.0 OR MIT)" but not confirmed.
4. **Git history:** the board's MAC address has been removed from every source file (2026-10-22), but the repository's **first commit** still contains it, along with the first image's developer paths. Publish from a fresh history (for example a new repository with one squashed commit), or rewrite the history, instead of pushing the existing one.

Resolved on 2026-10-22: the board MAC is zeroed in `board/discovery/discovery.dts/.dtb` and `patches/kernel/0001` (the separate `0002` patch was folded in, and a clean rebuild is still byte-identical), and the home network addresses in [docs/NETBOOT.md](docs/NETBOOT.md) are replaced with example addresses.

The main TALOS repository's name is deliberately kept out of this repository (owner decision).

Details: [docs/BUILD_PROVENANCE.md](docs/BUILD_PROVENANCE.md#licensing-and-attribution).

## What's in this repository

```text
README.md                    this guide
images/                      sel4test.uImage and SHA256SUMS
boot/                        autoboot script (boot-auto), Linux backup script (boot-linux), sources
scripts/install-to-boot.sh   SD-card installer (dry run by default; --restore-linux, --verify)
scripts/pf                   day-to-day board commands: status, flash, console, hss, reset, tftp, install-udev
scripts/usb-flash.sh         one-command USB load (pf flash): reset, YMODEM, verify, boot, check result
scripts/network-flash.sh     the same over the network (pf flash --lan): reset, TFTP, verify, boot, check result
scripts/serial-share.py      share a serial port between consoles, scripts and AI agents
scripts/test-installer.sh    installer tests on disposable FAT images
scripts/build-sel4test.sh    reproducible build of images/sel4test.uImage from pinned sources
scripts/make-source-archive.sh, privacy_audit.py   GPL source archive, artifact privacy scan
reports/                     build report, privacy audit, test results
rust-root-task/              no_std Rust seL4 root task: source, build script, boot steps
tftp/                        TFTP server (Docker) for pf flash --lan
host/udev/                   Linux host udev rule: bind all four serial channels, /dev/polarfire-* names
docs/SETUP.md                host details: flashing, mounting, serial ports (Windows and Linux), Docker
docs/FLASHING.md             load images into RAM and boot them: USB first, then network
docs/NETBOOT.md              network (TFTP) details: server, firewall, manual steps
docs/SHARED_CONSOLE.md       sharing the serial ports: people, scripts and AI agents at once
docs/PERIPHERALS.md          board peripheral map: addresses, IRQs, clocks, ownership
docs/TROUBLESHOOTING.md      failures and fixes
docs/FIRMWARE_COMPATIBILITY.md  tested firmware versions and results
docs/ARTIFACT_INTEGRITY.md   checksums vs. authenticity; future signed releases
docs/BRINGUP_GUIDE.md        engineering log of the port, from first boot to Rust (background)
docs/BUILD_PROVENANCE.md     where every file came from; rebuild instructions; licensing
board/discovery/             board device tree and the original bring-up notes and build wrapper
patches/                     source changes against pinned upstream revisions
source/                      pinned sel4test repo manifest
LICENSES/, THIRD_PARTY_NOTICES.md  third-party licence texts and notices
context/                     project handoff notes
```
