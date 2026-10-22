# Troubleshooting

Each entry says whether the advice comes from **what we saw on the board** or is **general guidance we have not tested on this board**. Always save the full serial log of a failure. It is the most useful thing to share with the team.

Basics first: **115200 8N1**, no flow control, and the right port (see [SETUP.md](SETUP.md#serial-console)).

---

## No output on any port

- Check power and the USB-C cable on connector **#1**. It must be a data cable, not charge-only.
- Open all serial ports, then power-cycle. HSS prints first on its own port.
- On Linux, permission errors on `/dev/ttyUSB*` mean you need the `dialout` group.

## Only one serial port on Linux

Seen on the board: the kernel binds only one of the FT4232H's channels (interface 2, the U-Boot/seL4 console), so a single `/dev/ttyUSB0` appears. Fix: `sudo sh -c 'echo 1514 2008 > /sys/bus/usb-serial/drivers/ftdi_sio/new_id'`. Details: [SETUP.md](SETUP.md#serial-console-on-a-linux-host).

## Console looks frozen, or output has gaps

- **Two programs on one port.** Seen on the board: with `picocom` open on the U-Boot port while a script also read it, each got only part of the output. Close one. Writing to a port from a script while `picocom` reads it is fine.
- **seL4 is done.** After sel4test's summary, or after the Rust root task prints its lines, nothing on the board reads input. U-Boot is gone and seL4 has no shell. Reset the board.

## Linux boots instead of seL4

Either `boot.scr` is still the Linux script, or the autoboot script hit a failed check and fell back. Look for `TALOS:` lines just before Linux starts ([autoboot messages](#autoboot-messages)). Check the card on your host:

```bash
scripts/install-to-boot.sh "$BOOT" --verify
```

Common causes:

- The file was copied to the wrong drive or partition. It must be the FAT partition with `fitImage`.
- On Windows it was named `boot.scr.scr`, or `boot-auto.scr` was copied without renaming it to `boot.scr`.
- The card was pulled without ejecting, so the write never finished. Re-copy, `sync`/eject, and try again.

## Boot script not found / wrong FAT partition

U-Boot's distro boot looks for `boot.scr` on the card's bootable partition (official layout: `mmc 0:1`, the vfat `boot` partition), in `/` or `/boot/`. Put `boot.scr` and `sel4test.uImage` at the **top level** of that partition, next to `fitImage`. Not inside a folder, and not on the ext4 root partition.

## Autoboot messages

The autoboot script ([boot/README.md](../boot/README.md)) prints `TALOS:` lines that say which check failed. Every failure falls back to `boot-linux.scr`. These branches were exercised in QEMU; on the board only the success path has been seen so far.

| Message | Meaning and what to do |
|---|---|
| `TALOS: fdtcontroladdr is not set` / `no valid FDT at …` | U-Boot did not expose a usable control FDT. Report the U-Boot version and the `bdinfo` output from a manual session. |
| `TALOS: sel4test.uImage not found` | The image is missing from the FAT partition or has another name. |
| `TALOS: image range overlaps the FDT` | Firmware placed the FDT near `0x8e000000`. Report it, because the staging address would need to move. |
| `Bad Data CRC` → `TALOS: image check failed` | Corrupt copy. Recopy it and check the hash with `--verify`. |
| `Failed to reserve memory for fdt …` / `FDT creation failed! hanging...` | Seen only under QEMU before the script cleared `fdt_high`. If it appears on the board, reset, restore Linux, and report the full log. |
| `TALOS: boot-linux.scr returned without booting Linux` | Both seL4 and the Linux fallback failed. Restore from a host as below. |
| Output stops after `Starting kernel` | The image ran but did not complete. Save the log and report it with your firmware versions. |

There is no keypress escape once the script runs. To get back to Linux, use a host computer and `--restore-linux`.

## Getting to the `RISC-V #` prompt

Needed for manual boot, [network boot](NETBOOT.md) and the [Rust root task](../rust-root-task/README.md). Press a key while U-Boot shows `Hit any key to stop autoboot` (the board's `bootdelay` is 2 seconds). On the board, from `picocom` on Linux, this stopped U-Boot at `RISC-V #` before `boot.scr` ran. During the original bring-up on Windows, interrupting the countdown was not reliable, which is why the first scripts only staged the image.

- Check you're on the **U-Boot** port, not the HSS port.
- If HSS doesn't hand over to U-Boot, typing `sdcard` then `boot` on the **HSS** console worked during the original bring-up.

## `load` or `iminfo` fails

At `RISC-V #`:

```text
load mmc 0:1 0x8e000000 sel4test.uImage
iminfo 0x8e000000
```

| You see | Meaning and fix |
|---|---|
| `3021688 bytes read` | Correct size. |
| `** File not found sel4test.uImage **` | Wrong partition or name. `ls mmc 0:1` lists the FAT partition so you can check. |
| a different byte count | Wrong or corrupted file. Re-copy and check the SHA-256. |
| `Bad Magic Number` | Nothing valid is at `0x8e000000`. Run `load` again **before** `iminfo`. |
| `Bad Data CRC` / checksum not OK | Corrupt copy. Re-copy, verify the hash, eject properly. |

A good `iminfo` shows `Legacy image found`, `Image Type: RISC-V Linux Kernel Image (uncompressed)`, `Data Size: 3021624 Bytes`, `Load Address: 80640000`, `Entry Point: 80640000`, `Verifying Checksum ... OK`. The "Linux Kernel" label is expected: the seL4 elfloader is wrapped as a Linux-type image for U-Boot.

## Invalid or missing FDT

`bootm` needs a valid flattened device tree (FDT) for a RISC-V Linux-type image. Get **this session's** address:

```text
bdinfo                    # look for: fdt_blob = 0x........
fdt addr 0x........       # your value
fdt header                # must print  magic: 0xd00dfeed
```

- On our board `bdinfo` has shown `fdt_blob = 0xbf333da0` in every session so far (`fdt header`: `totalsize: 0x5065`, `version: 17`). It may differ between firmware releases or boards, so read it each time.
- `<fdt_blob>` in these docs is a placeholder. Typing it literally makes `bootm` fail.
- If `bdinfo` has no `fdt_blob` line, or `fdt header` reports an error or bad magic, **don't run `bootm`**. Save the log and ask the team.

## `bootm` errors

| You see | Meaning and fix |
|---|---|
| `Device tree not found or missing FDT support` then `### ERROR ### Please RESET the board ###` | Seen on the board: `bootm 0x8e000000` without the FDT argument. seL4 did not run. Reset, `load` again, and use `bootm 0x8e000000 - <fdt_blob>`. Mind the `-` in the middle. |
| `Wrong Image Type for bootm command` / `ERROR -91: can't get kernel image!` | Seen on the board: the board had been reset after the image was loaded, so RAM no longer held it. `load` (or `tftpboot`) again. |
| `Failed to reserve memory for fdt at …` / `FDT creation failed! hanging...` | U-Boot was told to use the FDT in place (`fdt_high` all ones) and refused. Reproduced under QEMU with U-Boot 2025.10, not seen on the board. Reset, then `setenv fdt_high` before `bootm` (session only). |

## seL4 starts but output stops or tests fail

- If `TALOS: root task reached seL4 user space` appears, the kernel and user space started. A hang after that is worth a full log.
- Some tests deliberately cause kernel error messages (`Attempted to invoke a null cap`, invalid vspace root, unavailable ASID pool, …) and still **pass**. Look at the final summary line.
- Expected summary: `Test suite passed. 118 tests passed. 49 tests disabled.` Any other count means a different image or behavior. Confirm the image hash on the card, and record HSS/U-Boot/FPGA/Linux image versions.

## U-Boot, HSS or FPGA version mismatch

What we verified is listed in [FIRMWARE_COMPATIBILITY.md](FIRMWARE_COMPATIBILITY.md): U-Boot `2025.07-linux4microchip-2026.04`, Linux4Microchip `2026.04.1`, reference design RTL `v2507`, HSS 0.99.53 (historical record). Avnet's guide installs the *latest* releases, which may differ.

- U-Boot prints its version at startup. HSS prints its version on the HSS console. Note both.
- Memory layout matters. The image runs at `0x80640000` and assumes seL4 can use `0x80000000–0x84000000` and `0x8a000000–0x92000000`, with the first 2 MiB reserved for firmware. A firmware release that reserves different memory, or a different `scriptaddr`, could break things.
- If the latest release fails, try the tested Linux4Microchip **2026.04.1** Discovery Kit image and the matching reference design from the official release pages, **following the official flashing instructions**. Exact tag names were not verified for this document. Don't flash unofficial firmware.

## Network boot

TFTP timeouts, firewall rules and server errors: [NETBOOT.md](NETBOOT.md#troubleshooting).

## Restore Linux boot

On the host, with the FAT boot partition mounted:

```bash
scripts/install-to-boot.sh "$BOOT" --restore-linux          # dry run
scripts/install-to-boot.sh "$BOOT" --restore-linux --apply  # boot.scr <- boot-linux.scr (staged, verified)
```

Or by hand:

```bash
cp "$BOOT/boot-linux.scr" "$BOOT/boot.scr" && sync
```

**If `boot-linux.scr` is missing**, for example because `boot.scr` was replaced without a backup:

1. Check the card's Linux version: on the ext4 `root` partition, `ls /lib/modules` shows a name like `6.18.17-linux4microchip-2026.04.1-…`.
2. If it is **2026.04.1**, this repository's [`boot/boot-linux.scr`](../boot/boot-linux.scr) is the script from that image (227-byte payload: loads `fitImage` and boots it). Copy it as **both** `boot-linux.scr` and `boot.scr`:
   ```bash
   cp boot/boot-linux.scr "$BOOT/boot-linux.scr" && cp boot/boot-linux.scr "$BOOT/boot.scr" && sync
   ```
3. For any other release, extract that release's `boot.scr` from its `.wic` image (mount its first partition on a host), or re-flash the official `.wic`. Re-flashing **erases the card**.
