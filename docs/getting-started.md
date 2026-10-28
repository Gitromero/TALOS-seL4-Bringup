# Getting started

From a new board and a new computer to the first verified seL4 run. Board setup works from any host OS. The board tool, `scripts/board.py`, needs a Linux host.

**What has been tested.** The original bring-up used a **Windows** PC for the serial consoles and a **Linux Mint 22.3** host for the SD card. Since 2026-10-21 a Linux host (Linux Mint 22.3, and Debian 13) has been the serial console and the host for every `board.py` command.

## 1. Official board setup

Follow Avnet's [PolarFire SoC Discovery Kit QuickStart](https://github.com/avnet-iotconnect/iotc-python-lite-sdk-demos/blob/main/microchip-polarfire-soc-dk/README.md) up to the point shown below, and stop there:

| Avnet section | Do it? | Notes |
|---|---|---|
| 1 Introduction, 2 Requirements | Yes | You need FlashPro Express (Avnet points to the v2024.2 "Programming and Debug" download), a serial terminal and an SD-card flasher. |
| 3 Hardware Setup | Yes | USB-C to connector **#1**, Ethernet to connector **#2**. |
| 4 Software Setup: *Update FPGA* | Yes | Programs the reference design `.job`. This changes the board. Follow the official steps and pick the file for the Discovery Kit. |
| 4 Software Setup: *Flash Linux Image* | Yes | Official Linux4Microchip `.wic` onto your card ([on Linux](sd-card.md#flashing-the-official-linux-image)). |
| 5 Device Setup, Steps 1–3 | Yes | Serial settings 115200/8/1/None. Three serial ports appear. |
| 5 Step 4 onward, Sections 6–9 | **No** | Login, `pip install`, IoTConnect onboarding and demos are not part of this project. |

The verified runs used Linux4Microchip **2026.04.1**, U-Boot **2025.07-linux4microchip-2026.04** and FPGA reference design **v2507**. Avnet's guide installs the latest releases, which may be newer and are **untested** ([firmware compatibility](hardware.md#8-firmware-compatibility)). Write down which versions you installed.

Before continuing, confirm that the board boots the official Linux and that you can see its serial output.

## 2. Get this repository

> **Placeholder:** `https://github.com/<TEAM-ORG>/TALOS-seL4-Bringup` is **not a real URL yet**. Use the link your team shares once the repository is published.

```bash
git clone https://github.com/<TEAM-ORG>/TALOS-seL4-Bringup.git   # placeholder URL
cd TALOS-seL4-Bringup
sha256sum -c images/SHA256SUMS
```

All three lines must say `OK`. On Windows PowerShell, from the repository root:

```powershell
Get-FileHash images\sel4test.uImage, boot\boot-auto.scr, boot\boot-linux.scr -Algorithm SHA256
Get-Content images\SHA256SUMS
```

Compare the hashes by eye (PowerShell prints them in upper case, which is fine). The repository's `.gitattributes` marks these files as binary so Git won't change their line endings; even so, a mismatch means **don't use the file**. Checksums detect corruption, but they don't prove who made a file ([what they prove](building.md#checksums-and-authenticity)).

## 3. Serial ports

Settings everywhere: **115200 baud, 8 data bits, no parity, 1 stop bit, no flow control**.

USB-C connector **#1** goes to an FTDI **FT4232H** on the board (it identifies as `Microsemi Embedded FlashPro5`, USB ID `1514:2008`) with four channels:

| Channel | Console | What you see | Windows (one PC) | Linux name (udev rule) |
|---|---|---|---|---|
| interface 0 | JTAG | not a console | not shown | `/dev/polarfire-jtag` |
| interface 1 | **HSS** (firmware) | Hart Software Services banner at power-on; `>>` prompt | COM4 | `/dev/polarfire-hss` |
| interface 2 | **U-Boot / Linux / seL4** | U-Boot, `RISC-V #`, Linux login, seL4 and test output | COM5 (the middle-numbered port) | `/dev/polarfire-uboot` |
| interface 3 | Third UART | silent so far | not used | `/dev/polarfire-uart3` |

COM and `ttyUSB` numbers are assigned per computer and change, so the tools never use them. More about the channels and reset: [hardware.md](hardware.md#7-serial-channels-and-board-reset).

### Windows or macOS

Use any serial terminal (PuTTY, Tera Term; `screen` on macOS) on the HSS and U-Boot ports. That is all the SD-card procedure needs. `scripts/board.py` does not run on these systems.

### Linux

Verified on Linux Mint 22.3 and Debian 13.

1. **Permission.** Your user must be in the `dialout` group (`groups` lists it). If not: `sudo usermod -aG dialout "$USER"`, then log out and back in.
2. **Python 3.8 or newer** (`python3 --version`). `board.py` uses only the standard library.
3. **Bind all four channels and get stable names.** Out of the box, the kernel's `ftdi_sio` driver binds **only interface 2** of this board's FT4232H, so a single `/dev/ttyUSB0` appears (the U-Boot console). The repository's udev rule binds every channel each time the board is plugged in and adds the `/dev/polarfire-*` names. Install it once (asks for your password; it also refreshes a board that is already plugged in):

   ```bash
   scripts/board.py install-udev
   ```

   By hand, the same thing is:

   ```bash
   sudo cp host/udev/99-polarfire-discovery.rules /etc/udev/rules.d/
   sudo udevadm control --reload
   ls -l /dev/polarfire-*          # after unplugging and replugging the board
   ```

   Without the rule, `sudo sh -c 'echo 1514 2008 > /sys/bus/usb-serial/drivers/ftdi_sio/new_id'` binds all channels until the next unplug (the file is under **`/sys/bus/usb-serial/`**; `/sys/bus/usb/drivers/ftdi_sio/` has no `new_id`). The tools then find the ports as `/dev/serial/by-id/*FlashPro5*-ifNN-port0`.

   Binding also claims interface 0, the JTAG channel. That is harmless for the consoles. If FlashPro programming from this computer then fails to find the board, release it with `echo <usb-path>:1.0 | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind` (`<usb-path>` as listed by `ls /sys/bus/usb/drivers/ftdi_sio/`, e.g. `1-1`). This has **not** been needed or tested yet.

4. **Optional, for `flash --lan` only:** Docker (your user in the `docker` group) and one firewall rule ([network boot](flashing.md#network-boot)).

## 4. First run

With the board powered and USB-C #1 connected:

```bash
scripts/board.py status
```

Every line should be `[ok]`: the board on USB, all 4 channels bound, the udev rule installed, the four ports present, and `HSS answers Enter with '>>'`. Then open the U-Boot console in one terminal:

```bash
scripts/board.py console          # exit: Ctrl-a Ctrl-x
```

and in another, load and boot the shipped image:

```bash
scripts/board.py flash
```

The console shows the board resetting, U-Boot, the transfer and the whole test run. `flash` ends with `PASSED: Test suite passed. 118 tests passed. 49 tests disabled.` and exit code 0. Nothing was written to the board: a power cycle boots the official Linux again.

To make the board boot seL4 by itself instead, see [sd-card.md](sd-card.md). To load your own images, see [flashing.md](flashing.md).

## Optional: shell alias

`scripts/board.py` works from any directory. A short alias is a personal choice, not part of the repository's workflow, e.g. in your own shell startup file:

```bash
alias board="$HOME/path/to/TALOS-seL4-Bringup/scripts/board.py"
```
