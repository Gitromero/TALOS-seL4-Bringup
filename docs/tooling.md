# Tooling: architecture, conventions and plans

How the repository's tools are organized, the conventions new tools follow, what the tests cover, and which tools should eventually move to the main TALOS repository. Read this before adding or changing a tool.

## The tools

| Tool | Audience | Purpose |
|---|---|---|
| `scripts/board.py` | everyone with a board | Everything that talks to the board: `status`, `ports`, `flash [--lan]`, `console`, `send`, `reset`, `tftp`, `install-udev` |
| `scripts/polarfire/` | `board.py`, scripts, agents | The modules behind it (below). Not run directly. |
| `scripts/install-to-boot.sh` | SD-card setup and recovery | Install seL4 + autoboot on the card, restore Linux, verify a card |
| `scripts/build-sel4test.sh` | maintainers | Reproducible build of `images/sel4test.uImage` from pinned sources |
| `scripts/privacy_audit.py` | maintainers, before a release | Scan binaries for private data |
| `scripts/make-source-archive.sh` | maintainers, for a release | GPL corresponding-source archive |
| `tftp/serve.sh` | `board.py tftp`, `flash --lan` | TFTP-only dnsmasq in Docker |
| `host/udev/99-polarfire-discovery.rules` | Linux hosts, via `board.py install-udev` | Bind all four FT4232H channels; stable `/dev/polarfire-*` names |
| `boot/boot-auto.cmd`, `boot-linux.cmd` | the SD card | U-Boot autoboot (with Linux fallback) and the original Linux script ([boot/](../boot/README.md)) |
| `tests/run.sh` | everyone, before committing | All offline tests |
| `experiments/rust-root-task/build.sh` | experiment | Rust root task build (needs a local Docker image) |

### Why one board tool

Hardware operations share most of their logic: find the ports, check nobody else holds them, reset through HSS, stop U-Boot's autoboot, type commands slowly, load to `0x8e000000`, verify the CRC, `bootm`, watch for a result. Before 2026-10-28 that lived in three bash scripts with embedded Python (`pf`, `usb-flash.sh`, `network-flash.sh`): the two flash scripts shared 132 identical lines, and port lookup and the "who holds this port" check existed three times. One command with subcommands removes that duplication, gives one `--help`, one set of exit codes and one log format, and lets the U-Boot logic be tested offline.

Build, SD-card and release tools stay separate scripts. They don't touch the board, are run rarely, and are clearest as plain sequences of shell commands.

`board.py` uses the same name and the same verbs for shared operations (`flash`, `ports`, `console [--hss]`) as the main TALOS repository's board loader, so the two can converge ([below](#moving-tools-to-the-main-talos-repository)).

### Official tools and personal shortcuts

Everything in this repository must work from a clean clone after the documented setup, with no personal shell configuration. Personal conveniences (aliases, shell functions, short command names, machine-specific paths, SSH shortcuts) belong in your own dotfiles, not here. An alias such as `alias board=.../scripts/board.py` is fine as long as no document or script depends on it.

The former `scripts/pf` was audited on 2026-10-28 against this rule. It was a standalone bash script with repository-relative paths and no personal dependencies (no alias, PATH entry or shell function existed for it), so it was not a personal tool in the technical sense. But its short name and its role as a thin front end over two other scripts made it a development shortcut presented as the official interface, while it duplicated their port logic. Its useful parts (`status`, `reset`, `install-udev`, the shared consoles) moved into `board.py`; it was removed rather than kept as a wrapper, so there is one way to do each thing.

### `scripts/polarfire/`

| Module | Responsibility | Depends on |
|---|---|---|
| `__init__.py` | Exit codes (`OK`, `IMAGE_FAILED`, `HOST`, `BOARD`, `TIMEOUT`, `INTERRUPTED`) and `Failure(code, message)` | nothing |
| `ports.py` | Find the four channels by role (override variable → udev name → `by-id`); who holds a port; USB/sysfs facts for `status` | `serial_share` (to recognise the broker) |
| `serial_share.py` | The shared-console broker, its client and control socket, the interactive console | standard library only: it is also the broker's entry point (`serial_share.py serve <port>`) |
| `ymodem.py` | YMODEM sender over any object with `write()` and `wait_byte()` | nothing |
| `uboot.py` | `Console` (log, echo, pattern waits, slow typing); `get_prompt`, `load_serial`, `load_tftp`, `verify`, `boot`, `watch`; image header checks | `serial_share`, `ymodem` |
| `tftp.py` | Stage an image, start the server, find the host address, probe the server | `tftp/serve.sh`, Docker |

Linux only (sysfs, `/proc`, termios, Unix sockets), Python 3.8+, standard library only.

## Conventions

**Shell scripts:** `#!/usr/bin/env bash`, `set -euo pipefail` (the installer test deliberately uses `set -uo pipefail` to collect failures), a header comment with a `Usage:` section that `-h`/`--help` prints, exit `0` on `--help`, `2` on usage errors. Paths are relative to the script (`$(dirname "$0")`), never to the caller's directory or a home directory. `shellcheck -S warning` clean.

**Python:** executable scripts start with `#!/usr/bin/env python3` and use `argparse`; standard library only, so nothing needs installing; inline Python in shell scripts runs with `python3 -I`. `board.py` sets `sys.dont_write_bytecode` so no `__pycache__` appears in `scripts/` (`.gitignore` excludes it anyway).

**Board tools:**

