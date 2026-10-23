# U-Boot boot scripts

| File | What it is | Status |
|---|---|---|
| `boot-auto.scr` | **The autoboot script.** Install it on the card as `boot.scr`. Loads, checks and boots `sel4test.uImage` with no typing, and falls back to Linux on any failed check. | Booted sel4test on the board (118 passed / 49 disabled), see [History](#history) |
| `boot-auto.cmd` | Source text of `boot-auto.scr`. | `.scr` payload is byte-identical to this file |
| `boot-linux.scr` | Byte-for-byte copy of the **Linux4Microchip `boot.scr` that the official image shipped**, saved as a backup before it was replaced. | Reference/recovery only |
| `boot-linux.cmd` | Readable source text of `boot-linux.scr`. | Rebuild proven byte-identical |

SHA-256 values are in [`../images/SHA256SUMS`](../images/SHA256SUMS).

## What `boot-auto.scr` does

[`boot-auto.cmd`](boot-auto.cmd), in order:

1. Uses **`${fdtcontroladdr}`** as the device tree. In U-Boot v2025.07, `common/board_r.c` sets `fdtcontroladdr` from `gd->fdt_blob` right after the environment loads, and `cmd/bdinfo.c` prints the same `gd->fdt_blob` as `fdt_blob`. So it is the value the manual procedure reads from `bdinfo`, without a fixed address. It is validated with `fdt addr` (which fails on a bad header), and its size is read with `fdt header get`.
2. Gets the image size with `size` and checks that `[0x8e000000, +size)` does not overlap the FDT **before loading**. `0x8e000000` is the board's `scriptaddr`.
3. Loads the image, runs `iminfo` (header + data CRC), clears `fdt_high` in RAM, then runs `bootm 0x8e000000 - ${fdtcontroladdr}`.
4. If any step fails, it loads **`boot-linux.scr`** and runs it, so a broken install falls back to Linux.

Every line it prints starts with `TALOS:`, so a failure says which check failed ([messages](../docs/TROUBLESHOOTING.md#autoboot-messages)).

**Why clear `fdt_high`:** with `fdt_high` set to all ones ("use the FDT in place"), U-Boot ≥ 2025.10 refuses to boot (`Failed to reserve memory for fdt`), because U-Boot has already reserved that memory. Clearing it lets `bootm` copy the FDT to free memory. The board's saved environment doesn't set `fdt_high`, so on the board this changes nothing. It is a RAM-only change and never saved.

**Why loading over `scriptaddr` is safe:** U-Boot copies a sourced script into a malloc'd buffer before executing it (`run_command_list` in `common/cli.c`, v2025.07). The official Linux script relies on this too.

**There is no keypress escape once the script runs.** To get to `RISC-V #` instead, press a key during U-Boot's `Hit any key to stop autoboot` countdown, before the script starts.

## Rebuilding `boot-auto.scr`

[`scripts/build-sel4test.sh`](../scripts/build-sel4test.sh) builds it from `boot-auto.cmd` inside the pinned toolchain container. By hand, with the same `mkimage` and timestamp:

```bash
SOURCE_DATE_EPOCH=1790092976 mkimage -A riscv -O linux -T script -C none -n '' \
    -d boot/boot-auto.cmd boot/boot-auto.scr
tail -c +73 boot/boot-auto.scr | cmp - boot/boot-auto.cmd      # payload = source
```

A legacy U-Boot script image is a 64-byte header, an 8-byte length table and then the plain script text, which is why `tail -c +73` recovers the source.

## History

The first revision of this repository shipped two scripts:

- `boot-sel4.scr`: the original staging script. It loaded and checked `sel4.uImage` but did not boot it; seL4 was then started by typing `bootm` at `RISC-V #`. It and the original image have been removed. They are in git history.
- `experimental/boot/boot-auto.scr`: this autoboot script, loading `sel4-experimental.uImage`. Installed on an SD card with that image, it booted the board and ran sel4test to `118 tests passed. 49 tests disabled.` with no typing.

When the experimental build became the only image, the image file was renamed `sel4test.uImage` (same bytes, SHA-256 `2c986076…`) and the script was changed to match. The **only** differences from the script that ran on the board:

```diff
-# TALOS experimental seL4 autoboot CANDIDATE -- NOT verified on a physical board.
-# Loads sel4-experimental.uImage, validates image and U-Boot's own device tree,
+# TALOS seL4 autoboot for the PolarFire SoC Discovery Kit.
+# Loads sel4test.uImage, validates image and U-Boot's own device tree,
-echo === TALOS experimental seL4 autoboot (candidate, not hardware-verified) ===
-setenv talos_img sel4-experimental.uImage
+echo === TALOS seL4 autoboot ===
+setenv talos_img sel4test.uImage
```

The installer still recognises both earlier scripts by hash, so it never mistakes one for the Linux backup on a card set up from the first revision.

## How `boot-linux.cmd` was recovered

No hand-written source was found in the workspace, so the text was extracted from the payload and checked by rebuilding with the original header timestamp:

```bash
tail -c +73 boot-linux.scr > boot-linux.cmd
SOURCE_DATE_EPOCH=1777452750 mkimage -A riscv -O linux -T script -C none -n '' \
    -d boot-linux.cmd rebuilt.scr && cmp rebuilt.scr boot-linux.scr    # identical
```

To repeat the check from the repository root, without touching the tracked files:

```bash
tail -c +73 boot/boot-linux.scr | cmp - boot/boot-linux.cmd && echo "payload = source"
SOURCE_DATE_EPOCH=1777452750 mkimage -A riscv -O linux -T script -C none -n '' \
    -d boot/boot-linux.cmd /tmp/boot-linux-rebuilt.scr && cmp /tmp/boot-linux-rebuilt.scr boot/boot-linux.scr && echo identical
```

| File | Created (header) | Type | Data size | Data CRC |
|---|---|---|---|---|
| `boot-linux.scr` | 2026-04-29 08:52:30 UTC | RISC-V Linux Script (uncompressed) | 227 B (script 219 B) | `0x8B8DC2B5` |

## Recovering normal Linux boot

`boot-linux.scr` **on your own SD card** is the backup that matters, because the README procedure creates it from your card's original `boot.scr`. To restore Linux, mount the card's FAT boot partition on a host and run:

```bash
BOOT=$(findmnt -nro TARGET -S LABEL=boot)
cp "$BOOT/boot-linux.scr" "$BOOT/boot.scr" && sync
```

If your card's backup is missing, you can use this repository's `boot/boot-linux.scr`. It came from an official Linux4Microchip **2026.04.1** Discovery Kit image, and the card's rootfs kernel modules are `6.18.17-linux4microchip-2026.04.1`. It loads `fitImage` and boots it. Other releases are likely similar but not guaranteed identical. The last-resort fix is to re-flash the official `.wic` image.

## Do not

- Do not add `bootm` with a fixed FDT address such as `0xbf333da0`. Use `${fdtcontroladdr}`, as the autoboot script and the manual commands in these docs do.
- Do not edit `boot-auto.cmd` and call the result hardware-verified. Any logic change needs a board run.
