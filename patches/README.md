# Source patches

These are the **only** source changes behind `images/sel4test.uImage`, relative to the upstream revisions pinned in [`../source/sel4test-manifest-pinned.xml`](../source/sel4test-manifest-pinned.xml). Every other project in the checkout is unmodified. Teammates don't need them to boot seL4. [`scripts/build-sel4test.sh`](../scripts/build-sel4test.sh) applies both, in table order.

| Patch | Apply in | Baseline SHA |
|---|---|---|
| `kernel/0001-polarfire-add-discovery-kit-board.patch` | `kernel/` | `0f108291103d2797fc604fba71a1774d0ac20975` |
| `sel4test/0001-sel4test-driver-talos-banner.patch` | `projects/sel4test/` | `b00d84fca8890e34f6007f104372fec5e82a23d1` |

## What they change

**Kernel: Discovery Kit board support** (adds the board alongside the existing Icicle Kit support, which stays the default)

- `src/plat/polarfire/config.cmake`: new `KernelPolarfireBoard` choice, `icicle` (default, upstream behavior unchanged) or `discovery`, which selects the DTS list.
- `src/plat/polarfire/overlay-discovery.dts` (new): deletes the aliased memory nodes (`0xc4000000`, `0x1022000000`, `0x1412000000`) so seL4 sees only the two cached-low RAM slices. Marks CLINT and PLIC as `seL4,kernel-devices`, sets the CLINT compatible string to `riscv,clint0`, and reserves 2 MiB at `0x80000000` for firmware.
- `tools/dts/mpfs_discovery.dts` (new): the board's own device tree as extracted from `/sys/firmware/fdt`, with one change: the board-unique `local-mac-address` on `ethernet@20110000` is set to zeros, matching the board's second (unused) MAC node. It is identical to [`../board/discovery/discovery.dts`](../board/discovery/discovery.dts). seL4 and sel4test never use Ethernet, and Linux, U-Boot and HSS use their own device trees, so the board's networking is unaffected.

**sel4test: TALOS banner**

- `apps/sel4test-driver/src/main.c`: prints `TALOS: root task reached seL4 user space` at the start of `main()`. This is a quick sign that user space started. The patch reproduces the original edit exactly, including its trailing whitespace.

## Applying

From the root of a `repo` checkout synced to the pinned manifest:

```bash
git -C kernel apply --check /path/to/patches/kernel/0001-polarfire-add-discovery-kit-board.patch
git -C kernel apply         /path/to/patches/kernel/0001-polarfire-add-discovery-kit-board.patch
git -C projects/sel4test apply --whitespace=nowarn /path/to/patches/sel4test/0001-sel4test-driver-talos-banner.patch
```

`patch -p1` inside each directory also works. The sel4test patch deliberately keeps one line with trailing whitespace, so it reproduces the original edit byte-for-byte. `git apply` warns about it (`--whitespace=nowarn` silences that). `.gitattributes` marks `*.patch` as `-text -whitespace` so Git never rewrites the patches, but **editors that strip trailing whitespace will break them**.

**Verification:** `kernel/0001` and `sel4test/0001` were generated from the original developer working tree, then applied to fresh clones at the pinned SHAs; the resulting four files were byte-identical (`cmp`) to that tree, except for the zeroed MAC line in `mpfs_discovery.dts`. The clean build with these patches reproduces `images/sel4test.uImage` byte-for-byte. (The MAC was first zeroed by a separate patch `kernel/0002`; it was folded into `kernel/0001` on 2026-10-22 so no source file carries the board's MAC. The resulting DTS is the same, so the image did not change.) Applying them to other revisions has not been tested.

The patches are plain `git diff` output, not `git format-patch` commits, so they carry no author metadata. Turn them into commits however the team prefers.