- RAM only. Nothing writes the SD card except `install-to-boot.sh` (dry run unless `--apply`); nothing writes eMMC, QSPI, FPGA or HSS; nothing runs `saveenv`.
- Every check that can be done on the host happens before the board is touched.
- Serial ports are found by role and opened through the broker, never by `ttyUSB` number and never directly while a broker might be running.
- Exit codes are the six in `polarfire/__init__.py`; messages for host problems go to stderr as `error: ...`, run results to stdout as `==> ...`.
- Timeouts are named constants at the top of `uboot.py`.
- Hardware facts that explain unusual code (U-Boot dropping fast keystrokes, `loady` not setting `fileaddr`, the FTDI latency timer) are commented where they matter.

**Docs:** plain Markdown with tables; record what was verified on the board and when; say plainly what was not. Dated history goes in [history/](../history/README.md), not in the guides.

**Privacy:** no usernames, home paths, host names, real IP/MAC addresses or board serial numbers in committed files; use examples like `192.168.1.10`. The main TALOS repository's name is kept out of this repository.

## Tests

`tests/run.sh` runs everything that needs no board, network or root:

| Test | Covers |
|---|---|
| `test_uboot.py` | The flash sequence against `fake_uboot.py`, a simulated U-Boot console that receives YMODEM like `loady` and answers `dhcp`, `tftpboot`, `crc32`, `iminfo` and `bootm`: baud switching and restore, NAK resend, abort and retry, CRC mismatch, DHCP retry, pass/fail/timeout/idle results, autoboot stop, a lost console, image header checks, YMODEM framing |
| `test_host.py` | Port lookup and holder detection; the broker on a pseudo-terminal (fan-out, input order, exclusive control socket, error replies, exit and cleanup, stale sockets, direct send); TFTP staging and probe |
| `test_cli.py` | `--help` and usage errors for every tool; `flash` refusing bad images and missing ports before touching the board |
| `test_repository.py` | Markdown links and anchors, tool permissions and shebangs, no tracked bytecode, no retired names outside `history/` and `reports/`, no host paths, shipped image hashes |
| `test-installer.sh` | The SD installer on disposable FAT images (88 checks; needs `mkfs.vfat` and `udisksctl`) |
| shellcheck | All shell scripts, if installed |

What only the board can verify, and the procedure: with the board on USB-C #1 (and Ethernet #2 for the second line), run

```bash
scripts/board.py flash                 # expect PASSED ... 118 tests passed. 49 tests disabled., exit 0
scripts/board.py flash --lan           # same over Ethernet
```

while `scripts/board.py console` is open in another terminal (it must show the whole run). Record the date and result in [reports/TEST_RESULTS.md](../reports/TEST_RESULTS.md).

## Moving tools to the main TALOS repository

The main TALOS repository has its own `scripts/board.py`: a single-file, cross-platform (Linux, macOS, Windows) loader built on pyserial. It builds an image with Nix or takes an ELF, wraps the ELF as a uImage in Python, loads it with `loady`, checks the CRC, boots it, and watches for TALOS pass/fail lines; it also has `ports`, `console` and `uimage`. It has no network boot, no shared console and no `status`. This repository must not become a dependency of it; code moves by copying or adapting, and each repository keeps its own copy until one is retired.

| Component here | Recommendation | Notes |
|---|---|---|
| `polarfire/ymodem.py` | **Copy as is** | Pure protocol, no OS dependencies, tested. Replaces the YMODEM code inside the main repository's `Board` class. |
| U-Boot sequence (`polarfire/uboot.py`: prompt, load, verify, boot, watch) | **Adapt** | The same sequence exists there. Converge on one `Console` that works over either a broker socket (Linux) or a pyserial port (macOS, Windows): it only needs `sendall`/`recv`-style methods. Keep image-specific patterns (sel4test, TALOS) as arguments, as `watch()` already does. |
| Port lookup (`polarfire/ports.py`) | **Merge** | Combine this module's udev/by-id lookup with the main repository's pyserial interface-number and FTDI-suffix lookup, behind one `find(role)`. |
| Holder check | **Copy** | Already ported there (Linux `/proc` scan). |
| Network boot (`polarfire/tftp.py`, `load_tftp`, `tftp/serve.sh`) | **Adapt when needed** | Linux and Docker only. Port once someone needs `--lan` there; keep it optional. |
| Shared-console broker (`polarfire/serial_share.py`) | **Port later, Linux/macOS only** | Unix sockets and termios; no Windows equivalent. Valuable for agents and remote work; the main repository can use it when present and fall back to opening the port directly. |
| `status` report, `reset`, `send` | **Adapt** | Generic diagnostics; the sysfs parts are Linux-only and must degrade gracefully elsewhere. |
| `host/udev/99-polarfire-discovery.rules`, `install-udev` | **Copy** | Board-specific, host-side, small. |
| ELF → uImage wrapping | **Stays there** | Already in the main repository (byte-identical to seL4's `make-uimage`); this repository ships a ready uImage. |
| `build-sel4test.sh`, `patches/`, `source/`, `images/` | **Bringup only** | Pinned sel4test reproduction and known-good recovery image. |
| `install-to-boot.sh`, `boot/` | **Bringup only** | SD installation, Linux restore and recovery. |
| `privacy_audit.py`, `make-source-archive.sh` | **Bringup only** (copy if the main repository starts shipping binaries) | Release compliance for the shipped image. |
| `history/`, `reports/` | **Bringup only** | Evidence of the bring-up. |

Portability work still needed before a move: a serial transport abstraction (broker socket vs. pyserial) under `uboot.Console`; Windows/macOS port lookup (already solved in the main repository); and making the sysfs-based `status` checks optional.
