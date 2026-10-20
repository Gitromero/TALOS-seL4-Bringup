# Experimental build: clean image and autoboot candidate

> **Not hardware-verified.** Nothing in this folder has been run on a physical Discovery Kit. It has been built twice from clean sources (byte-identical results), privacy-audited, and run under **QEMU** only. QEMU success does **not** show the board will boot. Use a **spare** SD card, never the card you rely on. The [verified baseline](../README.md) remains the default and the recovery path. Making the experimental build the default requires explicit team approval **after** the hardware tests below pass.

## What's here

| Path | What it is |
|---|---|
| `images/sel4-experimental.uImage` | sel4test image rebuilt from clean, pinned upstream sources + this repo's patches, at a generic build path, with the board MAC zeroed |
| `images/SHA256SUMS` | Hashes for the experimental image and autoboot script |
| `boot/boot-auto.cmd` / `boot/boot-auto.scr` | **Autoboot candidate**: source and compiled U-Boot script (installed as `boot.scr`) |
| `patches/kernel/0002-mpfs-discovery-zero-board-mac.patch` | The only source difference from the verified build: zeroes the board-unique MAC in the DTS |
| `scripts/build-experimental.sh` | Fetches pinned sources, applies patches, builds in a digest-pinned container |
| `scripts/make-source-archive.sh` | Creates the GPL "corresponding source" release archive |
| `scripts/privacy_audit.py` | Scans artifacts for personal/machine-specific data |
| `reports/` | [Build report](reports/BUILD_REPORT.md), [privacy audit](reports/PRIVACY_AUDIT.md) (+ [JSON](reports/privacy-audit.json)), [test results](reports/TEST_RESULTS.md) |

## How it differs from the verified baseline

