# board/discovery

Copies of the board directory from the original seL4 checkout (`sel4test/board/discovery/`). It sits outside any upstream repository, so it isn't covered by the patches.

| File | Notes |
|---|---|
| `build.sh` | Docker build wrapper that produced the first image (`sel4.uImage`, since removed). Kept as a record; the current image is built by [`scripts/build-sel4test.sh`](../../scripts/build-sel4test.sh). Copied unchanged. It expects to live at `<sel4test checkout>/board/discovery/build.sh`, because it uses `../..` as the checkout root and writes to `build-polarfire/`. It uses the container image `user_img-$(whoami)` unless `SEL4_DOCKER_IMAGE` is set. |
| `bringup.md` | Original pre-hardware progress log. Copied with the local username replaced by `<user>`. Its "Hardware test results: (none yet)" predates the successful board run, which is recorded in [`../../docs/BRINGUP_GUIDE.md`](../../docs/BRINGUP_GUIDE.md). |
| `discovery.dts` / `discovery.dtb` | Device tree extracted from the running board's `/sys/firmware/fdt` (official Linux4Microchip 2026.04.1 boot). Copied unchanged except that the board-unique Ethernet MAC (`local-mac-address` on `ethernet@20110000`) is set to zeros (2026-10-22). |

The failed host-side CMake attempt (`old-host-cmake-attempt/`) was deliberately left out.
