# TALOS seL4 Bring-up: PolarFire SoC Discovery Kit

Take a **blank microSD card** to the team's **verified seL4 + sel4test boot** on a Microchip PolarFire SoC Discovery Kit (MPFS-DISCO-KIT). **No seL4 compilation required.** You copy two small files onto an official Linux SD card and type six U-Boot commands.

> **Repository status:** assembled locally and **not published yet**. The GitHub URL below is a placeholder. See [Publication status](#publication-status).

## Two builds, and which one to use

| | **Verified baseline** (default) | **Experimental** (opt-in, spare card only) |
|---|---|---|
| Files | [`images/sel4.uImage`](images/sel4.uImage) + [`boot/boot-sel4.scr`](boot/boot-sel4.scr) | [`experimental/`](experimental/README.md) |
| On real hardware | **Booted the Discovery Kit: 118 tests passed, 49 disabled** | **Not tested on hardware yet.** QEMU only. |
| Boot | Script stages the image; you type `bootm` (this page) | Candidate script that boots automatically, with Linux fallback |
| Build | The original developer's build | Rebuilt from clean pinned sources, reproducible |
| Privacy | **Contains machine-specific data**: 594 absolute build paths including the developer's username, plus the original board's MAC address. **Not a sanitized public release.** | Audited: no user, home, host or IP data, and the MAC is zeroed ([audit](experimental/reports/PRIVACY_AUDIT.md)) |

**Use the verified baseline.** The experimental build is for teammates who volunteer to run its [hardware test plan](experimental/README.md#hardware-test-plan-in-this-order-record-full-serial-logs) on a spare card. It will not become the default without explicit team approval after those tests pass.

## Checklist (verified baseline)

- [ ] **1.** Official setup: Avnet guide **through Section 5, Step 3**, and stop there ([§1](#1-start-with-the-official-linux-setup))
- [ ] **2.** Get this repository and check its hashes ([§2](#2-get-this-repository))
- [ ] **3.** On your computer: back up `boot.scr` to `boot-linux.scr`, then copy `sel4.uImage` and `boot.scr` onto the card's **FAT boot partition** ([§3](#3-install-onto-the-sd-cards-boot-partition))
- [ ] **4.** Boot the board, wait for `RISC-V #`, type the boot commands with **your own** FDT address ([§4](#4-boot-sel4-from-the-u-boot-prompt))
- [ ] **5.** See `118 tests passed. 49 tests disabled.` ([§5](#5-confirm-success))

## 1. Start with the official Linux setup

Follow Avnet's [Microchip PolarFire SoC Discovery Kit QuickStart](https://github.com/avnet-iotconnect/iotc-python-lite-sdk-demos/blob/main/microchip-polarfire-soc-dk/README.md) **from the beginning through Section 5 "Device Setup", Step 3, inclusive**. Step 3 is *"Click File → New connection... → Serial and observe 3 COM port entries"*. **Stop there.** Do not do Step 4 onward (login, `pip install`, IoTConnect, demos).

The guide is written for Windows. It covers:

- **Hardware (Sections 2–3):** the kit, a quality microSD card and reader, USB-C to connector **#1**, Ethernet to connector **#2**.
- **FPGA update (Section 4):** program the Discovery Kit reference design `.job` with Microchip FlashPro Express. This changes the board, so follow the official instructions exactly.
- **Linux image (Section 4):** download the Discovery Kit `.wic.gz` from the [Linux4Microchip releases](https://github.com/linux4microchip/meta-mchp/releases), extract it and flash it to the microSD card.
- **Serial (Section 5, Steps 1–3):** **115200 baud, 8 data bits, 1 stop bit, no parity**, and three serial ports appear.

**Versions.** The verified run used Linux4Microchip **2026.04.1**, U-Boot **2025.07-linux4microchip-2026.04** and FPGA reference design **v2507** (all confirmed from files), plus HSS **0.99.53** (from the bring-up log). Avnet says "latest", so you may get newer releases, which are **untested**. See [docs/FIRMWARE_COMPATIBILITY.md](docs/FIRMWARE_COMPATIBILITY.md) and please add your result there.

Linux-host equivalents (flashing, serial terminals) are in [docs/SETUP.md](docs/SETUP.md). Before continuing, confirm that the board boots the official Linux and that you can see its serial output.

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
| [`images/sel4.uImage`](images/sel4.uImage) | `sel4.uImage` | The exact image that passed 118 tests on our board |
| [`boot/boot-sel4.scr`](boot/boot-sel4.scr) | `boot.scr` | The exact U-Boot script from that board. It **stages** the image (§4) |

## 3. Install onto the SD card's boot partition

Power off the board, remove the microSD card and put it in your computer. The official image has a small **FAT partition labelled `boot`** (about 64 MiB) that contains `boot.scr`, `fitImage` and `uboot.env`. **Do not touch the large `root` (ext4) partition.**

### Linux host (recommended: the installer)

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS            # find the ~64M vfat partition labelled "boot"
BOOT=/media/$USER/boot                                 # EXAMPLE ONLY: use your card's real mount point
scripts/install-to-boot.sh "$BOOT"                     # dry run: checks everything, changes nothing
scripts/install-to-boot.sh "$BOOT" --apply             # back up Linux boot.scr, install, verify
```

The [installer](scripts/install-to-boot.sh) does the following:

- Checks the repository hashes, and that the target is a mounted FAT partition containing `boot.scr` and `fitImage`.
- Refuses to continue if `boot.scr` is already a TALOS script with no Linux backup.
- **Never overwrites `boot-linux.scr`.**
- Writes each file to a temporary name, verifies it, and only then renames it into place, replacing `boot.scr` last. An interrupted run leaves a card that still boots Linux.

It passed 79 checks against disposable FAT images ([results](experimental/reports/TEST_RESULTS.md#installer)). Its `--apply` mode has **not** yet been run on a real SD card.

Then unmount before removing the card, e.g. `udisksctl unmount -b /dev/sdX1` (your device) or the file manager's *Eject*.

### Linux host, by hand

```bash
BOOT=/media/$USER/boot                       # EXAMPLE ONLY: replace with your real mount point
ls -l "$BOOT/boot.scr" "$BOOT/fitImage"      # both must exist, otherwise STOP: wrong partition

# 1) Back up the Linux boot script once, and never back up a TALOS script by mistake
if [ ! -e "$BOOT/boot-linux.scr" ]; then
  if cmp -s "$BOOT/boot.scr" boot/boot-sel4.scr || cmp -s "$BOOT/boot.scr" experimental/boot/boot-auto.scr; then
    echo "STOP: boot.scr is already a TALOS script and there is no Linux backup (see docs/TROUBLESHOOTING.md)"
  else
    cp "$BOOT/boot.scr" "$BOOT/boot-linux.scr" && sync
  fi
fi
ls -l "$BOOT/boot-linux.scr"                 # must exist before you continue

# 2) Install (run from the root of this repository); boot.scr last
cp images/sel4.uImage "$BOOT/sel4.uImage"
cp boot/boot-sel4.scr "$BOOT/boot.scr"
sync
sha256sum "$BOOT/sel4.uImage" "$BOOT/boot.scr"   # must match images/SHA256SUMS
```

### Windows host

1. Open the drive named **boot** in File Explorer. It must contain `boot.scr` and `fitImage`. Windows may offer to *format* the other partition: **click Cancel**. Turn on *View → Show → File name extensions*.
2. **Back up first:** if there is no `boot-linux.scr` yet, right-click `boot.scr` → *Copy*, then *Paste* in the same folder (this creates `boot - Copy.scr`) and rename that copy to **`boot-linux.scr`**. Check it exists.
3. **Prepare the seL4 script on your computer, not on the card:** in your local copy of this repository, copy `boot\boot-sel4.scr` to a scratch folder, e.g. your Desktop, and rename it there to **`boot.scr`**.
4. Copy `images\sel4.uImage` onto the card.
5. Copy the renamed `boot.scr` from step 3 onto the card. When Windows asks, choose **Replace the file in the destination**. The original is safe as `boot-linux.scr`.
6. Optional check in PowerShell: `Get-FileHash E:\boot.scr, E:\sel4.uImage` (use your drive letter) must match `images\SHA256SUMS`.
7. *Safely Remove Hardware / Eject* before pulling the card.

## 4. Boot seL4 from the U-Boot prompt

### Serial ports

The board shows **three** serial ports over USB-C, at **115200 8N1**:

- **HSS console:** firmware messages, shown first at power-on.
- **U-Boot / Linux / seL4 console:** where `RISC-V #` appears and the tests run. Avnet's guide uses the **middle-numbered** port for the Linux console.

On one Windows PC these were **COM4 (HSS)** and **COM5 (U-Boot/seL4)**. Your numbers will differ. If unsure, open all three ports, power on, and see which one prints U-Boot output. Linux names are in [docs/SETUP.md](docs/SETUP.md#serial-console).

### Boot

Insert the card, open the U-Boot/seL4 port, and power on.

1. If boot stalls on the **HSS** console, typing `sdcard` and then `boot` there helped on our board.
2. The installed script prints `=== seL4 Discovery Kit Boot Test ===` and the image details. **It does not boot seL4.** U-Boot then carries on with its other boot methods. Based on the card's saved environment, those are EFI, then network (DHCP); this sequence was not observed line by line. You may see messages such as `SCRIPT FAILED: continuing...`. The `RISC-V #` prompt appeared **after a delay** in the verified setup, so **wait**. We could not reliably interrupt the countdown with a keypress, so don't depend on that.
3. At `RISC-V #`, reload and check the image:

   ```text
   load mmc 0:1 0x8e000000 sel4.uImage
   iminfo 0x8e000000
   ```

   ✔ `load` prints `3057528 bytes read` (verified). ✔ `iminfo` should show `Load Address: 80650000`, `Entry Point: 80650000` and `Verifying Checksum ... OK`. **If not, stop.** See [Troubleshooting](docs/TROUBLESHOOTING.md#load-or-iminfo-fails).

4. Find **this session's** device-tree address:

   ```text
   bdinfo
   ```

   Find the line `fdt_blob = 0x........` and write down the address.

5. Select and check it. Replace `<FDT>` with your address (no angle brackets):

   ```text
   fdt addr <FDT>
   fdt header
   ```

   ✔ `fdt header` must show `magic: 0xd00dfeed`. **If it errors or shows another magic value, do not boot.** See [Troubleshooting](docs/TROUBLESHOOTING.md#invalid-or-missing-fdt).

6. Boot, passing the same address as the **third** argument:

   ```text
   bootm 0x8e000000 - <FDT>
   ```

   **Never leave out the FDT argument**: `bootm 0x8e000000` alone fails with `Device tree not found or missing FDT support` and needs a board reset.

Our successful session used `fdt_blob = 0xbf333da0`. **That is an example, not a constant.** Always use your own `bdinfo` value.

## 5. Confirm success

The test suite runs for a while, and some tests deliberately print kernel error messages. The verified run ended with:

```text
Test suite passed. 118 tests passed. 49 tests disabled.
All is well in the universe
```

The image also prints `TALOS: root task reached seL4 user space` early on. This line was seen under QEMU, and the string is in the image, but the hardware log did not record it.

**Different counts are not "close enough".** They mean a different image or build, or different board behavior. Recheck the hashes, then share the full serial log and your firmware versions ([FIRMWARE_COMPATIBILITY.md](docs/FIRMWARE_COMPATIBILITY.md)).

## Restore normal Linux boot

Power off, put the card in your computer, mount the FAT boot partition, then:

```bash
scripts/install-to-boot.sh "$BOOT" --restore-linux --apply   # or by hand:
cp "$BOOT/boot-linux.scr" "$BOOT/boot.scr" && sync
```

On Windows, copy `boot-linux.scr`, paste it, rename the copy to `boot.scr`, and replace the existing file. Eject safely and reboot. `sel4.uImage` can stay on the card. This restores only the boot script. It does not undo the official FPGA programming, which is the intended board configuration. If `boot-linux.scr` is missing, see [Troubleshooting](docs/TROUBLESHOOTING.md#restore-linux-boot).

## Troubleshooting (short version)

| Symptom | Likely cause, and what to do |
|---|---|
| No output at all | Wrong port or settings: try all three ports at 115200 8N1 and check power. |
| Linux boots instead | `boot.scr` wasn't replaced, or it's on the wrong partition or named `boot.scr.scr`. Run `scripts/install-to-boot.sh "$BOOT" --verify`. |
| `ERROR: Could not load sel4.uImage` | `sel4.uImage` is missing from the FAT boot partition or has a different name. |
| Never reaches `RISC-V #` | Wait longer (network boot attempt). Check you're on the U-Boot port, not HSS. Try `sdcard` then `boot` on HSS. |
| `Bad Magic Number` / bad checksum | Rerun `load mmc 0:1 0x8e000000 sel4.uImage`. If it persists, recopy the file and check its hash. |
| `Device tree not found` | You left out the FDT argument. Reset, reload, and use `bootm 0x8e000000 - <FDT>`. |
| Different test counts | Not the verified image or setup. See §5. |

Full details: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Copy/paste summary (verified baseline)

```text
# Host (Linux), from this repo's root. First set BOOT to YOUR card's FAT "boot" mount point, e.g.:
#   BOOT=/media/$USER/boot
scripts/install-to-boot.sh "$BOOT" --apply
# eject, insert in board, power on, wait for RISC-V # on the U-Boot port (115200 8N1)

# Board, at RISC-V #  (replace <FDT> with the fdt_blob value bdinfo prints)
load mmc 0:1 0x8e000000 sel4.uImage
iminfo 0x8e000000                 # Verifying Checksum ... OK
bdinfo                            # note fdt_blob = <FDT>
fdt addr <FDT>
fdt header                        # magic: 0xd00dfeed
bootm 0x8e000000 - <FDT>
```

## Next milestone: automatic seL4 boot

The goal is a U-Boot script that boots seL4 with no typing at `RISC-V #`. It must find and **validate** the FDT without a hardcoded session address, run `bootm` itself, keep a Linux recovery path, and survive repeated cold boots before becoming the default.

**Status:** a **candidate** exists in [`experimental/boot/boot-auto.cmd`](experimental/boot/boot-auto.cmd). It uses U-Boot's `${fdtcontroladdr}`, which the U-Boot source sets to the same value `bdinfo` prints as `fdt_blob`, and it falls back to Linux on any failed check. It worked under **QEMU with U-Boot** but is **not verified on the Discovery Kit**. Until the [hardware test plan](experimental/README.md#hardware-test-plan-in-this-order-record-full-serial-logs) passes, use the manual steps above. The Rust user-space runtime is future work and is not in this repository.

## Publication status

Prepared locally, and **not ready for public release** until these are resolved:

1. **Verified baseline privacy:** `images/sel4.uImage`, `board/discovery/discovery.dts/.dtb` and `patches/kernel/0001-…` contain the developer's build paths and/or the original board's MAC address. The owner must accept this explicitly, or publish only the experimental image (which first needs hardware verification).
2. **Team licence:** no licence has been chosen for TALOS-authored docs and scripts (third-party licences are covered in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).
3. **GPL source:** publish the corresponding-source archive (`experimental/scripts/make-source-archive.sh`) next to the binaries in each release.
4. **Device tree licence:** the licence of the board-extracted DTS is assumed to be the upstream "(GPL-2.0 OR MIT)" but not confirmed.

The main TALOS repository's name is deliberately kept out of this repository (owner decision).

Details: [docs/BUILD_PROVENANCE.md](docs/BUILD_PROVENANCE.md#licensing-and-attribution).

## What's in this repository

```text
README.md                    this guide (verified baseline)
images/, boot/               verified baseline: image, staging script, Linux backup script, checksums
experimental/                experimental clean build, autoboot candidate, build/audit scripts, reports
scripts/install-to-boot.sh   installer (dry run by default; --experimental, --restore-linux, --verify)
scripts/test-installer.sh    installer tests on disposable FAT images
docs/SETUP.md                host details: flashing, mounting, serial ports, hash checks, Docker
docs/TROUBLESHOOTING.md      failures and fixes
docs/FIRMWARE_COMPATIBILITY.md  tested/historical/untested firmware versions
docs/ARTIFACT_INTEGRITY.md   checksums vs. authenticity; future signed releases
docs/BRINGUP_GUIDE.md        original engineering log of the port (background)
docs/BUILD_PROVENANCE.md     where every file came from; rebuild instructions; licensing
board/discovery/             build wrapper, original notes, board device tree (baseline)
patches/                     source changes against pinned upstream revisions
source/                      pinned sel4test repo manifest
LICENSES/, THIRD_PARTY_NOTICES.md  third-party licence texts and notices
context/                     project handoff notes with verified findings
```
