# Network boot from U-Boot (TFTP)

> **USB is the default way to load images** (`scripts/pf flash`, USB-C cable only): see [FLASHING.md](FLASHING.md). This page is the network alternative, `scripts/pf flash --lan`: faster for large images, but it needs Ethernet, Docker and a firewall rule.

Boot a freshly built image straight from your computer over Ethernet. U-Boot gets an IP address by DHCP, downloads the image over TFTP into RAM, and boots it with the same `bootm` command as the manual SD boot. **Verified on the Discovery Kit on 2026-10-21** with the [Rust root task](../rust-root-task/README.md). Nothing is written to the SD card or to U-Boot's saved environment.

## One command: `scripts/network-flash.sh`

Steps 1–4 below, plus the board reset, done by a script (`scripts/pf flash --lan` runs it too, defaulting to `images/sel4test.uImage`). Run it from the repository root on the computer the board's USB-C **#1** is plugged into (over SSH is fine):

```bash
scripts/network-flash.sh images/sel4test.uImage
scripts/network-flash.sh rust-root-task/build/images/rust-hello.uImage --expect 'Hello from Rust on seL4!'
scripts/network-flash.sh my.uImage --console      # boot, then stay attached to the seL4 console
```

What it does, stopping with a clear message at the first problem:

1. Checks the file is a uImage or FIT, and that a legacy uImage's load address doesn't overlap the `0x8e000000` staging address.
2. Copies it into `tftp/root/`, starts the TFTP server if it isn't running, and fetches the first block from the server itself, so a broken server is caught before the board is touched.
3. Talks to the serial ports through the [shared console](SHARED_CONSOLE.md). Refuses to start if a program that doesn't share, such as a plain `picocom`, has a port open, since it would take the output the script waits for.
4. Sends `RESET` to the HSS console, waits for `Hit any key to stop autoboot` on the U-Boot console and stops it. With `--no-reset`, it uses the `RISC-V #` prompt if it is already there, or waits for you to reset the board.
5. Runs `setenv autoload no`, `dhcp` (3 tries), `tftpboot` (2 tries, checking the byte count), `crc32` (compared with the file's CRC-32), `iminfo` and `bootm`, typing slowly enough that U-Boot keeps every character.
6. Watches the console. For an image that contains sel4test, success is the `Test suite passed` line. Otherwise give `--expect REGEX`, or it finishes after `--idle` seconds (20) with no output. `Test suite failed`, `Kernel panic` and `--fail REGEX` count as failures.

Everything is shown live and saved to `logs/network-flash-<time>.log` (git-ignored). Exit codes: `0` passed or booted, `1` the image reported a failure, `2` host setup problem, `3` board or U-Boot problem (no prompt, no DHCP lease, TFTP or checksum failure), `4` timed out. `scripts/network-flash.sh --help` lists every option.

### Watching while it flashes

Open `scripts/pf console` in another terminal (or SSH session) before or during the flash. It shows the reset, U-Boot, every command the script types and the whole test run, and stays open afterwards. **Don't type in it while the script is driving U-Boot.** How the sharing works, and how scripts and AI agents use it: [SHARED_CONSOLE.md](SHARED_CONSOLE.md).

Like the manual steps, it only uses RAM: no `saveenv`, nothing written to the SD card. Serial ports are found as `/dev/polarfire-uboot` and `/dev/polarfire-hss` ([udev rule](SETUP.md#stable-port-names)), then under `/dev/serial/by-id/`; `UBOOT_PORT` and `HSS_PORT` override both. **Verified on the Discovery Kit on 2026-10-25:** `PASSED: Test suite passed. 118 tests passed. 49 tests disabled.` from a single command, over SSH.

## What the board's U-Boot supports

Checked at `RISC-V #` on U-Boot `2025.07-linux4microchip-2026.04`:

| Item | Result |
|---|---|
| Network device | `eth0 : ethernet@20110000` (Ethernet connector **#2**), link up at 1000 Mbps full-duplex |
| Commands | `dhcp`, `ping`, `tftpboot` are present. There is **no `wget`**: U-Boot can't download from the internet, only from a TFTP server on your network. |
| Saved environment | `ipaddr`, `serverip`, `gatewayip` are not set. `dhcp` sets the first three for the session; `serverip` stays unset, so give the server address explicitly in `tftpboot`. |
| Transfer speed | 350–850 KiB/s from a laptop on Wi-Fi (a 173 KiB image takes well under a second) |

## 1. Put the images in `tftp/root/`

From the repository root, copy in the images you want to boot. The prebuilt sel4test image is always there:

```bash
cp images/sel4test.uImage tftp/root/sel4test.uImage
```

The [Rust root task](../rust-root-task/README.md), once you have built it:

```bash
cp rust-root-task/build/images/rust-hello.uImage tftp/root/rust.uImage
```

`tftp/root/` is git-ignored.

## 2. Start the TFTP server on your computer

The server is dnsmasq in TFTP-only mode, in Docker, so it needs no `sudo` (being in the `docker` group is enough). From the repository root:

```bash
tftp/serve.sh start
```

Other subcommands: `stop`, `status`, `logs`. It serves the files in `tftp/root/`, prints your computer's address (e.g. `TFTP serving .../tftp/root on wlo1 (192.168.1.10)`) and then, for each image, the exact U-Boot commands for step 4 with that address filled in. If you add images later, run `start` again to reprint them. It listens only on the interface of your default route; set `IFACE=<name>` to choose another. The server does not survive a reboot of your computer: run `start` again.

## 3. Allow TFTP through your computer's firewall

On Linux Mint and Ubuntu, `ufw` is usually active and **drops the board's requests**. The symptom on the board is `Loading: *T T T T` (timeouts), and the host's kernel log shows lines like `[UFW BLOCK] IN=wlo1 ... SRC=<board IP> DST=<your IP> ... PROTO=UDP ... DPT=69`. Allow inbound UDP port 69 from your local network only (once; needs your password). This finds your default interface and its subnet, shows them, then adds the rule:

```bash
IFACE=$(ip route show default | awk '{print $5; exit}')
SUBNET=$(ip -4 route show dev "$IFACE" scope link | awk '{print $1; exit}')
echo "interface=$IFACE subnet=$SUBNET"
sudo ufw allow in on "$IFACE" from "$SUBNET" to any port 69 proto udp comment 'sel4 tftp'
```

The echo should show something like `interface=wlo1 subnet=192.168.1.0/24`. If either is empty, find them with `ip -4 -br addr` (the subnet is the network part of your address, e.g. `192.168.1.10/24` → `192.168.1.0/24`) and set them by hand. Only port 69 is needed: every later packet of a transfer is a reply to a flow your computer started, which the firewall allows.

## 4. Boot from the U-Boot prompt

The board and your computer must be on the same network (the board's Ethernet and your Wi-Fi can be on the same router). Get to `RISC-V #` by pressing a key during `Hit any key to stop autoboot`, then paste the commands `serve.sh start` printed, **one line at a time** (U-Boot can drop characters that arrive while a command such as `dhcp` is still running). They look like this, with your computer's address in the `tftpboot` line:

```text
setenv autoload no
dhcp
tftpboot 0x8e000000 192.168.1.10:rust.uImage
iminfo 0x8e000000
bootm 0x8e000000 - ${fdtcontroladdr}
```

- `setenv autoload no` stops `dhcp` from also trying to download a boot file named by the DHCP server. It is a RAM-only setting: never run `saveenv`.
- Expect `DHCP client bound to address ...`, then `Bytes transferred = ...` and `done`.
- `iminfo` must end with `Verifying Checksum ... OK`.
- `${fdtcontroladdr}` is U-Boot's own device tree address, the same value `bdinfo` prints as `fdt_blob` (`0xbf333da0` on our board in every session so far). The [autoboot script](../boot/README.md#what-boot-autoscr-does) uses it the same way. The verified session below typed the address read from `bdinfo` instead.
- To check a transfer bit-for-bit, compare U-Boot's `crc32 0x8e000000 ${filesize}` with the file's CRC-32 on your computer, e.g. `python3 -c "import zlib,sys;print(hex(zlib.crc32(open(sys.argv[1],'rb').read())))" tftp/root/rust.uImage`.

The verified session, for comparison (addresses replaced with examples: board `192.168.1.20`, computer `192.168.1.10`):

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

## Driving the console from a script

Go through the shared console instead of opening the port directly, so a person can watch and nothing steals the output: [SHARED_CONSOLE.md](SHARED_CONSOLE.md#for-scripts-and-ai-agents).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Loading: *T T T` and nothing in `tftp/serve.sh logs` | Firewall drop: see step 3. Check `journalctl -k \| grep 'UFW BLOCK'`. |
| `serve.sh logs` shows `failed to send packet: Network is unreachable` | dnsmasq started with `--tftp-single-port`. Use the shipped `tftp/Dockerfile`, which leaves it out, and rebuild the image (`docker rmi sel4-tftp`, then `serve.sh start`). |
| `Wrong Image Type for bootm command` | The board was reset after `tftpboot`, so RAM no longer holds the image. Repeat `dhcp` and `tftpboot`. |
| Your computer's IP changed | Your router assigns it. `serve.sh start` prints the current one. |
| `BOOTP broadcast` repeats with no lease | No DHCP server on the Ethernet port's network, or the cable is in the wrong connector (use **#2**). |
