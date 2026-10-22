# Firmware compatibility

Which board firmware the TALOS seL4 images have been used with, and how sure we are of each value.

**Evidence levels**

- **Confirmed**: read directly from files at repository assembly (2026-10-20): the board-extracted device tree, or the seL4 SD card's root filesystem.
- **Historical**: recorded in the bring-up log at the time, but not re-checkable from files.
- **Untested**: no TALOS image has been run with it.

## Tested configuration (`sel4test.uImage` autoboot: 118 passed / 49 disabled)

| Component | Version | Evidence | Source of evidence |
|---|---|---|---|
| Linux4Microchip SD image | **2026.04.1** (Linux 6.18.17) | Confirmed | `/lib/modules/6.18.17-linux4microchip-2026.04.1-g7fbe4f69684d` on the seL4 card's root partition |
| U-Boot | **2025.07-linux4microchip-2026.04** | Confirmed | `u-boot,version` in `board/discovery/discovery.dts` (extracted from the running board) |
| FPGA reference design | **MPFS_DISCOVERY_KIT reference RTL v2507** | Confirmed | root `compatible = "microchip,mpfs-disco-kit-reference-rtl-v2507"` in the same DTS |
| Hart Software Services (HSS) | **0.99.53** | Historical | bring-up log ([BRINGUP_GUIDE §2](BRINGUP_GUIDE.md#2-hardware-firmware-and-host)) |
| SBI implementation | spec v2.0, impl ID `0x8`, impl version `0x10002` | Historical | bring-up log |
| `boot-linux.scr` | from the 2026.04.1 image, header date 2026-04-29 | Confirmed | `boot/boot-linux.scr` (byte copy from the card) |
| U-Boot environment | `scriptaddr=0x8e000000`, `fdt_addr_r=0x8a000000`, `kernel_addr_r=0x80200000`, `bootdelay=2`, `boot_targets= mmc0 dhcp` | Confirmed (file); not confirmed as the board's live environment | `uboot.env` on the card (valid CRC) |

HSS and FPGA programming were **not** changed during the seL4 bring-up. The board already had them from the official setup.

Observed on the same board on 2026-10-21 (U-Boot console):

| Item | Value |
|---|---|
| Firmware banner before U-Boot | `OpenSBI v1.2` (runtime SBI version 2.0, `Platform Name: Microchip PolarFire(R) SoC`, `Domain1 Name: u-boot.bin`, boot hart 1) |
| U-Boot | `2025.07-linux4microchip-2026.04 (Apr 29 2026 - 08:52:30 +0000)`, `Model: Microchip PolarFire-SoC Discovery Kit`, `DRAM: 1 GiB (total 1.8 GiB)` |
| U-Boot network | `eth0: ethernet@20110000`, gigabit link, `dhcp` / `ping` / `tftpboot` available, no `wget` ([NETBOOT.md](NETBOOT.md)) |
| `bdinfo` | `fdt_blob = 0xbf333da0`, `relocaddr = 0xbfb3b000`, boot hart 1 |

QEMU runs (QEMU 8.2.2 `virt` + built-in OpenSBI + Ubuntu U-Boot 2025.10 `qemu-riscv64_smode`) are emulation only and are recorded in [TEST_RESULTS](../reports/TEST_RESULTS.md); they are not Discovery Kit firmware.

## Other versions

Avnet's guide installs the **latest** FPGA design and Linux4Microchip release, which may be newer than the table above. **Newer releases are untested.** What could break:

- **Memory map**: both images expect seL4 RAM at `0x80000000–0x84000000` and `0x8a000000–0x92000000`, with the first 2 MiB reserved for SBI. A release that moves reserved regions or the HSS payload into those ranges could break seL4.
- **`scriptaddr`**: the manual steps and the autoboot script use `0x8e000000`.
- **SBI**: seL4 relies on HSS for SBI console, timer and HSM services (`UseRiscVOpenSBI=OFF`).
- **U-Boot commands**: the autoboot script needs `size`, `setexpr`, `fdt`, `test` and `iminfo` (all present in the tested U-Boot).
- **`fdt_high` with U-Boot ≥ 2025.10**: if a newer U-Boot environment sets `fdt_high=0xffffffffffffffff`, then `bootm 0x8e000000 - <fdt_blob>` fails with `Failed to reserve memory for fdt` (reproduced under QEMU with U-Boot 2025.10). Run `setenv fdt_high` first. The autoboot script already does this. The tested board's environment does not set `fdt_high`.

If you use a different version, record it in the table below and share the full serial log. Exact release-tag URLs for the tested versions were **not** verified. Use the official [Linux4Microchip releases](https://github.com/linux4microchip/meta-mchp/releases) and [Discovery Kit reference design releases](https://github.com/polarfire-soc/polarfire-soc-discovery-kit-reference-design/releases) pages.

## Results reported by teammates

| Date | Board / who | Linux4Microchip | U-Boot | HSS | FPGA design | Image | Result |
|---|---|---|---|---|---|---|---|
| 2026-10 (bring-up) | original board | 2026.04.1 | 2025.07-linux4microchip-2026.04 | 0.99.53 (historical) | v2507 | first image `sel4.uImage` `29d926e4…` (removed; in git history), manual `bootm` | 118 passed / 49 disabled |
| 2026-10 | original board | 2026.04.1 | 2025.07-linux4microchip-2026.04 | 0.99.53 (historical) | v2507 | `sel4test.uImage` `2c986076…` (then named `sel4-experimental.uImage`), **autoboot**, no typing | 118 passed / 49 disabled |
| 2026-10-21 | original board | 2026.04.1 | 2025.07-linux4microchip-2026.04 | n/a | v2507 | Rust root task, network boot (developer-tree build, load `0x80260000`) | `Hello from Rust on seL4!`, 50 untyped regions |
| | | | | | | | |
