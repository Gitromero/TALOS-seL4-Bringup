# Sharing the serial ports (people, scripts and AI agents)

The board's consoles are ordinary serial ports, and Linux gives each byte that arrives on a serial port to **only one** reader. Open the U-Boot console in `picocom` while a script reads it too, and each of them sees only part of the output: the console looks frozen or garbled, and the script misses the lines it waits for.

[`scripts/serial-share.py`](../scripts/serial-share.py) fixes that. A small background **broker** owns the port and copies everything the board prints to every connected client. Anything a client types goes to the board. So a teammate in a terminal, `pf flash`, and an AI coding agent driving U-Boot can all use the same console at once, and all see the same output.

**Verified on the Discovery Kit:** a shared console open during `network-flash.sh` saw the same 118-test run as the script (2026-10-25). A shared watcher during `pf flash` over USB saw the whole run, including the 1.5 Mbaud transfer (2026-10-26).

## For people

```bash
scripts/pf console     # U-Boot / Linux / seL4 console (interface 2)
scripts/pf hss         # HSS firmware console (interface 1), ">>" prompt
```

Exit with `Ctrl-a Ctrl-x`. `Ctrl-a Ctrl-a` sends a literal `Ctrl-a`. Settings are 115200 8N1.

- Open as many as you like, in tmux or in several SSH sessions. They all show the same output.
- Leave `pf console` open and run `pf flash` in another terminal to watch a whole flash live. The console stays open afterwards.
- **Don't type while a script is driving the board.** Your keys go to the board too, in the middle of the script's commands or transfer.
- **Don't open the ports with plain `picocom`, `screen` or `minicom`.** They don't share, so they take output the other tools need. `pf flash` refuses to start while one is open, and `scripts/pf status` shows who holds each port.

`scripts/serial-share.py console <port>` is the same thing for any port, e.g. `/dev/polarfire-uart3`.

## For scripts and AI agents

Anything that reads or writes a board console should go through the broker, never open `/dev/ttyUSB*` or `/dev/polarfire-*` directly. Then a person can watch, and the script doesn't take bytes from anyone else.

| Need | Use |
|---|---|
| Send a line or a key | `scripts/serial-share.py send /dev/polarfire-uboot 'version\r'` (`\r` is Enter). Goes through the broker if one is running, else straight to the port. |
| Read output and react to it | Python: load `scripts/serial-share.py` with `importlib`, then `s = ensure_broker(port)` gives a connected Unix socket. `s.recv()` returns what the board prints, `s.sendall()` types. |
| Reset the board | `scripts/pf reset -y` (sends `RESET` to HSS, through a shared HSS console if one is open) |
| Load and boot an image | `scripts/pf flash [image] --expect 'REGEX'`: exit code 0 on pass. See [FLASHING.md](FLASHING.md). |
| Is anyone using the board? | `scripts/pf status`: `shared console open` and `held by:` per port |

`scripts/usb-flash.sh` and `scripts/network-flash.sh` are complete examples: they use `ensure_broker`, type one character every 8 ms (U-Boot drops characters that arrive faster), and wait for the `RISC-V #` prompt after each command.

Rules for agents (also in [CLAUDE.md](../CLAUDE.md)): use the port names, never `ttyUSB` numbers. Check `pf status` before resetting or flashing, since someone may be using the board. Never run `saveenv` and never write the SD card.

## How it works

- The broker starts the first time a client connects (`ensure_broker`). It exits about 3 s after the last client leaves, or at once if the board is unplugged.
- One broker per port. Its socket is `$XDG_RUNTIME_DIR/serial-share/<ttyUSBn>.sock`, with the broker's PID in `<ttyUSBn>.sock.pid`. It is keyed on the real device, so `/dev/polarfire-uboot` and its `/dev/serial/by-id/` alias find the same broker.
- `scripts/serial-share.py sock <port>` prints the socket path and PID if a broker is running. The flash scripts and `pf status` use the PID to tell the broker apart from programs that don't share.
- Input from clients is queued and written to the port in order, so a 1 KiB YMODEM block is never cut short.
- A client that stops reading is dropped after 1 MiB of unread output, so it can't stall the others.

### Changing the port settings

A script may need different port settings for a while: `pf flash` sends the image at 1.5 Mbaud, then returns to 115200. It does this through the broker's **control socket** (`<ttyUSBn>.ctl`), so the other clients stay connected:

| Command | Effect |
|---|---|
| `baud <rate>` | Change the port's baud rate (e.g. `baud 1500000`). Runs after earlier input has been written. |
| `lowlat 1` / `lowlat 0` | FTDI 1 ms latency timer on/off (the default is 16 ms). No root needed. |

From Python, `c = control(port)` connects, `c.cmd("baud 1500000")` returns on `ok` and raises `OSError` otherwise. Only one program can hold the control socket at a time; a second one gets `err busy`. **When the holder disconnects, for any reason, including a crash or Ctrl-C, the broker restores the settings it found**, so the consoles never stay at the wrong speed. While the speed is changed, consoles still receive whatever the board sends. During a YMODEM transfer that is only a few control bytes, so they stay quiet.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Console output has gaps, or looks frozen mid-boot | A non-sharing program has the port open as well. `scripts/pf status` names it. Close it. |
| `... is open in another program: <pid>(picocom)` from `pf flash` | Same: close that program (picocom: `Ctrl-a Ctrl-x`) and use `scripts/pf console`. |
| `serial-share: could not start a broker` | The port is missing or not readable: check `scripts/pf status`, and that you are in the `dialout` group. |
| `err busy` | Another flash holds the control socket. Wait for it to finish. |
