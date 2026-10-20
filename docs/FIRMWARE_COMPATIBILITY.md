# Firmware compatibility

Which board firmware the TALOS seL4 images have been used with, and how sure we are of each value.

**Evidence levels**

- **Confirmed**: read directly from files at repository assembly (2026-10-20): the board-extracted device tree, or the seL4 SD card's root filesystem.
- **Historical**: recorded in the bring-up log at the time, but not re-checkable from files.
- **Untested**: no TALOS image has been run with it.

## Tested configuration (verified baseline, 118 passed / 49 disabled)

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

## Experimental build

| Component | Status |
|---|---|
| Any firmware on a physical board | **Untested.** See the [experimental hardware test plan](../experimental/README.md#hardware-test-plan-in-this-order-record-full-serial-logs). |
| QEMU `virt` + OpenSBI (QEMU 8.2.2 built-in) + U-Boot 2025.10 (Ubuntu `u-boot-qemu` package, `qemu-riscv64_smode`) | Emulation only. See [TEST_RESULTS](../experimental/reports/TEST_RESULTS.md). This is not Discovery Kit firmware. |

## Other versions

Avnet's guide installs the **latest** FPGA design and Linux4Microchip release, which may be newer than the table above. **Newer releases are untested.** What could break:

- **Memory map**: both images expect seL4 RAM at `0x80000000–0x84000000` and `0x8a000000–0x92000000`, with the first 2 MiB reserved for SBI. A release that moves reserved regions or the HSS payload into those ranges could break seL4.
- **`scriptaddr`**: the verified manual steps and the autoboot candidate use `0x8e000000`.
- **SBI**: seL4 relies on HSS for SBI console, timer and HSM services (`UseRiscVOpenSBI=OFF`).
- **U-Boot commands**: the autoboot candidate needs `size`, `setexpr`, `fdt`, `test` and `iminfo`.
- **`fdt_high` with U-Boot ≥ 2025.10**: if a newer U-Boot environment sets `fdt_high=0xffffffffffffffff`, then `bootm 0x8e000000 - <fdt_blob>` fails with `Failed to reserve memory for fdt` (reproduced under QEMU with U-Boot 2025.10). Run `setenv fdt_high` first. The autoboot candidate already does this. The tested board's environment does not set `fdt_high`.

If you use a different version, record it in the table below and share the full serial log. Exact release-tag URLs for the tested versions were **not** verified. Use the official [Linux4Microchip releases](https://github.com/linux4microchip/meta-mchp/releases) and [Discovery Kit reference design releases](https://github.com/polarfire-soc/polarfire-soc-discovery-kit-reference-design/releases) pages.

## Results reported by teammates

| Date | Board / who | Linux4Microchip | U-Boot | HSS | FPGA design | Image | Result |
|---|---|---|---|---|---|---|---|
| 2026-10 (bring-up) | original board | 2026.04.1 | 2025.07-linux4microchip-2026.04 | 0.99.53 (historical) | v2507 | baseline `29d926e4…` | 118 passed / 49 disabled |
| | | | | | | | |
