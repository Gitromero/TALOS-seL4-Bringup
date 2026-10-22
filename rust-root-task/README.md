# Rust root task on seL4

A `no_std` Rust program that runs as seL4's root task (the first and only user-space program the kernel starts) on the Discovery Kit. It prints two lines and suspends itself. It is a bring-up check that the Rust toolchain, rust-sel4 and this board's kernel work together.

**Verified on the Discovery Kit on 2026-10-21**, network-booted ([docs/NETBOOT.md](../docs/NETBOOT.md)):

```text
ELF-loader started on (HART 1) (NODES 1)
Loaded DTB from 80281630.
ELF-loading image 'kernel' to 80200000
ELF-loading image 'rootserver' to 8022a000
Enabling MMU and paging
Jumping to kernel-image entry point...
Bootstrapping kernel
Initializing PLIC...
Available phys memory regions: 2
  [80200000..84000000)
  [8a000000..92000000)
Booting all finished, dropped to user space
Hello from Rust on seL4!
TALOS: Rust root task running, 50 untyped regions available
```

After that the console goes quiet: the task has suspended itself and nothing reads input. Reset the board to start again.

> The image that produced this log was built with the same sources and settings from the developer's local seL4 checkout. `build.sh` below builds against the clean pinned checkout instead (kernel with the board MAC zeroed), which gives a slightly different image (load address `0x80262000` instead of `0x80260000`). **Boot it once and record the result** in [FIRMWARE_COMPATIBILITY.md](../docs/FIRMWARE_COMPATIBILITY.md#results-reported-by-teammates).

## How it is put together

seL4 has no shell or login: at boot the kernel starts exactly one program, the root task, and the board does whatever that program does. sel4test's root task is the test driver; here it is `rust/hello`. Everything else is reused from the sel4test build so the kernel matches `images/sel4test.uImage`.

| Piece | Source | Built in |
|---|---|---|
| seL4 kernel + C elfloader | patched pinned checkout from [`scripts/build-sel4test.sh`](../scripts/build-sel4test.sh), configured by [`cmake/settings.cmake`](cmake/settings.cmake) with the same options (debug, printing on, single core, `UseRiscVOpenSBI=OFF`, `KernelPolarfireBoard=discovery`) | pinned toolchain image `trustworthysystems/camkes@sha256:77dcf9c7…` |
| Rust root task | [`rust/hello/src/main.rs`](rust/hello/src/main.rs), using [rust-sel4](https://github.com/seL4/rust-sel4) @ `7a2321f2d84310ba7a09fe7f5988e6dcecde3566` (`sel4`, `sel4-root-task`) | `sel4-rust-tutorial:latest` (nightly-2026-03-18 with `rust-src`, libclang) |
| Rust target | [`rust/target-specs/riscv64gc-sel4-roottask.json`](rust/target-specs/riscv64gc-sel4-roottask.json), copied from rust-sel4's `support/targets/`. `riscv64gc` because the kernel enables the F and D extensions | |
| Packaging | [`cmake/CMakeLists.txt`](cmake/CMakeLists.txt): the elfloader bundles `kernel.elf`, the board DTB and the Rust ELF; `make-uimage` wraps the elfloader for U-Boot `bootm`, exactly as for sel4test | pinned toolchain image |

How the pieces connect:

- **libsel4 headers for Rust.** rust-sel4 reads the kernel's configuration (`kernel/gen_config.json`, `sel4/gen_config.json`), headers and API XML through `SEL4_INCLUDE_DIRS`, a colon-separated list. `build.sh` passes the kernel source's `libsel4/{include, arch_include/riscv, sel4_arch_include/riscv64, sel4_plat_include/polarfire, mode_include/64}` plus the build directory's generated `libsel4/…` and `kernel/gen_config`. All of them are needed; a missing platform directory fails with `'sel4/plat/api/constants.h' file not found`.
- **Generated headers first.** The kernel step must build the `libsel4.a` target, not just `kernel.elf`: only that generates every header bindgen needs (otherwise: `'sel4/sel4_arch/types_gen.h' file not found`).
- **Using the C elfloader with a non-CMake root task.** The elfloader only needs a target named `rootserver_image` whose `ROOTSERVER_IMAGE` property is the root task's path, so `CMakeLists.txt` sets that directly instead of calling `DeclareRootserver()`. It also adds `util_libs/libcpio`, which the elfloader links against and which sel4test normally pulls in through its own imports.
- **Kernel configuration.** Generated kernel config and DTB are identical to the sel4test build except `CONFIG_ROOT_CNODE_SIZE_BITS` (sel4test sets 13; the default 12 is used here).

## Build

You need:

1. The patched sel4test checkout from a clean build: `scripts/build-sel4test.sh /path/to/new-empty-dir` leaves it in `/path/to/new-empty-dir/sel4test` ([prerequisites](../docs/SETUP.md#docker-and-build-prerequisites-only-for-rebuilding-images)).
2. The `sel4-rust-tutorial:latest` Docker image from the [seL4 Rust tutorial code](https://github.com/seL4/seL4-rust-tutorial-code) repository: clone it and run `make -C docker build`. That builds the image with your own UID, so files it writes into `rust-root-task/build/` belong to you.

Then, from the repository root:

```bash
rust-root-task/build.sh /path/to/new-empty-dir/sel4test               # add --reconfigure for a clean build
```

Output: `rust-root-task/build/images/rust-hello.uImage` (about 175 KiB). The first build downloads rust-sel4 and its crates (network access to GitHub and crates.io).

## Boot

**Network (fastest):** copy the image to `tftp/root/rust.uImage` and follow [docs/NETBOOT.md](../docs/NETBOOT.md).

**SD card:** copy it next to `sel4test.uImage` on the FAT boot partition, e.g. as `rust.uImage`. At `RISC-V #`:

```text
load mmc 0:1 0x8e000000 rust.uImage
iminfo 0x8e000000
bdinfo                              # note fdt_blob
fdt addr <fdt_blob>
fdt header                          # magic: 0xd00dfeed
bootm 0x8e000000 - <fdt_blob>
```

The autoboot `boot.scr` keeps booting sel4test, so the card still works as before.

## Changing the program

Edit [`rust/hello/src/main.rs`](rust/hello/src/main.rs), rerun `build.sh` (incremental), copy the image to `tftp/root/`, reset the board and netboot. `sel4::debug_println!` goes through `seL4_DebugPutChar` → kernel → SBI → the U-Boot/seL4 serial port.
