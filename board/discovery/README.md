# board/discovery

Copies of the board directory from the original seL4 checkout (`sel4test/board/discovery/`). It sits outside any upstream repository, so it isn't covered by the patches.

| File | Notes |
|---|---|
| `discovery.dts` / `discovery.dtb` | Device tree extracted from the running board's `/sys/firmware/fdt` (official Linux4Microchip 2026.04.1 boot). Copied unchanged except that the board-unique Ethernet MAC (`local-mac-address` on `ethernet@20110000`) is set to zeros (2026-10-22). |

The original Docker build wrapper and pre-hardware progress notes that came with this directory are kept as a record in [history/first-bringup/](../../history/first-bringup/README.md). The failed host-side CMake attempt (`old-host-cmake-attempt/`) was deliberately left out.
