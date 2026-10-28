# Loading images onto the board

Boot an image straight from your computer, with no SD-card swaps. U-Boot copies the image into RAM and boots it with the same `bootm` as the manual SD boot. **Nothing is written to the SD card, eMMC, QSPI or U-Boot's saved environment**, so a power cycle boots whatever is on the card again.

| | **USB (default)** | Network |
|---|---|---|
| Command | `scripts/board.py flash [image]` | `scripts/board.py flash --lan [image]` |
| Cables | USB-C **#1** only | USB-C **#1** + Ethernet **#2** on your network |
| Host setup | the [serial ports](getting-started.md#linux) | plus Docker and one [firewall rule](#2-allow-tftp-through-the-firewall) |
| 3 MB sel4test image | about 25 s | a few seconds |
| How | U-Boot `loady` (YMODEM) over the U-Boot serial port | U-Boot `dhcp` + `tftpboot` |

Use **USB** unless the image is large or you load it many times an hour. Both are verified on the Discovery Kit with `images/sel4test.uImage`: `Test suite passed. 118 tests passed. 49 tests disabled.` (USB since 2026-10-26, network since 2026-10-25; with `scripts/board.py` on 2026-10-28).

`flash` reboots the board: whatever runs on it is lost. Run `scripts/board.py status` first if someone else might be using it.

## The flash command

From the repository root (or anywhere: paths are resolved from the script), on the computer the board's USB-C #1 is plugged into. Over SSH is fine.

```bash
scripts/board.py flash                                   # images/sel4test.uImage
scripts/board.py flash my.uImage --expect 'Hello from Rust on seL4!'
scripts/board.py flash my.uImage --console               # boot, then stay on the seL4 console
scripts/board.py flash --lan my.uImage                   # over Ethernet
```

What it does, stopping with a clear message at the first problem:

1. **Checks the image** on the host: a legacy uImage or FIT, and a uImage's load range must not overlap the `0x8e000000` staging address.
2. **Checks the host**: finds the ports ([how](hardware.md#7-serial-channels-and-board-reset)) and refuses to start if a program that doesn't share, such as a plain `picocom`, has one open. With `--lan`, it also stages the image in `tftp/root/`, starts the TFTP server if needed and fetches the first block from it, so a broken server is caught before the board is touched.
3. **Gets to the `RISC-V #` prompt**: sends `RESET` to the HSS console and stops U-Boot's autoboot. With `--no-reset` it uses a prompt that is already there, or waits up to 5 minutes for someone to reset the board.
4. **Loads the image** to `0x8e000000`:
   - USB: `loady 0x8e000000 1500000`, switches the port to 1.5 Mbaud with the FTDI 1 ms latency timer, sends the image with YMODEM (1 KiB blocks, CRC-16), and switches back to 115200. One retry.
   - Network: `setenv autoload no`, `dhcp` (3 tries), `tftpboot` (2 tries, byte count checked).
5. **Verifies** it: `crc32` must equal the file's CRC-32, and `iminfo` must report `Verifying Checksum ... OK`.
6. **Boots** it: `bootm 0x8e000000 - ${fdtcontroladdr}`.
7. **Watches** the console. Success is `--expect REGEX`; for sel4test images the default is the `Test suite passed` line. Without a pattern it finishes after `--idle` seconds (20) of silence. `Test suite failed`, `Kernel panic`, `seL4 failed assertion` and `--fail REGEX` count as failures. `--timeout` (600 s) bounds the wait.

Commands are typed one character every 8 ms, because U-Boot drops characters that arrive faster. Everything is shown live and saved to `logs/flash-<usb|lan>-<time>.log` (git-ignored), ending with the result line that `status` reports. `scripts/board.py flash --help` lists every option.

| Exit code | Meaning |
|---|---|
| `0` | passed (pattern seen), or booted and went quiet |
| `1` | the image printed a failure pattern |
| `2` | usage error or host problem (bad image, port missing or held, TFTP server) |
| `3` | board or U-Boot problem (no prompt, transfer, DHCP/TFTP, checksum, `bootm`) |
| `4` | booted, but no result before `--timeout` |
| `130` | interrupted (Ctrl-C); mid-transfer, U-Boot is told to abort |

### USB speed

Measured on the board on 2026-10-26 with `images/sel4test.uImage` (3,021,688 bytes), each run ending in `118 tests passed`:

| `--baud` | Transfer time |
|---|---|
| `1500000` (default) | 23.6 s |
| `921600` | 35.4 s |
| `115200` | 268 s |

3 Mbaud does not work: U-Boot never starts receiving. With the FTDI driver's default 16 ms latency timer every block waits for its acknowledgement, which halves the speed; `flash` sets the 1 ms timer for the transfer (no root needed). The serial-share broker restores both settings when `flash` finishes, even if it is interrupted.

## Shared consoles

Linux gives each byte that arrives on a serial port to **only one** reader. With `picocom` open on the U-Boot console while a script reads it too, each of them sees part of the output: the console looks frozen or garbled, and the script misses what it waits for.

So every console the tools open goes through a small **broker** (`scripts/polarfire/serial_share.py`) that owns the port and copies everything the board prints to every connected client; anything a client types goes to the board. A teammate in a terminal, `flash`, and an AI agent driving U-Boot can all use the same console at once and see the same output. **Verified on the board:** a shared console open during a network flash saw the same 118-test run (2026-10-25), and one open during a USB flash saw the whole run including the 1.5 Mbaud transfer (2026-10-26).

```bash
scripts/board.py console            # U-Boot / Linux / seL4 (interface 2)
scripts/board.py console --hss      # HSS firmware (interface 1), ">>" prompt
scripts/board.py console --uart3    # third UART (interface 3)
```

Exit with `Ctrl-a Ctrl-x`; `Ctrl-a Ctrl-a` sends a literal `Ctrl-a`.

- Open as many as you like, in tmux or several SSH sessions. Leave one open and run `flash` in another terminal to watch a whole flash; it stays open afterwards. It goes quiet while an image is sent over USB.
- **Don't type while `flash` is driving the board.** Your keys go to the board too, in the middle of its commands or transfer.
- **Don't open the ports with plain `picocom`, `screen` or `minicom`.** They don't share. `flash` refuses to start while one is open, and `status` and `ports` show who holds each port.

### For scripts and AI agents

Anything that reads or writes a board console should go through the broker, never open `/dev/ttyUSB*` or `/dev/polarfire-*` directly.

| Need | Use |
|---|---|
| Is anyone using the board? | `scripts/board.py status` (`shared console open`, `held by:` per port) |
| Send a line or a key | `scripts/board.py send 'version\r'` (`\r` is Enter; `--hss` for HSS). Goes through the broker if one is running, else straight to the port. |
| Reset the board | `scripts/board.py reset -y` |
| Load and boot an image | `scripts/board.py flash [image] --expect 'REGEX'`: exit code 0 on pass |
| Read output and react to it | Python, with `scripts/` on `sys.path`: `from polarfire import serial_share`; `s = serial_share.ensure_broker(port)` is a connected socket: `s.recv()` returns what the board prints, `s.sendall()` types. `polarfire.uboot.Console` adds prompt handling on top. |

Use the port names, never `ttyUSB` numbers. Never run `saveenv` and never write the SD card.

### How the broker works

- It starts when the first client connects (`ensure_broker`) and exits about 3 s after the last one leaves, or at once if the board is unplugged. One broker per port: its socket is `$XDG_RUNTIME_DIR/serial-share/<ttyUSBn>.sock`, with its PID in `<ttyUSBn>.sock.pid`. It is keyed on the real device, so `/dev/polarfire-uboot` and its `/dev/serial/by-id/` alias find the same broker. A socket left by a broker that died is replaced.
- Input from clients is queued and written to the port in order, so a 1 KiB YMODEM block is never cut short. A client that stops reading is dropped after 1 MiB of unread output, so it can't stall the others.
- A script that needs other port settings for a while takes the **control socket** (`<ttyUSBn>.ctl`), one holder at a time (a second gets `err busy`): `baud <rate>` changes the speed after earlier input has been written; `lowlat 1|0` turns the FTDI 1 ms latency timer on or off. **When the holder disconnects, for any reason, including a crash or Ctrl-C, the broker restores the settings it found**, so consoles never stay at the wrong speed. On a port without the FTDI latency setting, `lowlat` reports an error and the broker keeps running.

## Network boot

The same flow over Ethernet: `scripts/board.py flash --lan [image]`. It needs an Ethernet cable from connector **#2** to the same network as your computer (a home or lab router with DHCP), Docker, and the firewall rule below. Verified with the board on an ordinary home router: the DHCP lease took about 20–600 ms and the 3 MB image transferred in a few seconds.

### What the board's U-Boot supports

Checked at `RISC-V #` on U-Boot `2025.07-linux4microchip-2026.04`:

| Item | Result |
|---|---|
| Network device | `eth0 : ethernet@20110000` (Ethernet connector **#2**), link up at 1000 Mbps full-duplex |
| Commands | `dhcp`, `ping`, `tftpboot`. There is **no `wget`**: U-Boot can only download from a TFTP server on your network. |
| Saved environment | `ipaddr`, `serverip`, `gatewayip` are not set. `dhcp` sets the first three for the session; `serverip` stays unset, so the server address is given in `tftpboot`. |

### 1. The TFTP server

dnsmasq in TFTP-only mode (no DNS, no DHCP), in Docker with host networking, so it needs no `sudo` (the `docker` group is enough). `flash --lan` starts it when needed; by hand:

```bash
scripts/board.py tftp start       # or stop, status, logs (same as tftp/serve.sh)
```

It serves `tftp/root/` (git-ignored), listens only on the interface of your default route (`IFACE=<name>` chooses another), and prints your computer's address and ready-to-paste U-Boot commands for each staged image. It does not survive a reboot of your computer; `flash --lan` restarts it.

### 2. Allow TFTP through the firewall

On Linux Mint and Ubuntu, `ufw` is usually active and **drops the board's requests**: the board shows `Loading: *T T T T` and the host's kernel log shows `[UFW BLOCK] ... DPT=69`. Allow inbound UDP port 69 from your local network only (once; asks for your password):

```bash
IFACE=$(ip route show default | awk '{print $5; exit}')
SUBNET=$(ip -4 route show dev "$IFACE" scope link | awk '{print $1; exit}')
echo "interface=$IFACE subnet=$SUBNET"
sudo ufw allow in on "$IFACE" from "$SUBNET" to any port 69 proto udp comment 'sel4 tftp'
```

The echo should show something like `interface=wlo1 subnet=192.168.1.0/24`. If either is empty, find them with `ip -4 -br addr` and set them by hand. Only port 69 is needed: every later packet of a transfer is a reply to a flow your computer started. `flash --lan` prints a reminder when `ufw` is active.

## Manual procedures

`flash` automates these; they are the reference, and work from any terminal on any OS.

**Get to `RISC-V #`:** press a key while U-Boot prints `Hit any key to stop autoboot` (2 s).

**Over USB:** any terminal that can send a file with **YMODEM** works.

```text
loady 0x8e000000
```

U-Boot prints `## Ready for binary (ymodem) download to 0x8E000000 at 115200 bps...` and a `C` every few seconds. Send the image with YMODEM now:

- **Linux, picocom:** install `lrzsz`, start `picocom -b 115200 --send-cmd 'sb -vv' /dev/polarfire-uboot`, press `Ctrl-a Ctrl-s` and type the image path.
- **Windows, Tera Term:** *File → Transfer → YMODEM → Send*, then pick the image.

At 115200 this takes about 5 minutes for the 3 MB image. `loady 0x8e000000 1500000` is faster: U-Boot asks you to switch your terminal to 1500000 baud and press Enter, and afterwards to switch back to 115200 and press Esc. The picocom and Tera Term steps have **not** been tried on the board; the `loady` commands were verified through the script.

**Over the network:** with the server running and the firewall rule in place, paste **one line at a time** (U-Boot can drop characters that arrive while `dhcp` is still running), using your computer's address:

```text
setenv autoload no
dhcp
tftpboot 0x8e000000 192.168.1.10:sel4test.uImage
```

`setenv autoload no` stops `dhcp` from also trying to download a boot file named by the DHCP server; it is a RAM-only setting. Expect `DHCP client bound to address ...`, then `Bytes transferred = ...`.

**Then, either way, check and boot:**

```text
crc32 0x8e000000 ${filesize}
iminfo 0x8e000000
bootm 0x8e000000 - ${fdtcontroladdr}
```

- Compare `crc32` with the file's CRC-32 on your computer: `python3 -c "import zlib,sys;print(hex(zlib.crc32(open(sys.argv[1],'rb').read())))" images/sel4test.uImage` (`0xeb98aed0` for sel4test). `loady` sets `filesize` but **not** `fileaddr`, so give the address explicitly.
- `iminfo` must end with `Verifying Checksum ... OK`.
- `${fdtcontroladdr}` is U-Boot's own device tree ([why](sd-card.md#manual-boot-from-the-u-boot-prompt)). Never leave out the FDT argument.

A verified network session, for comparison (addresses replaced with examples: board `192.168.1.20`, computer `192.168.1.10`):

```text
RISC-V # dhcp
ethernet@20110000: link up, 1000Mbps full-duplex (lpa: 0x3800)
DHCP client bound to address 192.168.1.20 (567 ms)
RISC-V # tftpboot 0x8e000000 192.168.1.10:rust.uImage
TFTP from server 192.168.1.10; our IP address is 192.168.1.20
Filename 'rust.uImage'.
Load address: 0x8e000000
Loading: *#############
	 846.7 KiB/s
done
Bytes transferred = 177016 (2b378 hex)
RISC-V # bootm 0x8e000000 - 0xbf333da0
    ## Booting kernel from Legacy Image at 8e000000 ...
   Verifying Checksum ... OK
Starting kernel ...
...
Hello from Rust on seL4!
```

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `... is open in a program that doesn't share it: <pid>(picocom)` | A plain terminal holds the port. Close it (picocom: `Ctrl-a Ctrl-x`) and use `scripts/board.py console`. |
| Console output has gaps, or looks frozen mid-boot | Same cause: a non-sharing program has the port open as well. `scripts/board.py ports` names it. |
| `uboot serial port ... not found` | USB-C #1 unplugged, board off, or not all four channels bound: `scripts/board.py status`, then `install-udev`. |
| `no read/write access to ...` | Add yourself to the `dialout` group and log in again. |
| `U-Boot's autoboot prompt didn't appear` | HSS didn't reset or hand over. `scripts/board.py console --hss`: Enter should give `>>`. Power-cycle if not. |
| `the serial (YMODEM) transfer failed` | Something typed on the console during the transfer, or a poor cable. Retry with `--baud 921600`, or `115200`. |
| `## Binary (ymodem) download aborted` after `Timed out` (manual) | The terminal didn't send YMODEM's closing empty header. Use a YMODEM sender (`sb`), not XMODEM (`sx`). |
| `crc32 - checksum calculation` usage text instead of a CRC (manual) | `${fileaddr}` is empty after `loady`. Use `crc32 0x8e000000 ${filesize}`. |
| Garbage on the console after an interrupted flash | U-Boot is still waiting in `loady` at 1.5 Mbaud. `scripts/board.py flash` or `reset` resets it. |
| `err busy` / `can't take the serial port's control socket` | Two flashes at once. Wait for the other one to finish. |
| `Loading: *T T T` and nothing in `scripts/board.py tftp logs` | Firewall drop: [step 2](#2-allow-tftp-through-the-firewall). Check `journalctl -k \| grep 'UFW BLOCK'`. |
| `tftp logs` shows `failed to send packet: Network is unreachable` | dnsmasq started with `--tftp-single-port`. Use the shipped `tftp/Dockerfile`, which leaves it out, and rebuild its image (`docker rmi sel4-tftp`, then `scripts/board.py tftp start`). |
| `BOOTP broadcast` repeats with no lease / `no DHCP lease` | No DHCP server on the Ethernet port's network, or the cable is in the wrong connector (use **#2**). |
| `Wrong Image Type for bootm command` (manual) | The board was reset after loading, so RAM no longer holds the image. Load it again. |
