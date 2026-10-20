# U-Boot boot scripts

| File | What it is | Status |
|---|---|---|
| `boot-sel4.scr` | **The verified seL4 staging script.** Byte-for-byte copy of `boot.scr` from the team's working seL4 SD card. Install it on the card as `boot.scr`. | Used in the verified 118-test boot |
| `boot-sel4.cmd` | Readable source text of `boot-sel4.scr`, extracted from its payload. | Rebuild proven byte-identical (see below) |
| `boot-linux.scr` | Byte-for-byte copy of `boot-linux.scr` from the same card: the **Linux4Microchip `boot.scr` that the official image shipped**, saved as a backup before it was replaced. | Reference/recovery only |
| `boot-linux.cmd` | Readable source text of `boot-linux.scr`. | Rebuild proven byte-identical |

SHA-256 values for the two `.scr` files are in [`../images/SHA256SUMS`](../images/SHA256SUMS).

## What `boot-sel4.scr` does

The full script ([`boot-sel4.cmd`](boot-sel4.cmd)):

```text
echo === seL4 Discovery Kit Boot Test ===
echo Loading seL4 image...

if load mmc 0:${distro_bootpart} ${scriptaddr} sel4.uImage; then
    iminfo ${scriptaddr}
    echo seL4 image loaded successfully.
else
    echo ERROR: Could not load sel4.uImage
fi
```

- It **loads and checks** `sel4.uImage`. It does **not** run `bootm`, so it **does not boot seL4**. It is a *staging* script, used because the U-Boot countdown could not reliably be interrupted from the serial console.
- It loads to `${scriptaddr}`, not a literal address. The saved environment on the verified card (`uboot.env`) sets `scriptaddr=0x8e000000`, which is why all manual commands use `0x8e000000`.
- It loads from `mmc 0:${distro_bootpart}`, the partition the script was found on (the FAT boot partition, `0:1` on the official image layout).

### Why a `RISC-V #` prompt appears "eventually"

The following is **analysis of the card's saved `uboot.env`, not something observed step by step on the board**. The board's live environment may differ from the saved file.

`bootcmd` runs `distro_bootcmd`, which tries `boot_targets= mmc0 dhcp` in order. On `mmc0`, U-Boot finds `boot.scr` and sources it. When the script *returns* (instead of booting a kernel), U-Boot's distro boot prints `SCRIPT FAILED: continuing...` and keeps scanning: EFI boot manager, then the `dhcp` (network) target. Only after every target has failed does it drop to the `RISC-V #` prompt. That matches the historical observation that the prompt appeared after a delay. **`SCRIPT FAILED: continuing...` is therefore expected here and is not an error.**

Two consequences:

1. The network attempt can take a while, especially with Ethernet connected. Waiting is the verified behavior. Unplugging Ethernet may shorten the wait, but **we have not tested this**.
2. The `dhcp` target can load files to `${scriptaddr}` and `${kernel_addr_r}`, which could in principle overwrite the staged image. So the teammate instructions always run `load` again and check with `iminfo` before booting.

## How the `.cmd` sources were recovered and checked

No hand-written source file for either script was found in the workspace. A legacy U-Boot script image is a 64-byte header, an 8-byte length table and then the plain script text. The text was therefore extracted with:

```bash
tail -c +73 boot-sel4.scr > boot-sel4.cmd
```

To prove the extracted text is the real source, it was rebuilt with the original header timestamp and compared:

```bash
SOURCE_DATE_EPOCH=1792486890 mkimage -A riscv -O linux -T script -C none -n '' \
    -d boot-sel4.cmd rebuilt.scr && cmp rebuilt.scr boot-sel4.scr      # identical
SOURCE_DATE_EPOCH=1777452750 mkimage -A riscv -O linux -T script -C none -n '' \
    -d boot-linux.cmd rebuilt.scr && cmp rebuilt.scr boot-linux.scr    # identical
```

Both comparisons were byte-identical (U-Boot `mkimage`/`dumpimage` from the host's `u-boot-tools`). Even so, **install the shipped `.scr` binary**, not a rebuilt one. The `.cmd` files are for reading and for the future autoboot work.

`dumpimage -l` header summaries:

| File | Created (header) | Type | Data size | Data CRC |
|---|---|---|---|---|
| `boot-sel4.scr` | 2026-10-20 09:01:30 UTC | RISC-V Linux Script (uncompressed) | 260 B (script 252 B) | `0x7E5AFCC4` |
| `boot-linux.scr` | 2026-04-29 08:52:30 UTC | RISC-V Linux Script (uncompressed) | 227 B (script 219 B) | `0x8B8DC2B5` |

## Recovering normal Linux boot

`boot-linux.scr` **on your own SD card** is the backup that matters, because the README procedure creates it from your card's original `boot.scr`. To restore Linux, mount the card's FAT boot partition on a host and run:

```bash
cp "$BOOT/boot-linux.scr" "$BOOT/boot.scr" && sync
```

If your card's backup is missing, you can use this repository's `boot/boot-linux.scr`. It came from an official Linux4Microchip **2026.04.1** Discovery Kit image, and the card's rootfs kernel modules are `6.18.17-linux4microchip-2026.04.1`. It loads `fitImage` and boots it. Releases are likely similar but not guaranteed identical. The last-resort fix is to re-flash the official `.wic` image.

## Do not

- Do not replace `boot-sel4.scr` with an edited or "improved" script and call it verified.
- Do not add `bootm` with a fixed FDT address such as `0xbf333da0`. That address was valid for one session only. An automatic-boot **candidate** lives separately in [`../experimental/boot/`](../experimental/boot/). It is QEMU-tested only and must not replace this verified script until it passes the hardware test plan.
