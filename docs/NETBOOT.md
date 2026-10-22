# Network boot from U-Boot (TFTP)

Boot a freshly built image straight from your computer, with no SD card swaps. U-Boot gets an IP address by DHCP, downloads the image over TFTP into RAM, and boots it with the same `bootm` command as the manual SD boot. **Verified on the Discovery Kit on 2026-10-21** with the [Rust root task](../rust-root-task/README.md). Nothing is written to the SD card or to U-Boot's saved environment.

## What the board's U-Boot supports

Checked at `RISC-V #` on U-Boot `2025.07-linux4microchip-2026.04`:

| Item | Result |
|---|---|
| Network device | `eth0 : ethernet@20110000` (Ethernet connector **#2**), link up at 1000 Mbps full-duplex |
| Commands | `dhcp`, `ping`, `tftpboot` are present. There is **no `wget`**: U-Boot can't download from the internet, only from a TFTP server on your network. |
| Saved environment | `ipaddr`, `serverip`, `gatewayip` are not set. `dhcp` sets the first three for the session; `serverip` stays unset, so give the server address explicitly in `tftpboot`. |
| Transfer speed | 350–850 KiB/s from a laptop on Wi-Fi (a 173 KiB image takes well under a second) |

## 1. Start the TFTP server on your computer

The server is dnsmasq in TFTP-only mode, in Docker, so it needs no `sudo` (being in the `docker` group is enough). From the repository root:

```bash
tftp/serve.sh start        # also: stop, status, logs
```

It serves the files in `tftp/root/` and prints the address to use, e.g. `TFTP serving .../tftp/root on wlo1 (192.168.1.10)`. It listens only on the interface of your default route; set `IFACE=<name>` to choose another. The server does not survive a reboot of your computer: run `start` again.

Copy the images you want to boot into `tftp/root/`, for example:

```bash
cp rust-root-task/build/images/rust-hello.uImage tftp/root/rust.uImage
cp images/sel4test.uImage tftp/root/sel4test.uImage
```

`tftp/root/` is git-ignored.

## 2. Allow TFTP through your computer's firewall

On Linux Mint and Ubuntu, `ufw` is usually active and **drops the board's requests**. The symptom on the board is `Loading: *T T T T` (timeouts), and the host's kernel log shows lines like `[UFW BLOCK] IN=wlo1 ... SRC=<board IP> DST=<your IP> ... PROTO=UDP ... DPT=69`. Allow inbound UDP port 69 from your local network only (once; needs your password):

```bash
sudo ufw allow in on <iface> from <your-subnet> to any port 69 proto udp comment 'sel4 tftp'
```

For example, `<iface>` = `wlo1` and `<your-subnet>` = `192.168.1.0/24`.

`ip -4 -br addr` shows your interface and address; the subnet is the network part, e.g. `192.168.1.10/24` → `192.168.1.0/24`. Only port 69 is needed: every later packet of a transfer is a reply to a flow your computer started, which the firewall allows.

## 3. Boot from the U-Boot prompt

The board and your computer must be on the same network (the board's Ethernet and your Wi-Fi can be on the same router). Get to `RISC-V #` by pressing a key during `Hit any key to stop autoboot`, then:

```text
setenv autoload no
dhcp
tftpboot 0x8e000000 <your-computer-IP>:rust.uImage
iminfo 0x8e000000                     # Verifying Checksum ... OK
bdinfo                                # note fdt_blob
bootm 0x8e000000 - <fdt_blob>
```

- `setenv autoload no` stops `dhcp` from also trying to download a boot file named by the DHCP server. It is a RAM-only setting: never run `saveenv`.
- Expect `DHCP client bound to address ...`, then `Bytes transferred = ...` and `done`.
- `<fdt_blob>` is the address `bdinfo` prints (`0xbf333da0` on our board in every session so far). It must be a real address: typing the placeholder literally fails.
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

Anything that reads the U-Boot serial port competes with your terminal for its output: Linux gives each incoming byte to only one reader. If a script sends commands while `picocom` is open, either have the script only **write** to the port and watch the output in `picocom`, or close `picocom` first.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Loading: *T T T` and nothing in `tftp/serve.sh logs` | Firewall drop: see step 2. Check `journalctl -k \| grep 'UFW BLOCK'`. |
| `serve.sh logs` shows `failed to send packet: Network is unreachable` | dnsmasq started with `--tftp-single-port`. Use the shipped `tftp/Dockerfile`, which leaves it out, and rebuild the image (`docker rmi sel4-tftp`, then `serve.sh start`). |
| `Wrong Image Type for bootm command` | The board was reset after `tftpboot`, so RAM no longer holds the image. Repeat `dhcp` and `tftpboot`. |
| Your computer's IP changed | Your router assigns it. `serve.sh start` prints the current one. |
| `BOOTP broadcast` repeats with no lease | No DHCP server on the Ethernet port's network, or the cable is in the wrong connector (use **#2**). |
