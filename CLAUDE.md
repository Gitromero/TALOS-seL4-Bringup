# Notes for AI coding assistants (and humans skimming)

PolarFire SoC Discovery Kit (MPFS-DISCO-KIT) seL4 bring-up. Shared by the team: keep everything host-neutral.

- **Read first:** `context/SEL4_BRINGUP_CONTEXT.md`. Its dated updates at the end are the current state; the latest one wins. Add a new dated update there when you verify or change something important, and say plainly what ran on the real board and what didn't.
- **Daily commands:** `scripts/pf status | flash [--lan] [image] | console | hss | reset | tftp | install-udev` (README, "Day-to-day commands"). `pf flash` loads over USB (`scripts/usb-flash.sh`, YMODEM), `pf flash --lan` over TFTP (`scripts/network-flash.sh`). Loading images: `docs/FLASHING.md` (network details: `docs/NETBOOT.md`). Serial setup: `docs/SETUP.md`.
- **Serial ports:** never hard-code `ttyUSB` numbers. Use `/dev/polarfire-*` (udev rule) or `/dev/serial/by-id/*FlashPro5*-ifNN-port0`: if01 HSS, if02 U-Boot/seL4, if03 third UART, if00 JTAG. Only one program can read a port at a time unless it goes through `scripts/serial-share.py`: always use it (`pf console`, `serial-share.py send`, or `ensure_broker()` from Python) and never open the device directly. Don't start a plain picocom/screen on a port a script needs. Details: `docs/SHARED_CONSOLE.md`.
- **Safe by default:** `pf flash` (USB or `--lan`) is RAM only. Never `saveenv` in U-Boot. Never write the SD card except through `scripts/install-to-boot.sh` (dry run by default, keeps `boot-linux.scr`). Never touch the FPGA/HSS.
- **Board state:** `pf reset` and `pf flash` reboot the board; whatever runs on it is lost. Check `pf status` first if the board might be in use by someone else.
- **Privacy rule for committed files:** no usernames, home paths, host names, real IP/MAC addresses or board serial numbers. Use examples like `192.168.1.10`. `scripts/privacy_audit.py` scans binary artifacts; check docs by eye.
- **Images:** `images/sel4test.uImage` is the only hardware-verified image (SHA-256 in `images/SHA256SUMS`). Rebuilds go through `scripts/build-sel4test.sh` and must stay byte-identical.
- **Style:** scripts are bash with `set -euo pipefail` and a usage header that `--help` prints; inline Python runs with `python3 -I`. Docs are plain, direct Markdown with tables, and record verification dates.