| | Verified baseline (`images/sel4.uImage`) | Experimental (`sel4-experimental.uImage`) |
|---|---|---|
| Hardware result | 118 passed / 49 disabled on the Discovery Kit | **none yet** |
| Sources | developer working tree (pinned SHAs + local edits) | clean `repo` fetch of the same pinned SHAs + the same patches + MAC patch |
| Build config | see [BUILD_PROVENANCE](../docs/BUILD_PROVENANCE.md) | identical settings; 11/11 generated kernel config headers byte-identical |
| Embedded paths | 594 absolute paths with developer username | none (only a `/build/reproducible-path/…` string from the upstream toolchain's libgcc, also in the baseline) |
| Board MAC in embedded DTB | `00:04:a3:6d:f8:11` | `00:00:00:00:00:00` |
| Load / entry address | `0x80650000` | **`0x80640000`** (payload is 35,840 bytes smaller because path strings are shorter, so the ELF loader is placed lower) |
| Boot script | `boot-sel4.scr`: stages image, **manual** `bootm` | `boot-auto.scr`: validates and boots **automatically**, Linux fallback |
| Toolchain | user image built from seL4 dockerfiles | `trustworthysystems/camkes@sha256:77dcf9c7…` (same GCC 14.2.0, CMake 3.31.6, mkimage 2025.01) |

**Why the MAC change is harmless for seL4:** neither seL4 nor sel4test drives the Ethernet controller. The embedded device tree is only used by seL4. Linux boots from its own `fitImage` device tree, and U-Boot and HSS use their own, so **Linux networking and the board's real MAC are unaffected**. If a future seL4 component drives Ethernet, it must get a valid MAC some other way, such as from the U-Boot-provided FDT or the board's unique ID.

## What the autoboot candidate does

[`boot/boot-auto.cmd`](boot/boot-auto.cmd), in order:

1. Uses **`${fdtcontroladdr}`** as the device tree. In U-Boot v2025.07, `common/board_r.c` sets `fdtcontroladdr` from `gd->fdt_blob` right after the environment loads, and `cmd/bdinfo.c` prints the same `gd->fdt_blob` as `fdt_blob`. So this is the value the verified manual procedure read from `bdinfo`, without the fixed `0xbf333da0`. It is validated with `fdt addr` (which fails on a bad header), and its size is read with `fdt header get`.
2. Gets the image size with `size` and checks that `[0x8e000000, +size)` does not overlap the FDT **before loading**. `0x8e000000` is the verified staging address (`scriptaddr`).
3. Loads the image, runs `iminfo` (header + data CRC), then `bootm 0x8e000000 - ${fdtcontroladdr}`, which is the verified command with the FDT address resolved automatically.
4. If any step fails, it loads **`boot-linux.scr`** and runs it, so a broken experimental install falls back to Linux.

**Why loading over `scriptaddr` is safe:** U-Boot copies a sourced script into a malloc'd buffer before executing it (`run_command_list` in `common/cli.c`, v2025.07). The verified script and the official Linux script both rely on this already.

**Remaining uncertainties (hardware tests required):**

- On the real board, is `${fdtcontroladdr}` equal to `bdinfo`'s `fdt_blob`? The source analysis says yes; this has not been observed.
- Does the board's U-Boot build include every command used (`size`, `setexpr`, `fdt header get`, `test -le`)? `load` and `size` live in the same source file, and `setexpr`, `fdt addr -q` and `test -e` appear in the board's own environment, but this is still unconfirmed.
- Does the seL4 kernel work with the elfloader at `0x80640000` on the board? It did under QEMU.
- **There is no keypress escape.** Once the script starts, the only ways back to Linux are a failed check or restoring `boot.scr` from a host computer. That's why this goes on a spare card.

## Install on a spare SD card

Prerequisite: a spare card prepared exactly like the README's §1 (official Linux4Microchip image). Mount its FAT `boot` partition on a Linux host, then from this repository's root:

```bash
BOOT=/media/$USER/boot          # EXAMPLE: replace with the real mount point of the SPARE card
sha256sum -c images/SHA256SUMS && (sha256sum -c experimental/images/SHA256SUMS)
scripts/install-to-boot.sh "$BOOT" --experimental            # dry run: shows what would change
scripts/install-to-boot.sh "$BOOT" --experimental --apply    # backs up Linux boot.scr, installs
udisksctl unmount -b /dev/sdX1                               # your card's boot partition
```

The installer refuses to proceed if `boot.scr` is already a TALOS script and no Linux backup exists. It never overwrites `boot-linux.scr`, and it writes `boot.scr` last.

Manual alternative (Linux), with the same safety check:

```bash
if [ ! -e "$BOOT/boot-linux.scr" ]; then
  if cmp -s "$BOOT/boot.scr" boot/boot-sel4.scr || cmp -s "$BOOT/boot.scr" experimental/boot/boot-auto.scr; then
    echo "STOP: boot.scr is already a TALOS script and there is no Linux backup"; false
  else
    cp "$BOOT/boot.scr" "$BOOT/boot-linux.scr" && sync
  fi
fi && \
cp experimental/images/sel4-experimental.uImage "$BOOT/" && \
cp experimental/boot/boot-auto.scr "$BOOT/boot.scr" && sync
```

## Rollback

| Want | Do (host computer, card's FAT partition mounted) |
|---|---|
| Linux again | `scripts/install-to-boot.sh "$BOOT" --restore-linux --apply`, or `cp "$BOOT/boot-linux.scr" "$BOOT/boot.scr" && sync` |
| Verified baseline (manual boot) | `scripts/install-to-boot.sh "$BOOT" --apply`. This installs `sel4.uImage` and `boot-sel4.scr` and keeps the backup |
| Check what's on the card | `scripts/install-to-boot.sh "$BOOT" --verify` (read-only) |

`sel4-experimental.uImage` and `sel4.uImage` can both stay on the card. Only `boot.scr` decides what runs.

## Hardware test plan (in this order; record full serial logs)

Each step separates one unknown. Stop at the first failure.

1. **FDT equivalence (baseline card, verified path).** At `RISC-V #`, run `bdinfo` and `printenv fdtcontroladdr`. ✔ Expect the same address. This is the key assumption of the autoboot.
2. **Command availability (same prompt).** Run `help size`, `help setexpr`, `help fdt`, `help test`, and `fdt addr ${fdtcontroladdr}; fdt header get x totalsize; printenv x`. ✔ All exist and `x` is set.
3. **Experimental image, manual boot (baseline card).** Copy `sel4-experimental.uImage` to the card, then at `RISC-V #`:
   ```text
   load mmc 0:1 0x8e000000 sel4-experimental.uImage
   iminfo 0x8e000000                       # Load Address: 80640000, Verifying Checksum ... OK
   fdt addr ${fdtcontroladdr}
   fdt header                              # magic: 0xd00dfeed
   bootm 0x8e000000 - ${fdtcontroladdr}
   ```
   ✔ `TALOS: root task reached seL4 user space`, then `Test suite passed. 118 tests passed. 49 tests disabled.`
4. **Autoboot (spare card, `--experimental` install).** Power on with no keyboard input. ✔ Expect `=== TALOS experimental seL4 autoboot ... ===`, `TALOS: FDT at 0x…`, `TALOS: image range ends below FDT` (or `FDT ends below image range`), `Verifying Checksum ... OK`, `TALOS: booting seL4 …`, then the 118/49 summary.
5. **Repeatability.** Cold-boot (power removed) at least 5 times. ✔ The same result each time.
6. **Fallback.** On the host, rename `sel4-experimental.uImage` on the card to `x.uImage`. ✔ Expect `TALOS: … not found` → `trying boot-linux.scr` → Linux boots. Rename it back afterwards.
7. **Rollback.** `--restore-linux --apply` on the host. ✔ The board boots Linux normally.

Only after steps 1–7 pass on at least one board, and the team approves, should the experimental image or autoboot be proposed as the default.

## Rebuild it yourself

Needs Linux, `git`, Google's `repo` launcher, Docker (your user able to run `docker`), network access to GitHub and Docker Hub, about 12 GB of disk for the container image and about 250 MB per build:

```bash
docker pull trustworthysystems/camkes@sha256:77dcf9c7927c138d88434d812d8bd8b86455f9418d0895682250745b192e291e
experimental/scripts/build-experimental.sh /path/to/new-empty-dir
sha256sum /path/to/new-empty-dir/out/sel4-experimental.uImage   # compare with experimental/images/SHA256SUMS
```

Two independent runs produced byte-identical images. The container image can only be pulled by digest while Docker Hub still serves it. See [reports/BUILD_REPORT.md](reports/BUILD_REPORT.md).
