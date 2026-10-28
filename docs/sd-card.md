# Booting seL4 from the SD card

Make the board boot seL4 + sel4test by itself, with no typing: copy two files onto the official Linux SD card's FAT `boot` partition and power on. The Linux boot script is kept as a backup, so restoring Linux is one copy. **Verified on the board:** `118 tests passed. 49 tests disabled.` with no typing, and repeated cold boots (2026-10-22).

You need a card set up with the official Linux image ([getting started](getting-started.md#1-official-board-setup)) and this repository with its hashes checked ([§2 there](getting-started.md#2-get-this-repository)).

| Repository file | Copy to the card as | What it is |
|---|---|---|
| [`images/sel4test.uImage`](../images/sel4test.uImage) | `sel4test.uImage` | seL4 + sel4test, the image that passed 118 tests on the board |
| [`boot/boot-auto.scr`](../boot/boot-auto.scr) | `boot.scr` | U-Boot script that checks and boots the image, and falls back to Linux if anything is wrong ([what it does](../boot/README.md)) |

## 1. Install

Power off the board, remove the microSD card and put it in your computer. The official image has a small **FAT partition labelled `boot`** (about 64 MiB) containing `boot.scr`, `fitImage` and `uboot.env`. **Do not touch the large `root` (ext4) partition.**

### Linux: the installer (recommended)

From the repository root, find the card's mounted `boot` partition and do a dry run, which checks everything and changes nothing:

```bash
BOOT=$(findmnt -nro TARGET -S LABEL=boot)
echo "BOOT=$BOOT"
scripts/install-to-boot.sh "$BOOT"
```

`BOOT` should be one path such as `/media/<you>/boot`. If it is empty, the partition isn't mounted ([mounting](#mounting-the-fat-boot-partition)). If the dry run reports no problems, install:

```bash
scripts/install-to-boot.sh "$BOOT" --apply
```

Then unmount before removing the card (`udisksctl unmount -b /dev/sdX1`, or the file manager's *Eject*).

What [`install-to-boot.sh`](../scripts/install-to-boot.sh) guarantees:

- Repository files must match `images/SHA256SUMS` (CRLF line endings are tolerated; a missing or malformed entry is an error).
- The target must be a mounted vfat partition with `boot.scr` and `fitImage`, and `boot.scr` must be a U-Boot script image.
- `boot-linux.scr` is created once, only from a non-TALOS script, and is **never overwritten or deleted**. TALOS scripts are recognised by hash, including both scripts from the repository's first revision, so a card set up earlier is handled safely. There is no option to override this; fix such a card by hand.
- Every write goes to `<name>.talos-tmp`, then is synced, hash-checked and renamed into place, image first and `boot.scr` last. A failure or interruption at any point leaves `boot.scr` as it was. A later run removes leftover `*.talos-tmp` files.
- `--verify` is a read-only report of what is on the card. It also lists images from earlier revisions (`sel4.uImage`, `sel4-experimental.uImage`), which are unused and safe to delete.

It passes 88 checks against disposable FAT images (`tests/test-installer.sh`, [results](../reports/TEST_RESULTS.md#installer)). It is Linux-only (it needs `findmnt`).

### Linux, by hand

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

**2. Install** (from the repository root). `boot.scr` goes last, and the two hashes printed at the end must match the ones in `images/SHA256SUMS`:

```bash
cp images/sel4test.uImage "$BOOT/sel4test.uImage"
cp boot/boot-auto.scr "$BOOT/boot.scr"
sync
sha256sum "$BOOT/sel4test.uImage" "$BOOT/boot.scr"
grep -e sel4test.uImage -e boot-auto.scr images/SHA256SUMS
```

### Windows

1. Open the drive named **boot** in File Explorer. It must contain `boot.scr` and `fitImage`. Windows may offer to *format* the other partition: **click Cancel**. Turn on *View → Show → File name extensions*.
2. **Back up first:** if there is no `boot-linux.scr` yet, right-click `boot.scr` → *Copy*, then *Paste* in the same folder (this creates `boot - Copy.scr`) and rename that copy to **`boot-linux.scr`**. Check it exists.
3. **Prepare the seL4 script on your computer, not on the card:** copy `boot\boot-auto.scr` from the repository to a scratch folder, e.g. your Desktop, and rename it there to **`boot.scr`**.
4. Copy `images\sel4test.uImage` onto the card.
5. Copy the renamed `boot.scr` from step 3 onto the card. When Windows asks, choose **Replace the file in the destination**. The original is safe as `boot-linux.scr`.
6. Optional check in PowerShell: `Get-FileHash E:\boot.scr, E:\sel4test.uImage` (use your drive letter) must match `images\SHA256SUMS`.
7. *Safely Remove Hardware / Eject* before pulling the card.

## 2. Boot

Insert the card, open the U-Boot/seL4 serial port ([which one](getting-started.md#3-serial-ports)), power on, and **don't type anything**. You should see, in order:

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

Then sel4test runs for a while. If HSS stalls before U-Boot, typing `sdcard` and then `boot` on the **HSS** console helped during the original bring-up. If any check in the script fails, it prints a `TALOS:` line saying which one and boots Linux from `boot-linux.scr` instead ([messages](troubleshooting.md#autoboot-messages)).

## 3. Confirm success

Some tests deliberately print kernel error messages (for example `Attempted to invoke a null cap`). That is expected. The run ends with:

```text
Test suite passed. 118 tests passed. 49 tests disabled.
All is well in the universe
```

**Different counts are not "close enough".** They mean a different image or build, or different board behavior. Recheck the hashes, then share the full serial log and your firmware versions ([firmware compatibility](hardware.md#8-firmware-compatibility)).

After the summary nothing else runs: seL4 has no shell, and sel4test is the only program in the image. Reset or power-cycle the board to start again.

## Manual boot from the U-Boot prompt

To boot the image on the card by hand (or after copying another image onto the card), press a key while U-Boot prints `Hit any key to stop autoboot` (the board's `bootdelay` is 2 s). This stops U-Boot before it runs `boot.scr`. Then paste these one line at a time:

```text
load mmc 0:1 0x8e000000 sel4test.uImage
iminfo 0x8e000000
fdt addr ${fdtcontroladdr}
fdt header
bootm 0x8e000000 - ${fdtcontroladdr}
```

- `iminfo` must show `Load Address: 80640000` and `Verifying Checksum ... OK`; `fdt header` must show `magic: 0xd00dfeed`. If either doesn't, stop and see [troubleshooting](troubleshooting.md#load-or-iminfo-fails).
- `${fdtcontroladdr}` is U-Boot's own device tree address, the same value `bdinfo` prints as `fdt_blob` (`0xbf333da0` on our board in every session so far). The autoboot script uses it the same way.
- **Never leave out the FDT argument**: `bootm 0x8e000000` alone fails with `Device tree not found or missing FDT support` and needs a board reset.
- If the board was reset, anything loaded into RAM is gone: `load` again before `bootm`.

## Restore normal Linux boot

Power off, put the card in your computer, mount the FAT boot partition, then from the repository root. First a dry run, then apply it:

```bash
BOOT=$(findmnt -nro TARGET -S LABEL=boot)
scripts/install-to-boot.sh "$BOOT" --restore-linux
scripts/install-to-boot.sh "$BOOT" --restore-linux --apply
```

Or by hand: `cp "$BOOT/boot-linux.scr" "$BOOT/boot.scr" && sync`. On Windows, copy `boot-linux.scr`, paste it, rename the copy to `boot.scr`, and replace the existing file. Eject safely and reboot. `sel4test.uImage` can stay on the card.

This restores only the boot script. It does not undo the official FPGA programming, which is the intended board configuration. If `boot-linux.scr` is missing, see [troubleshooting](troubleshooting.md#restore-linux-boot).

## Flashing the official Linux image

**Windows (Avnet's method):** extract the `.wic.gz` and flash the `.wic` with Balena Etcher.

**Linux (not tested by the team):** Balena Etcher also runs on Linux and is the safest choice, because it only offers removable drives. A command-line alternative, **which destroys the target device**:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS    # identify the SD card by SIZE/MODEL. Check twice.
WIC=mchp-base-image-mpfs-disco-kit.rootfs-XXXXXXXXXXXXXX.wic   # the exact file name you downloaded, minus .gz
gunzip -k "$WIC.gz"
sudo umount /dev/sdX?* 2>/dev/null            # sdX = YOUR card, never your system disk
sudo dd if="$WIC" of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

`/dev/sdX` is a placeholder. On some machines the card shows up as `/dev/mmcblk0`, on others as `/dev/sda`, and a wrong guess can wipe a disk.

## Mounting the FAT boot partition

After flashing, the card has (on the image we tested) a ~64 MiB **vfat** partition labelled **`boot`** and a large **ext4** partition labelled **`root`**. Only `boot` is used. On the verified card it contained:

```text
boot.scr   fitImage   uboot.env           (official image)
boot-linux.scr   sel4test.uImage          (added by this procedure; boot.scr replaced)
```

**Linux:** most desktops auto-mount it under `/media/<you>/boot`; `findmnt -nro TARGET -S LABEL=boot` prints where (nothing means not mounted). Otherwise mount it by hand (`sdX` is your card, found with `lsblk`):

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
udisksctl mount -b /dev/sdX1        # the vfat partition labelled boot; prints the mount point
sync                                # after copying files
udisksctl unmount -b /dev/sdX1
udisksctl power-off -b /dev/sdX     # optional, then remove the card
```

**Windows:** the `boot` partition appears as a drive letter. Windows cannot read the ext4 partition and may ask to format it. **Always click Cancel.**

**Before copying, always** check that the folder contains both `boot.scr` and `fitImage`. If it doesn't, you have the wrong drive or partition.

## Not yet tested on the board

The autoboot script's **fallback to Linux** when a check fails worked in QEMU ([results](../reports/TEST_RESULTS.md)) but has not been exercised on the board. To test it: rename `sel4test.uImage` on the card and power on; expect `TALOS: sel4test.uImage not found` → `trying boot-linux.scr` → Linux.

The board run used the autoboot script as it was before the repository's file rename: it loaded the same image bytes under the name `sel4-experimental.uImage`. The current script differs from it only in that file name and its banner line ([diff](../boot/README.md#history)).
