# TALOS seL4 Bring-up: PolarFire SoC Discovery Kit

Tools, images and documentation for running seL4 on a Microchip PolarFire SoC Discovery Kit (MPFS-DISCO-KIT, RISC-V 64-bit). It ships a hardware-verified seL4 + sel4test image, an SD-card installer that makes the board boot it by itself, and a board tool that loads any U-Boot image into the board's RAM over USB or Ethernet and reports whether it passed.

> **Repository status:** assembled locally and **not published yet**. The GitHub URL below is a placeholder. See [Publication status](#publication-status).

## What works on the board

| Capability | Status | Guide |
|---|---|---|
| seL4 + sel4test **booting automatically** from the SD card | ✅ Verified: `118 tests passed. 49 tests disabled.` with no typing | [docs/sd-card.md](docs/sd-card.md) |
| Load and boot an image **over USB**, no SD-card swaps: `scripts/board.py flash` | ✅ Verified | [docs/flashing.md](docs/flashing.md) |
| The same **over Ethernet** (DHCP + TFTP): `scripts/board.py flash --lan` | ✅ Verified | [docs/flashing.md](docs/flashing.md#network-boot) |
| Shared serial consoles: people, scripts and AI agents on one port at once | ✅ Verified | [docs/flashing.md](docs/flashing.md#shared-consoles) |
| Reproducible, byte-identical rebuild of the image from pinned public sources | ✅ Verified | [docs/building.md](docs/building.md) |
| `no_std` Rust root task (`Hello from Rust on seL4!`) | ✅ Verified (experiment) | [experiments/rust-root-task/](experiments/rust-root-task/README.md) |
| Peripheral map; user LEDs driven by register writes | ✅ LEDs verified from U-Boot | [docs/hardware.md](docs/hardware.md) |

Verification dates and the exact commands run are in [reports/TEST_RESULTS.md](reports/TEST_RESULTS.md).

## Quick start

You need the board set up with the official Linux image and FPGA design first ([docs/getting-started.md](docs/getting-started.md#1-official-board-setup)). Then pick one:

**A. Make the board boot seL4 from its SD card** (any host OS; no tools needed beyond a file copy). Copy two files onto the card's FAT `boot` partition and power on. On Linux the installer does it safely:

```bash
git clone https://github.com/<TEAM-ORG>/TALOS-seL4-Bringup.git   # placeholder URL
cd TALOS-seL4-Bringup
sha256sum -c images/SHA256SUMS
BOOT=$(findmnt -nro TARGET -S LABEL=boot)
scripts/install-to-boot.sh "$BOOT"            # dry run: checks everything, changes nothing
scripts/install-to-boot.sh "$BOOT" --apply
```

Full procedure, Windows steps and restoring Linux: [docs/sd-card.md](docs/sd-card.md).

**B. Load images from a Linux computer** with the board's USB-C **#1** connected (RAM only: the SD card is never written):

```bash
scripts/board.py install-udev                 # once per computer (sudo)
scripts/board.py status                       # board found? ports free? HSS alive?
scripts/board.py flash                        # boot images/sel4test.uImage, wait for the result
```

Full guide: [docs/flashing.md](docs/flashing.md).

## Commands

All board work goes through one tool, `scripts/board.py` (Linux host, Python 3.8+, standard library only). It works over SSH: nobody needs to be at the board except to power-cycle it or swap the SD card. `scripts/board.py <command> --help` describes every option.

| Task | Command |
|---|---|
| Check the board, ports and last result | `scripts/board.py status` |
| List the serial ports | `scripts/board.py ports` |
| Load an image over USB and boot it | `scripts/board.py flash [image] [--expect REGEX]` |
| The same over Ethernet | `scripts/board.py flash --lan [image]` |
| Open a console (shared) | `scripts/board.py console` · `console --hss` · `console --uart3` |
| Type on a console from a script | `scripts/board.py send 'version\r'` |
| Reboot the board | `scripts/board.py reset` |
| TFTP server for `--lan` | `scripts/board.py tftp start\|stop\|status\|logs` |
| Install the udev rule | `scripts/board.py install-udev` |
| Install seL4 on an SD card / restore Linux | `scripts/install-to-boot.sh BOOT [--apply \| --restore-linux \| --verify]` |
| Rebuild the image reproducibly | `scripts/build-sel4test.sh WORK_DIR` |
| Run the offline tests | `tests/run.sh` |
| Verify shipped files | `sha256sum -c images/SHA256SUMS` |

Exit codes for `board.py`: `0` passed or booted, `1` the image reported failure, `2` usage or host problem, `3` board or U-Boot problem, `4` timed out. How the tools are organized and why: [docs/tooling.md](docs/tooling.md).

## Safety

- `board.py flash` writes **RAM only**. It never writes the SD card, eMMC, QSPI, FPGA, HSS or U-Boot's saved environment, and never runs `saveenv`. A power cycle boots whatever is installed.
- The SD card is changed only by `scripts/install-to-boot.sh`, which is a dry run unless given `--apply` and never overwrites the Linux boot-script backup.
- `flash` and `reset` reboot the board, so whatever runs on it is lost. Check `scripts/board.py status` first if someone else may be using it.

## Documentation

| Page | Contents |
|---|---|
| [docs/getting-started.md](docs/getting-started.md) | Official board setup, host setup, serial ports, first run |
| [docs/sd-card.md](docs/sd-card.md) | Install seL4 on the SD card, boot, manual boot, restore Linux |
| [docs/flashing.md](docs/flashing.md) | Load images over USB or Ethernet; shared consoles; manual procedures |
| [docs/building.md](docs/building.md) | Rebuild the image; verify, audit and package releases |
| [docs/hardware.md](docs/hardware.md) | Peripheral and memory map, serial channels, reset, firmware versions |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Failures and fixes |
| [docs/tooling.md](docs/tooling.md) | Tool architecture, conventions, tests, plan for moving tools into the main TALOS repository |
| [docs/provenance.md](docs/provenance.md) | Where every shipped file came from; licensing |
| [history/](history/README.md) | How the bring-up happened: dated log, original guide, first-image build |

## Repository layout

```text
scripts/board.py             the board tool (status, ports, flash, console, send, reset, tftp, install-udev)
scripts/polarfire/           its modules: ports, serial_share, uboot, ymodem, tftp
scripts/install-to-boot.sh   SD-card installer (dry run by default; --restore-linux, --verify)
scripts/build-sel4test.sh    reproducible build of images/sel4test.uImage
scripts/make-source-archive.sh, privacy_audit.py   GPL source archive, artifact privacy scan
images/                      sel4test.uImage and SHA256SUMS
boot/                        autoboot script (boot-auto), Linux boot script backup (boot-linux), sources
board/discovery/             the board's device tree, as extracted from the running board
patches/, source/            changes to, and the manifest of, the pinned upstream sources
host/udev/                   Linux udev rule: bind all four serial channels, /dev/polarfire-* names
tftp/                        TFTP server (Docker) for flash --lan
tests/                       offline test suite (tests/run.sh) and the SD installer test
reports/                     build report, privacy audit, test results for the shipped files
experiments/rust-root-task/  no_std Rust seL4 root task (toolchain check)
history/                     bring-up log and earlier procedures, kept as a record
docs/                        the guides above
LICENSES/, THIRD_PARTY_NOTICES.md   third-party licence texts and notices
```

## Publication status

Prepared locally, and **not ready for public release** until these are resolved:

1. **Team licence:** no licence has been chosen for TALOS-authored docs and scripts (third-party licences are covered in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).
2. **GPL source:** publish the corresponding-source archive (`scripts/make-source-archive.sh`) next to the binary in each release.
3. **Device tree licence:** the licence of the board-extracted DTS is assumed to be the upstream "(GPL-2.0 OR MIT)" but not confirmed.
4. **Git history:** the board's MAC address has been removed from every source file (2026-10-22), but the repository's **first commit** still contains it, along with the first image's developer paths. Publish from a fresh history (for example a new repository with one squashed commit), or rewrite the history, instead of pushing the existing one.

The main TALOS repository's name is deliberately kept out of this repository (owner decision). Details: [docs/provenance.md](docs/provenance.md#licensing-and-attribution).
