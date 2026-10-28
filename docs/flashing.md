# Loading images onto the board (USB or network)

Boot a freshly built image straight from your computer, with no SD card swaps. U-Boot copies the image into RAM and boots it with the same `bootm` command as the manual SD boot. Nothing is written to the SD card or to U-Boot's saved environment, so a power cycle boots whatever is on the card again.

There are two ways to get the image into RAM:

| | **USB (default)** | Network (TFTP) |
|---|---|---|
| Command | `scripts/pf flash [image]` | `scripts/pf flash --lan [image]` |
| Cables | USB-C **#1** only | USB-C **#1** + Ethernet **#2** on your router |
| Host setup | none beyond the [serial ports](SETUP.md#serial-console-on-a-linux-host) | Docker, plus one firewall rule |
| 3 MB sel4test image | about 25 s | a few seconds |
| How | U-Boot `loady` (YMODEM) over the U-Boot serial port | U-Boot `dhcp` + `tftpboot` |

Use **USB** unless the image is large or you load it many times an hour: it works anywhere the board is plugged in. Both commands work over SSH, reset the board themselves, check the image's CRC-32 on the board, boot it and report pass/fail. Both are **verified on the Discovery Kit** (USB on 2026-10-26, network on 2026-10-25): `Test suite passed. 118 tests passed. 49 tests disabled.`

`pf flash` and `pf flash --lan` reboot the board: whatever runs on it is lost. Run `scripts/pf status` first if someone else might be using it.

## 1. USB

### One command

From the repository root, on the computer the board's USB-C **#1** is plugged into:

```bash
scripts/pf flash                                    # images/sel4test.uImage
scripts/pf flash rust-root-task/build/images/rust-hello.uImage --expect 'Hello from Rust on seL4!'
scripts/pf flash my.uImage --console                # boot, then stay attached to the seL4 console
```

`scripts/pf flash` runs [`scripts/usb-flash.sh`](../scripts/usb-flash.sh), which you can also call directly. What it does, stopping with a clear message at the first problem:

1. Checks the file is a uImage or FIT, and that a legacy uImage's load address doesn't overlap the `0x8e000000` staging address.
2. Talks to the serial ports through the [shared console](SHARED_CONSOLE.md), and refuses to start if a program that doesn't share, such as a plain `picocom`, has a port open.
3. Sends `RESET` to the HSS console, then stops U-Boot's autoboot. With `--no-reset`, it uses the `RISC-V #` prompt if it is already there, or waits for you to reset the board.
4. Runs `loady 0x8e000000 1500000`, switches the port to 1.5 Mbaud and sends the image with YMODEM (1 KiB blocks, each with a CRC-16). The console goes back to 115200 afterwards. One retry if the transfer fails.
5. Runs `crc32` (compared with the file's CRC-32), `iminfo` and `bootm`.
6. Watches the console. For an image that contains sel4test, success is the `Test suite passed` line. Otherwise give `--expect REGEX`, or it finishes after `--idle` seconds (20) with no output. `Test suite failed`, `Kernel panic` and `--fail REGEX` count as failures.

Everything is shown live and saved to `logs/usb-flash-<time>.log` (git-ignored). Exit codes: `0` passed or booted, `1` the image reported a failure, `2` host setup problem, `3` board or U-Boot problem (no prompt, transfer or checksum failure), `4` timed out. `scripts/usb-flash.sh --help` lists every option.

To watch, open `scripts/pf console` in another terminal before or during the flash. It shows the reset, U-Boot, every command the script types and the whole test run, and stays open afterwards. It goes quiet while the image is being sent. **Don't type in it until the result appears**: your keys would go into the transfer.

### Speed

Measured on the board on 2026-10-26 with `images/sel4test.uImage` (3,021,688 bytes), each run ending in `118 tests passed`:

| `--baud` | Transfer time |
|---|---|
| `1500000` (default) | 23.6 s |
| `921600` | 35.4 s |
| `115200` | 268 s |

Faster rates don't work: at 3 Mbaud U-Boot never starts receiving. The script also turns on the FTDI driver's 1 ms latency mode for the transfer (no root needed), because with the default 16 ms every block waits for its acknowledgement and the transfer is half as fast. The [shared console](SHARED_CONSOLE.md#changing-the-port-settings) restores both settings when the script finishes, even if it is interrupted.

### By hand

Any terminal program that can send a file with **YMODEM** works. Get to `RISC-V #` (press a key during `Hit any key to stop autoboot`), then:

```text
loady 0x8e000000
```

U-Boot prints `## Ready for binary (ymodem) download to 0x8E000000 at 115200 bps...` and a `C` every few seconds. Send the image file with YMODEM from your terminal now:

- **Linux, picocom:** install `lrzsz` and start picocom with `picocom -b 115200 --send-cmd 'sb -vv' /dev/polarfire-uboot`. Press `Ctrl-a Ctrl-s` and type the path of the image.
- **Windows, Tera Term:** *File → Transfer → YMODEM → Send*, then pick the image.

At 115200 this takes about 5 minutes for the 3 MB sel4test image. When U-Boot prints `## Total Size = ... Bytes`, check and boot:

```text
crc32 0x8e000000 ${filesize}
iminfo 0x8e000000
bootm 0x8e000000 - ${fdtcontroladdr}
```

- `loady` sets `filesize` but **not** `fileaddr`, so give the address explicitly in `crc32`. Compare the result with the file's CRC-32 on your computer: `python3 -c "import zlib,sys;print(hex(zlib.crc32(open(sys.argv[1],'rb').read())))" images/sel4test.uImage` (`0xeb98aed0` for sel4test).
- `iminfo` must end with `Verifying Checksum ... OK`.
- Faster: `loady 0x8e000000 1500000` makes U-Boot ask you to switch your terminal to 1500000 baud and press Enter. After the transfer it asks you to switch back to 115200 and press Esc.

The `loady` commands and the speeds above were verified on the board through the script. The picocom and Tera Term steps have **not** been tried on the board yet.

### Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `USB (YMODEM) transfer failed` | Something else typed on the console during the transfer, or a poor cable. Retry with `--baud 921600`, or `115200`. |
| `## Binary (ymodem) download aborted` after `Timed out` (manual) | The terminal didn't send YMODEM's closing empty header. Use a YMODEM sender (`sb`), not XMODEM (`sx`). |
| `crc32 - checksum calculation` usage text instead of a CRC | `${fileaddr}` is empty after `loady`. Use `crc32 0x8e000000 ${filesize}`. |
| The console shows garbage after an interrupted flash | U-Boot is still waiting in `loady` at 1.5 Mbaud. `scripts/pf flash` (or `pf reset`) resets it. |
| `... is open in another program` | A plain `picocom`/`screen` holds the port. Close it and use `scripts/pf console` ([why](SHARED_CONSOLE.md)). |
| `err busy` from the control socket | Two flashes at once. Wait for the other one to finish. |

## 2. Network (TFTP)

The same flow, with the image downloaded over Ethernet instead. It is faster for large images, but needs an Ethernet cable from connector **#2** to your router, Docker on your computer and one firewall rule ([setup](NETBOOT.md#2-start-the-tftp-server-on-your-computer)).

```bash
scripts/pf flash --lan                              # images/sel4test.uImage
scripts/pf flash --lan my.uImage --expect 'REGEX'   # same options as above, plus --server-ip
```

`scripts/pf flash --lan` runs [`scripts/network-flash.sh`](../scripts/network-flash.sh) and logs to `logs/network-flash-<time>.log`. Everything else (options, exit codes, watching with `pf console`) is the same as for USB. The TFTP server, firewall, the manual `dhcp`/`tftpboot` procedure and network troubleshooting are in **[NETBOOT.md](NETBOOT.md)**.
