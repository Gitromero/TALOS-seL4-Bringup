# Setup details (host side)

This page adds host-specific detail to the [root README](../README.md). The README is still the procedure to follow.

**What has been tested.** The team's verified run used a **Windows** PC for the serial consoles (COM4/COM5) and a **Linux Mint** host to mount the SD card's FAT boot partition and copy files. The Linux serial-terminal and Linux flashing instructions below are standard equivalents that **the team has not tested on this board**.

## Official base setup: where to stop

Use Avnet's [PolarFire SoC Discovery Kit QuickStart](https://github.com/avnet-iotconnect/iotc-python-lite-sdk-demos/blob/main/microchip-polarfire-soc-dk/README.md):

| Avnet section | Do it? | Notes |
|---|---|---|
| 1 Introduction, 2 Requirements | Yes | You need FlashPro Express (Avnet points to the v2024.2 "Programming and Debug" download), a serial terminal and an SD-card flasher. |
| 3 Hardware Setup | Yes | USB-C to connector **#1**, Ethernet to connector **#2**. |
| 4 Software Setup: *Update FPGA* | Yes | Programs the reference design `.job`. This changes the board. Follow the official steps and pick the file for the Discovery Kit. |
| 4 Software Setup: *Flash Linux Image* | Yes | Official Linux4Microchip `.wic` onto your blank card. |
| 5 Device Setup, Steps 1–3 | Yes | Serial settings 115200/8/1/None. See the three ports. |
| 5 Step 4 onward, Sections 6–9 | **No** | Login, `pip install`, IoTConnect onboarding and demos are not part of TALOS bring-up. |

Avnet's "latest" FPGA and Linux releases may be newer than what we tested (see [FIRMWARE_COMPATIBILITY.md](FIRMWARE_COMPATIBILITY.md)). Write down which versions you installed.

## Flashing the Linux `.wic` image

