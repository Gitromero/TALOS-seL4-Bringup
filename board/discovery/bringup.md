# seL4 bring-up on MPFS-DISCO-KIT — progress log

## 2026-10-19 — Session 1

### Environment
- Host has no RISC-V toolchain or ninja. The existing `cbuild/` (QEMU) was built
  inside the Docker image `user_img-<user>` (seL4-CAmkES-L4v-dockerfiles,
  `make user`): GCC `riscv64-unknown-elf-` 14.2.0, ninja, dtc, mkimage.
  No host packages installed; all builds run in that container.
- `board/discovery/build.sh` runs the container with the repo mounted at its
  host path (CMake paths stay valid) and as the host UID (no root-owned files).
- The failed host-side CMake attempt in `build-polarfire/` was moved (not
  deleted) to `board/discovery/old-host-cmake-attempt/`.
- `cbuild/` untouched.

### Hardware facts verified from `discovery.dts`
| Item | Discovery Kit | Kernel assumption | OK |
|---|---|---|---|
| Boot hart | `boot-hartid = 1`; hart 0 = E51 (disabled) | `FIRST_HART_ID 1` | yes |
| Timebase | `0xf4240` = 1 MHz | `TIMER_FREQUENCY 1000000` | yes |
| PLIC | `0xc000000`, `sifive,plic-1.0.0`, ndev 186 | `MAX_IRQ 186`, riscv_plic0 | yes |
| CLINT | `0x2000000`, `sifive,clint0` | not matched by hardware.yml | overlay fixes compatible |
| Console | MMUART4 `0x20106000` (ns16550a-style, shift 2, 32-bit) | kernel uses SBI putchar | n/a |
| MMUART3 `0x20104000` | **disabled** | libplatsupport polarfire default | avoided (see below) |

Memory (MSS aliases one DDR through several windows):
- Usable cached RAM per firmware DT: `0x80000000–0x84000000` (64 MiB),
  `0x8A000000–0x92000000` (128 MiB).
- `0x84000000–0x8A000000`: reserved region + fabric buffer, not in any memory node.
- `0xC4000000` (96 MiB) and `0x1412000000` (256 MiB): non-cached aliases / DMA pools.
- `0x1022000000` (480 MiB): cached-high alias; contains HSS buffer `0x103FC00000`.
- Decision: seL4 uses only the two cached-low slices; other memory nodes deleted
  in the overlay. 2 MiB at `0x80000000` kept reserved (same as Icicle overlay).

### Kernel changes (kernel/ git)
- `src/plat/polarfire/config.cmake`: new `config_choice KernelPolarfireBoard`
  (`icicle` default — unchanged behavior; `discovery`) selecting the DTS list.
- `tools/dts/mpfs_discovery.dts`: verbatim copy of `board/discovery/discovery.dts`.
- `src/plat/polarfire/overlay-discovery.dts`: delete aliased memory nodes,
  `seL4,kernel-devices` (CLINT, PLIC), CLINT compatible -> `riscv,clint0`,
  reserve `0x80000000+2MiB`.

### Build configuration (`board/discovery/build.sh`)
```
../init-build.sh -DPLATFORM=polarfire -DKernelPolarfireBoard=discovery \
  -DRELEASE=OFF -DSMP=OFF -DUseRiscVOpenSBI=OFF -DElfloaderImage=uimage \
  -DLibSel4PlatSupportUseDebugPutChar=ON
ninja
```
- `UseRiscVOpenSBI=OFF`: HSS already provides M-mode SBI; U-Boot hands off in S-mode.
- `LibSel4PlatSupportUseDebugPutChar=ON`: user output goes via `seL4_DebugPutChar`
  -> kernel -> SBI, so user space never touches the (disabled) MMUART3.
- `ElfloaderImage=uimage` is force-overridden to `elf` by sel4test's
  `ApplyData61ElfLoaderSettings`; build.sh wraps the ELF with
  `tools/seL4/cmake-tool/helpers/make-uimage` instead.
- Effective: Debug build, KernelPrinting ON, MaxNumNodes 1, Sel4testHaveTimer OFF.

### Artifacts (`build-polarfire/images/`)
- `sel4test-driver-image-riscv-polarfire` — ELF64 RISC-V, entry `0x80650000`,
  one LOAD segment `0x80650000`, filesz `0x2ea738`, memsz `0x2f1000`.
- `sel4test-driver-image-riscv-polarfire.uImage` — RISC-V Linux kernel image,
  uncompressed, load = entry = `0x80650000`, 2.92 MiB.

Physical layout at boot (from QEMU run):
- kernel `0x80200000–0x80224000`, DTB `0x80224000–0x8022a000`,
  rootserver `0x8022a000–0x80630000`, elfloader `0x80650000–0x80941000`.
- All inside the first 64 MiB bank.

### QEMU smoke test (same image, not board)
`qemu-system-riscv64 -machine virt -smp 2 -m 2G -bios default -kernel <ELF>`:
elfloader switched to hart 1 via HSM, kernel booted, reported both RAM regions,
user space printed `TALOS: root task reached seL4 user space`, sel4test ran
113+ tests with no failures before the 60 s timeout. Validates image layout,
not HSS SBI compatibility.

### Open questions / blockers
- HSS (SBI impl ID 8) legacy SBI support (console putchar, set_timer) — unverified.
  Check with U-Boot `sbi` command.
- U-Boot relocation address / RAM view, legacy uImage support — need `bdinfo`.

### Hardware test results
- (none yet)
