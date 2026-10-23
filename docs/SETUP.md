# Setup details (host side)

This page adds host-specific detail to the [root README](../README.md). The README is still the procedure to follow.

**What has been tested.** The original bring-up used a **Windows** PC for the serial consoles (COM4/COM5) and a **Linux Mint 22.3** host to mount the SD card's FAT boot partition and copy files. On 2026-10-21 the same Linux Mint host was used as the serial console for the network-boot and Rust sessions ([below](#serial-console-on-a-linux-host)). The Linux `.wic` flashing instructions are standard equivalents that **the team has not tested on this board**.

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
boot.scr   fitImage   uboot.env           (official image)
boot-linux.scr   sel4test.uImage          (added by our procedure; boot.scr replaced)
```

**Linux:** most desktops auto-mount it under `/media/<you>/boot`. This prints where it is mounted (nothing means not mounted):

```bash
findmnt -nro TARGET -S LABEL=boot
```

Otherwise, mount it by hand (`sdX` is your card, found with `lsblk`):

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
udisksctl mount -b /dev/sdX1        # the vfat partition labelled boot; prints the mount point
sync                                # after copying files as in the README
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
Get-FileHash images\sel4test.uImage, boot\boot-auto.scr, boot\boot-linux.scr -Algorithm SHA256
Get-Content images\SHA256SUMS
```

Compare the hashes by eye. PowerShell prints them in upper case, which is fine. After copying, you can hash the files **on the card** the same way, and they must match too.

> If you cloned with Git on Windows, the repository's `.gitattributes` marks these files as binary so Git won't change line endings. Even so, a hash mismatch means **don't use the file**.

## Serial console

Settings everywhere: **115200 baud, 8 data bits, no parity, 1 stop bit, no flow control**.

The board's USB-C connector **#1** goes to an on-board FTDI **FT4232H** (it identifies as `Microsemi Embedded FlashPro5`, USB ID `1514:2008`). It has four channels: one for JTAG programming and three UARTs.

