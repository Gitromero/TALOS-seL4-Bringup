# Troubleshooting

Each entry says whether the advice comes from the **verified bring-up** or is **general guidance we have not tested on this board**. Always save the full serial log of a failure. It is the most useful thing to share with the team.

Basics first: **115200 8N1**, no flow control, and the right port (see [SETUP.md](SETUP.md#serial-console)).

---

## No output on any port

- Check power and the USB-C cable on connector **#1**. It must be a data cable, not charge-only.
- Open all three serial ports, then power-cycle. HSS prints first on its own port.
- On Linux, permission errors on `/dev/ttyUSB*` mean you need the `dialout` group (general guidance).

## Linux boots instead of the seL4 staging script

The card still has the Linux `boot.scr`. Check the card on your host:

```bash
sha256sum "$BOOT/boot.scr"     # must equal boot/boot-sel4.scr in images/SHA256SUMS
```

Common causes:

- The file was copied to the wrong drive or partition. It must be the FAT partition with `fitImage`.
- On Windows it was named `boot.scr.scr`, or `boot-sel4.scr` was copied without renaming it to `boot.scr`.
- The card was pulled without ejecting, so the write never finished. Re-copy, `sync`/eject, and try again.

## Boot script not found / wrong FAT partition

U-Boot's distro boot looks for `boot.scr` on the card's bootable partition (official layout: `mmc 0:1`, the vfat `boot` partition), in `/` or `/boot/`. Put `boot.scr` and `sel4.uImage` at the **top level** of that partition, next to `fitImage`. Not inside a folder, and not on the ext4 root partition.

## `ERROR: Could not load sel4.uImage` (from the script)

The staging script ran but could not read `sel4.uImage` from that partition. Check that the file is at the top level of the FAT `boot` partition and named exactly `sel4.uImage` (watch for `.txt` or `(1)` suffixes added by a browser or Windows). Copy it again from `images/`.

## `load` or `iminfo` fails

At `RISC-V #`:

```text
load mmc 0:1 0x8e000000 sel4.uImage
iminfo 0x8e000000
```

| You see | Meaning and fix |
|---|---|
| `3057528 bytes read` | Correct size (verified). |
| `** File not found sel4.uImage **` | Wrong partition or name. `ls mmc 0:1` lists the FAT partition so you can check. |
| a different byte count | Wrong or corrupted file. Re-copy and check the SHA-256. |
| `Bad Magic Number` | Nothing valid is at `0x8e000000`. Run `load` again **before** `iminfo`. |
| `Bad Data CRC` / checksum not OK | Corrupt copy. Re-copy, verify the hash, eject properly. |

A good `iminfo` shows `Legacy image found`, `Image Type: RISC-V Linux Kernel Image (uncompressed)`, `Data Size: 3057464 Bytes`, `Load Address: 80650000`, `Entry Point: 80650000`, `Verifying Checksum ... OK`. The "Linux Kernel" label is expected: the seL4 elfloader is wrapped as a Linux-type image for U-Boot.

Always **reload before booting**. U-Boot's later network-boot attempt uses the same memory region (`scriptaddr`), so don't trust a copy staged earlier without checking it. See [boot/README.md](../boot/README.md#why-a-risc-v--prompt-appears-eventually).

## Can't reach the `RISC-V #` prompt

- **Wait.** The prompt appeared after a delay in the verified setup. Based on the card's saved environment (not observed line by line), U-Boot tries EFI and then **network (DHCP)** boot after the staging script returns, so messages like `SCRIPT FAILED: continuing...` are likely and harmless.
- Check you're on the **U-Boot** port, not the HSS port.
- If HSS doesn't hand over to U-Boot, typing `sdcard` then `boot` on the **HSS** console worked during the original bring-up.
- Pressing a key during U-Boot's countdown was **not reliable** for us, so this procedure doesn't depend on it. If it works for you, that's a bonus. Run the same commands.
- Disconnecting Ethernet may shorten the network-boot wait (**untested**).
- If you never get a prompt, recheck that `boot.scr` is the hash-verified seL4 script. An untested "autoboot" script could hang or boot something else.

## Invalid or missing FDT

`bootm` needs a valid flattened device tree (FDT) for a RISC-V Linux-type image. Get **this session's** address:

```text
bdinfo                    # look for: fdt_blob = 0x........
fdt addr 0x........       # your value
fdt header                # must print  magic: 0xd00dfeed
```

- **Do not hardcode `0xbf333da0`.** It was correct for one verified session (`fdt header` then showed `totalsize: 0x5065`, `version: 17`). It may differ between boots, firmware releases or boards.
- If `bdinfo` has no `fdt_blob` line, or `fdt header` reports an error or bad magic, **don't run `bootm`**. Save the log and ask the team. Don't guess an address.
- `printenv fdtcontroladdr` should show the same address. In U-Boot v2025.07 source, both it and `bdinfo`'s `fdt_blob` are set from `gd->fdt_blob`. This **has not been observed on the board**, so use `bdinfo` (the verified method) and treat `fdtcontroladdr` as a cross-check.

## `bootm` without the third argument

```text
bootm 0x8e000000
...
Device tree not found or missing FDT support
### ERROR ### Please RESET the board ###
```

This is the verified first-attempt failure.

A different FDT failure, `Failed to reserve memory for fdt at …` followed by `FDT creation failed! hanging...`, means U-Boot was told to use the FDT in place (`fdt_high` set to all ones) and refused. This was reproduced under QEMU with U-Boot 2025.10; it was not seen on the tested board. Reset, then before `bootm` run `setenv fdt_high` (this unsets it for the session only).

Recovering from the missing-argument failure: seL4 did not run. **Reset the board**, wait for `RISC-V #`, then `load`, `iminfo`, `bdinfo`, `fdt addr`, `fdt header`, and `bootm 0x8e000000 - <FDT>`. Mind the `-` in the middle.

## seL4 starts but output stops or tests fail

- If `TALOS: root task reached seL4 user space` appears, the kernel and user space started. A hang after that is worth a full log.
- Some tests deliberately cause kernel error messages (invalid vspace root, unavailable ASID pool, …) and still **pass**. Look at the final summary line.
- Expected summary: `Test suite passed. 118 tests passed. 49 tests disabled.` Any other count means a different image or behavior. Confirm the image hash on the card, and record HSS/U-Boot/FPGA/Linux image versions.

## U-Boot, HSS or FPGA version mismatch

What we verified is listed in [FIRMWARE_COMPATIBILITY.md](FIRMWARE_COMPATIBILITY.md): U-Boot `2025.07-linux4microchip-2026.04`, Linux4Microchip `2026.04.1`, reference design RTL `v2507`, HSS 0.99.53 (historical record). Avnet's guide installs the *latest* releases, which may differ.

- U-Boot prints its version at startup. HSS prints its version on the HSS console. Note both.
- Memory layout matters. The image runs at `0x80650000` and assumes seL4 can use `0x80000000–0x84000000` and `0x8a000000–0x92000000`, with the first 2 MiB reserved for firmware. A firmware release that reserves different memory, or a different `scriptaddr`, could break things.
- If the latest release fails, try the tested Linux4Microchip **2026.04.1** Discovery Kit image and the matching reference design from the official release pages, **following the official flashing instructions**. Exact tag names were not verified for this document. Don't flash unofficial firmware.

## Restore Linux boot

On the host, with the FAT boot partition mounted:

```bash
scripts/install-to-boot.sh "$BOOT" --restore-linux          # dry run
scripts/install-to-boot.sh "$BOOT" --restore-linux --apply  # boot.scr <- boot-linux.scr (staged, verified)
# or by hand:
cp "$BOOT/boot-linux.scr" "$BOOT/boot.scr" && sync
```

**If `boot-linux.scr` is missing**, for example because `boot.scr` was replaced without a backup:

1. Check the card's Linux version: on the ext4 `root` partition, `ls /lib/modules` shows a name like `6.18.17-linux4microchip-2026.04.1-…`.
2. If it is **2026.04.1**, this repository's [`boot/boot-linux.scr`](../boot/boot-linux.scr) is the script from that image (227-byte payload: loads `fitImage` and boots it). Copy it as **both** `boot-linux.scr` and `boot.scr`:
   ```bash
   cp boot/boot-linux.scr "$BOOT/boot-linux.scr" && cp boot/boot-linux.scr "$BOOT/boot.scr" && sync
   ```
3. For any other release, extract that release's `boot.scr` from its `.wic` image (mount its first partition on a host), or re-flash the official `.wic`. Re-flashing **erases the card**.

## Experimental autoboot candidate

Applies only to cards installed with `--experimental` ([experimental/README.md](../experimental/README.md)). The script prints `TALOS:` lines that say which check failed:

| Message | Meaning and what to do |
|---|---|
| `TALOS: fdtcontroladdr is not set` / `no valid FDT at …` | U-Boot did not expose a usable control FDT. The script falls back to Linux. Report the U-Boot version and the `bdinfo` output from a manual session. |
| `TALOS: sel4-experimental.uImage not found` | The image is missing from the FAT partition. Falls back to Linux. |
| `TALOS: image range overlaps the FDT` | Firmware placed the FDT near `0x8e000000`. Falls back to Linux. Report it, because the staging address would need to move. |
| `Bad Data CRC` → `TALOS: image check failed` | Corrupt copy. Recopy it and check the hash with `--verify`. |
| `Failed to reserve memory for fdt …` / `FDT creation failed! hanging...` | Seen under QEMU before the script cleared `fdt_high`. If it appears on the board, reset, restore Linux, and report the full log. |
| `TALOS: boot-linux.scr returned without booting Linux` | Both seL4 and the Linux fallback failed. Restore from a host as above. |
| Kernel or test output stops after `Starting kernel` | The image ran but did not complete. Use the baseline (`--apply`) to check that the board itself is fine, then report the log. |

There is no keypress escape from the autoboot. To get back to Linux, use a host computer and `--restore-linux`.