**Windows (Avnet's method):** extract the `.wic.gz` and flash the `.wic` with Balena Etcher.

**Linux host (not tested by the team):** Balena Etcher also runs on Linux and is the safest choice, because it only offers removable drives. A command-line alternative, **which destroys the target device**:

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

After flashing, the card has (on the image we tested) a ~64 MiB **vfat** partition labelled **`boot`** and a large **ext4** partition labelled **`root`**. Only the `boot` partition is used. On the verified card it contained:

```text
boot.scr   fitImage   uboot.env        (official image)
boot-linux.scr   sel4.uImage           (added by our procedure)
```

**Linux:** most desktops auto-mount it under `/media/<you>/boot`. Otherwise:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
udisksctl mount -b /dev/sdX1        # the vfat partition labelled boot; prints the mount point
# ...copy files as in the README...
sync
udisksctl unmount -b /dev/sdX1
udisksctl power-off -b /dev/sdX     # optional, then remove the card
```

**Windows:** the `boot` partition appears as a drive letter. Windows cannot read the ext4 partition and may ask to format it. **Always click Cancel.** Turn on *View → File name extensions* so you can see you are creating `boot.scr` and not `boot.scr.scr`. Eject with *Safely Remove Hardware*.

**Before copying, always** check that the folder contains both `boot.scr` and `fitImage`. If it doesn't, you have the wrong drive or partition.

## Verify the downloaded files

Linux/macOS, from the repository root:

```bash
sha256sum -c images/SHA256SUMS
```

Windows PowerShell, from the repository root:

```powershell
Get-FileHash images\sel4.uImage, boot\boot-sel4.scr, boot\boot-linux.scr -Algorithm SHA256
Get-Content images\SHA256SUMS
```

Compare the hashes by eye. PowerShell prints them in upper case, which is fine. After copying, you can hash the files **on the card** the same way, and they must match too.

> If you cloned with Git on Windows, the repository's `.gitattributes` marks these files as binary so Git won't change line endings. Even so, a hash mismatch means **don't use the file**.

## Serial console

Settings everywhere: **115200 baud, 8 data bits, no parity, 1 stop bit, no flow control**.

The board presents three USB serial ports.

| Console | What you see | Observed on our Windows PC |
|---|---|---|
| HSS (firmware) | Hart Software Services banner at power-on; accepts `sdcard`, `boot` | COM4 |
| U-Boot / Linux / seL4 | U-Boot, `RISC-V #`, Linux login, sel4test output | COM5 (the middle-numbered port, matching Avnet's advice) |
| Third port | Not used in this procedure | n/a |

COM numbers are assigned per PC and per USB port, so identify yours by what it prints.

**Linux host (not tested by the team):** the ports usually appear as `/dev/ttyUSB0..2`, though this can vary. Stable names are under `/dev/serial/by-id/`:

```bash
ls -l /dev/serial/by-id/
sudo usermod -aG dialout "$USER"     # once, then log out and back in, so you can open the port without sudo
picocom -b 115200 /dev/ttyUSB1       # exit: Ctrl-A Ctrl-X
# or: screen /dev/ttyUSB1 115200     (exit: Ctrl-A k)
```

Opening each port in a separate terminal and power-cycling the board is the fastest way to tell them apart. Make sure your terminal sends a plain carriage return for Enter. U-Boot accepts it.

## Installer script

[`scripts/install-to-boot.sh`](../scripts/install-to-boot.sh) automates the README's §3. It is **dry-run by default**:

```bash
scripts/install-to-boot.sh "$BOOT"                        # dry run: report only
scripts/install-to-boot.sh "$BOOT" --apply                # verified baseline
scripts/install-to-boot.sh "$BOOT" --experimental --apply # experimental image + autoboot candidate (spare card!)
scripts/install-to-boot.sh "$BOOT" --restore-linux --apply
scripts/install-to-boot.sh "$BOOT" --verify               # read-only report of what is on the card
```

Safety rules it enforces:

- Repository files must match their SHA256SUMS. CRLF line endings are tolerated, and a missing or malformed entry is an error.
- The target must be a mounted vfat partition with `boot.scr` and `fitImage`, and `boot.scr` must be a U-Boot script image.
- `boot-linux.scr` is created once, only from a non-TALOS script, and is **never overwritten or deleted**. There is no option to override this; fix such a card by hand.
- Every write goes to `<name>.talos-tmp`, then is synced, hash-checked and renamed into place. The image is written before `boot.scr`, and `boot.scr` is always replaced last. A failure or interruption at any point leaves `boot.scr` as it was. A later run removes leftover `*.talos-tmp` files.

`scripts/test-installer.sh` re-runs the full test suite against disposable loop-mounted FAT images. It needs `mkfs.vfat` and `udisksctl`, and **never touches a real card**: each target is checked to be a loop device backed by its own temp file. Results: [TEST_RESULTS](../experimental/reports/TEST_RESULTS.md#installer). The installer has **not** been run with `--apply` against a physical SD card.

The installer is Linux-only (it needs `findmnt`). On Windows, follow the README's manual steps.

## Docker and build prerequisites (only for rebuilding images)

Teammates who just boot seL4 **do not need this**. To rebuild:

- Linux x86-64 with Docker Engine, and your user in the `docker` group (`docker run hello-world` works without `sudo`).
- `git` and Google's `repo` launcher (`sudo apt install repo` on Ubuntu/Mint, or see the [repo docs](https://gerrit.googlesource.com/git-repo)).
- Network access to github.com and Docker Hub, and about 12 GB of free disk for the toolchain image plus about 250 MB per build work directory.
- Toolchain image: `trustworthysystems/camkes@sha256:77dcf9c7927c138d88434d812d8bd8b86455f9418d0895682250745b192e291e` (GCC 14.2.0, CMake 3.31.6, Ninja 1.12.1, dtc 1.7.2, mkimage 2025.01). Pull it by digest so you get exactly these tools.

Experimental build: [`experimental/scripts/build-experimental.sh`](../experimental/scripts/build-experimental.sh). How the verified baseline was built: [BUILD_PROVENANCE.md](BUILD_PROVENANCE.md#rebuilding).