| Console | What you see | Windows (one PC) | Linux | FT4232H channel |
|---|---|---|---|---|
| JTAG | Not a console | not shown | `/dev/ttyUSB0` | interface 0 |
| HSS (firmware) | Hart Software Services banner at power-on; `>>` prompt; accepts `sdcard`, `boot` | COM4 | `/dev/ttyUSB1` | interface 1 |
| U-Boot / Linux / seL4 | U-Boot, `RISC-V #`, Linux login, seL4 and test output | COM5 (the middle-numbered port, matching Avnet's advice) | `/dev/ttyUSB2` | interface 2 |
| Third UART | Silent in this procedure | n/a | `/dev/ttyUSB3` | interface 3 |

COM and `ttyUSB` numbers are assigned per computer and can change. The interface number is fixed by the hardware, so on Linux use the stable names under `/dev/serial/by-id/`, which end in `-if01-port0`, `-if02-port0` and so on.

**One program per port.** If two programs have the same port open (two terminals, or a terminal and a script), Linux hands each incoming byte to only one of them, so both see gaps and the console looks frozen or garbled. Close one.

### Serial console on a Linux host

Verified on Linux Mint 22.3 (kernel 7.0) with `picocom`.

**1. Permission.** Your user must be in the `dialout` group (`groups` lists it). If not: `sudo usermod -aG dialout "$USER"`, then log out and back in.

**2. Make all three UARTs appear.** Out of the box, the kernel's `ftdi_sio` driver binds **only interface 2** of this board's FT4232H, so a single `/dev/ttyUSB0` appears, and it is the U-Boot/seL4 console, not the first port. To bind every channel, tell `ftdi_sio` about the board's USB ID:

```bash
sudo sh -c 'echo 1514 2008 > /sys/bus/usb-serial/drivers/ftdi_sio/new_id'
ls /dev/serial/by-id/          # now four entries: ...-if00-port0 through ...-if03-port0
```

The `new_id` file is under **`/sys/bus/usb-serial/`**. `/sys/bus/usb/drivers/ftdi_sio/` has no `new_id`, and writing there fails with `Permission denied` even as root. The binding lasts until the board is unplugged or the computer restarts; run the command again after that.

Binding also claims interface 0, the JTAG channel, as `/dev/ttyUSB0`. That is harmless for the consoles. If FlashPro programming from this computer then fails to find the board, release it with `echo <usb-path>:1.0 | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind`, where `<usb-path>` is the board's device, e.g. `1-1` (`ls /sys/bus/usb/drivers/ftdi_sio/`). This last step has **not** been needed or tested yet.

**3. Open the consoles**, one terminal each. HSS:

```bash
picocom -b 115200 /dev/serial/by-id/*FlashPro5*-if01-port0
```

U-Boot / seL4:

```bash
picocom -b 115200 /dev/serial/by-id/*FlashPro5*-if02-port0
```

Exit picocom with `Ctrl-a Ctrl-x`. Enter sends a carriage return, which U-Boot accepts. `screen <port> 115200` works too (exit: `Ctrl-a k`).

On the verified host, the HSS port answered Enter with `>>`, and the U-Boot port showed U-Boot, then seL4 and sel4test after `bootm`.

## Installer script

[`scripts/install-to-boot.sh`](../scripts/install-to-boot.sh) automates the README's §3. It is **dry-run by default**. It takes the mount point of the card's FAT `boot` partition:

```bash
BOOT=$(findmnt -nro TARGET -S LABEL=boot)
```

Then one of these modes (reference, not a sequence to paste as a whole):

```bash
scripts/install-to-boot.sh "$BOOT"                        # dry run: report only
scripts/install-to-boot.sh "$BOOT" --apply                # sel4test.uImage + autoboot boot.scr
scripts/install-to-boot.sh "$BOOT" --restore-linux --apply
scripts/install-to-boot.sh "$BOOT" --verify               # read-only report of what is on the card
```

Safety rules it enforces:

- Repository files must match `images/SHA256SUMS`. CRLF line endings are tolerated, and a missing or malformed entry is an error.
- The target must be a mounted vfat partition with `boot.scr` and `fitImage`, and `boot.scr` must be a U-Boot script image.
- `boot-linux.scr` is created once, only from a non-TALOS script, and is **never overwritten or deleted**. TALOS scripts are recognised by hash, including both scripts from the repository's first revision (`boot-sel4.scr` and the autoboot that loaded `sel4-experimental.uImage`), so a card set up earlier is handled safely. There is no option to override this; fix such a card by hand.
- Every write goes to `<name>.talos-tmp`, then is synced, hash-checked and renamed into place. The image is written before `boot.scr`, and `boot.scr` is always replaced last. A failure or interruption at any point leaves `boot.scr` as it was. A later run removes leftover `*.talos-tmp` files.
- `--verify` also lists images from earlier revisions (`sel4.uImage`, `sel4-experimental.uImage`) if present. They are unused and safe to delete.

`scripts/test-installer.sh` re-runs the full test suite (88 checks) against disposable loop-mounted FAT images. It needs `mkfs.vfat`, `udisksctl` and the repository's git history (for the first-revision scripts), and **never touches a real card**: each target is checked to be a loop device backed by its own temp file. Results: [TEST_RESULTS](../reports/TEST_RESULTS.md#installer).

The installer is Linux-only (it needs `findmnt`). On Windows, follow the README's manual steps.

## Docker and build prerequisites (only for rebuilding images)

Teammates who just boot seL4 **do not need this**. To rebuild:

- Linux x86-64 with Docker Engine, and your user in the `docker` group (`docker run hello-world` works without `sudo`).
- `git` and Google's `repo` launcher (`sudo apt install repo` on Ubuntu/Mint, or see the [repo docs](https://gerrit.googlesource.com/git-repo)).
- Network access to github.com and Docker Hub, and about 12 GB of free disk for the toolchain image plus about 250 MB per build work directory.
- Toolchain image: `trustworthysystems/camkes@sha256:77dcf9c7927c138d88434d812d8bd8b86455f9418d0895682250745b192e291e` (GCC 14.2.0, CMake 3.31.6, Ninja 1.12.1, dtc 1.7.2, mkimage 2025.01). Pull it by digest so you get exactly these tools.

Build the image with [`scripts/build-sel4test.sh`](../scripts/build-sel4test.sh) ([details](BUILD_PROVENANCE.md#rebuilding)). The [Rust root task](../rust-root-task/README.md) additionally needs the `sel4-rust-tutorial` image, and [network boot](NETBOOT.md) needs Docker and one firewall rule.
