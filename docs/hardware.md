# Discovery Kit hardware

Sections 1–6 are the peripheral map; [§7](#7-serial-channels-and-board-reset) covers the serial channels and remote reset, and [§8](#8-firmware-compatibility) the firmware versions the images were tested with.

What hardware the PolarFire SoC Discovery Kit exposes, where each block lives in physical memory, how it's switched on, which interrupt it raises, and how a seL4 root task (or partition) reaches it. Ordered by relevance to TALOS, an APEX-like (ARINC 653-style) partitioned OS on seL4: first the user LEDs (the simplest output, verified on the board), then peripherals a partitioned system is likely to use, then the rest.

**Legend**

| Mark | Meaning |
|---|---|
| ★ | User LEDs: verified on the board from U-Boot |
| ◆ | Candidate for TALOS (timing, health monitoring, partition-owned I/O). Not a design decision |
| · | Present, not needed for TALOS so far |
| ⛔ | Owned by the seL4 kernel or the firmware: don't map it into user space |

**Evidence levels.** **Board-verified** = read or driven on our board from the U-Boot prompt on 2026-10-22. **DT** = from the board's own device tree ([`board/discovery/discovery.dts`](../board/discovery/discovery.dts), extracted from the running board). **Microchip/Linux** = from Microchip's register layout as used by the upstream Linux and bare-metal drivers, not independently checked on the board.

---

## 1. User LEDs ★

### Where they are

Eight user LEDs, driven by two of the MSS (Microprocessor SubSystem) GPIO controllers. All are **active-high** (DT flag `0` = `GPIO_ACTIVE_HIGH`).

| LED (DT label) | Controller | Base address | Pin | Bit mask | Colour (DT) |
|---|---|---|---:|---|---|
| `led1` | MSS GPIO2 | `0x2012_2000` | 17 | `0x0002_0000` | amber |
| `led2` | MSS GPIO2 | `0x2012_2000` | 18 | `0x0004_0000` | red |
| `led3` | MSS GPIO2 | `0x2012_2000` | 19 | `0x0008_0000` | amber |
| `led4` | MSS GPIO2 | `0x2012_2000` | 20 | `0x0010_0000` | red |
| `led5` | MSS GPIO2 | `0x2012_2000` | 21 | `0x0020_0000` | amber |
| `led6` | MSS GPIO2 | `0x2012_2000` | 22 | `0x0040_0000` | red |
| `led7` | MSS GPIO2 | `0x2012_2000` | 23 | `0x0080_0000` | amber |
| `led8` | MSS GPIO1 | `0x2012_1000` | 9 | `0x0000_0200` | red |

**Board-verified:** each LED lit alone in this order (LED1 → LED8), then all eight blinked, using only the register writes below. GPIO2 is only reachable through the FPGA fabric, so the LEDs depend on the Discovery Kit **reference design (v2507)** being programmed, as the Avnet setup does. A different FPGA design can route these pins elsewhere.

**Simplest single target: LED1 = GPIO2 pin 17.** Everything needed is in one 4 KiB page at `0x2012_2000`.

### GPIO register layout (MSS GPIO, per controller)

| Offset | Register | Access | Use |
|---|---|---|---|
| `0x000 + 4·n` | `GPIO_CFG[n]` (n = 0…31) | RW | Per-pin config. Bit 0 `EN_OUT` (output register), bit 1 `EN_IN` (input register), bit 2 `EN_OUT_BUF` (drive the pad), bit 3 `EN_INT`, bits 7:5 interrupt type. **Output = `0x5`.** |
| `0x080` | `GPIO_IRQ` | RW1C | Interrupt pending bits, write 1 to clear |
| `0x084` | `GPIO_IN` | RO | Input levels (only for pins with `EN_IN`) |
| `0x088` | `GPIO_OUT` | RW | Output levels, one bit per pin |
| `0x08C` | `GPIO_CFG_ALL` | WO | Write the same config to every pin |
| `0x090`–`0x09C` | `GPIO_CFG_BYTE[0..3]` | WO | Config for 8 pins at once |
| `0x0A0` | `GPIO_CLR_BITS` | WO | Write 1s to clear those `GPIO_OUT` bits (atomic) |
| `0x0A4` | `GPIO_SET_BITS` | WO | Write 1s to set those `GPIO_OUT` bits (atomic) |

**Board-verified:** writing `0x5` to `GPIO_CFG[17]`, then `0x00020000` to `GPIO_OUT`, read back as `0x00020000` and lit LED1. `GPIO_SET_BITS` (`0xA4`) and `GPIO_CLR_BITS` (`0xA0`) set and cleared bit 17 in `GPIO_OUT`. Use set/clear in a driver, so you never read-modify-write `GPIO_OUT`: a read-modify-write can undo a change another thread made in between.

**Power-on state under U-Boot (board-verified):** every `GPIO_CFG`, `GPIO_OUT` and `GPIO_IRQ` of GPIO1 and GPIO2 reads `0`. U-Boot doesn't touch them, so seL4 starts with all LED pins configured as nothing (pad not driven, LEDs off). Your code must write `GPIO_CFG` first.

### Clock and reset: already on

Each MSS peripheral has an enable bit in `SUBBLK_CLOCK_CR` and a reset bit in `SOFT_RESET_CR`, in the MSS system registers (`mss_top_sysreg`, base `0x2000_2000`).

| Register | Address | Value under U-Boot (board-verified) |
|---|---|---|
| `SUBBLK_CLOCK_CR` | `0x2000_2084` | `0x3FFD_FFFF`: **every** peripheral clock on (bit 17 is reserved) |
| `SOFT_RESET_CR` | `0x2000_2088` | `0x0000_0000`: **nothing** held in reset |

So to drive the LEDs you **don't** need to touch these. HSS enables everything before U-Boot runs, and seL4 doesn't change it. The bit for each block is in the [master table](#5-master-table) (GPIO0 = bit 20, GPIO1 = 21, GPIO2 = 22).

### Prove it from U-Boot first (board-verified)

At `RISC-V #`, this lights LED1, turns it off again and puts the pin back to its reset state:

```text
mw.l 0x20122044 0x5          # GPIO2 CFG[17] = output (EN_OUT | EN_OUT_BUF)
mw.l 0x201220a4 0x00020000   # SET_BITS: LED1 on
mw.l 0x201220a0 0x00020000   # CLR_BITS: LED1 off
mw.l 0x20122044 0x0          # back to reset state
```

`CFG[n]` is at `base + 4·n`, so pin 17 is `0x20122000 + 0x44`. LED8 is `mw.l 0x20121024 0x5`, then `mw.l 0x20121088 0x200` (GPIO1 pin 9).

### Driving an LED from seL4

The GPIO controller is ordinary MMIO, so the root task needs a **frame capability for the 4 KiB page at `0x2012_2000`**, mapped into its address space. No IRQ is needed to blink. Steps (rust-sel4 API names):

1. Find the **device untyped** covering the address: iterate `bootinfo.untyped_list()`, pick the entry whose `[paddr(), paddr() + 2^size_bits())` contains `0x2012_2000`, and check `is_device()`. seL4 hands every non-RAM physical address to the root task as device untypeds, except the kernel's own devices.
2. **Trim** that untyped down to the target address by retyping off-cuts until the next free physical address is `0x2012_2000`, then retype one `sel4::cap_type::Granule` (4 KiB frame) at it.
3. **Map** the frame with `frame_map(VSPACE, vaddr, CapRights::read_write(), VmAttributes::default())` at a free, page-aligned virtual address.
4. Write registers with **volatile** accesses: `CFG[17] = 0x5`, then alternate `SET_BITS = 1<<17` and `CLR_BITS = 1<<17`.

rust-sel4's own [`crates/examples/root-task/serial-device`](https://github.com/seL4/rust-sel4/blob/7a2321f2d84310ba7a09fe7f5988e6dcecde3566/crates/examples/root-task/serial-device/src/main.rs) does steps 1–3 exactly (`trim_untyped`, `get_user_image_frame_slot`, `init_free_page_addr`) for a UART. Swap in the GPIO2 address and drop the IRQ part. The core of the blink, once the page is mapped at `gpio`:

```rust
// Untested sketch: register offsets are board-verified, the seL4 plumbing follows rust-sel4's serial-device example.
const CFG_OUTPUT: u32 = 0x5;          // EN_OUT | EN_OUT_BUF
const LED1: u32 = 1 << 17;            // GPIO2 pin 17
let gpio = gpio_vaddr as *mut u32;
unsafe {
    gpio.add(17).write_volatile(CFG_OUTPUT);           // GPIO_CFG[17]
    loop {
        gpio.add(0xA4 / 4).write_volatile(LED1);       // GPIO_SET_BITS: on
        delay();
        gpio.add(0xA0 / 4).write_volatile(LED1);       // GPIO_CLR_BITS: off
        delay();
    }
}
```

**Delay.** The kernel owns the CLINT timer, and this non-MCS kernel has no sleep call. Options, simplest first:

- **Busy loop**, e.g. `for _ in 0..N { core::hint::spin_loop() }`, tuned by eye. Good enough for a first test.
- **`rdtime`**: reads the 1 MHz timebase (`timebase-frequency` = 1,000,000 in the DT). Whether user mode may read `time` depends on the kernel/firmware counter-enable setup; **not tested**. If it traps, fall back to the busy loop.
- **MSS Timer** (`0x2012_5000`, Microchip memory map; not in the DT; **not checked on the board**): a free-running hardware timer you could map like the GPIO, and later use with an IRQ for real periodic scheduling.

**Isolation note.** seL4 grants device access per 4 KiB page, so the page is the smallest unit a partition can own. GPIO2's page holds all 32 GPIO2 pins: whoever holds its frame cap can drive all of them. In an APEX-style system, give each device page to exactly one partition (an I/O partition or a small GPIO server) and let other partitions reach it through ports, never by sharing the cap.

---

## 2. Candidate TALOS peripherals ◆

Which of these TALOS uses, and which partition owns each, is still open. The column below says what each block *could* serve in a partitioned system.

| Block | Address (4 KiB page) | PLIC IRQ | Clock/reset bit | DT status | Possible TALOS role |
|---|---|---|---:|---|---|
| **MSS GPIO0** | `0x2012_0000` | via GPIO mux | 20 | disabled | More GPIO (14 pins; routing to pads depends on the IOMUX/fabric design) |
| **MSS GPIO1** | `0x2012_1000` | via GPIO mux | 21 | okay | LED8 (pin 9), 24 pins |
| **MSS GPIO2** | `0x2012_2000` | via GPIO mux | 22 | okay | LED1–7 (pins 17–23), 32 pins, fabric-routed |
| **MSS Timer** | `0x2012_5000` (Microchip map; not in DT) | Microchip map | 4 | n/a | User-space deadline/timeout monitoring, without touching the kernel's CLINT. A kernel-enforced partition schedule (domain scheduler or MCS) runs on the CLINT, not on this |
| **Watchdog 1** (`wdt1`) | `0x2010_1000` | 101 (`mvrp`), 106 (`trig`) | `CLK_AHB` | okay | Health-monitor backstop: the hart-1 watchdog (seL4 runs on hart 1) |
| Watchdogs 0, 2–4 | `0x2000_1000`, `0x2010_3000`, `0x2010_5000`, `0x2010_7000` | see [§5](#5-master-table) | `CLK_AHB` | disabled | One per hart (0 = E51 monitor core) |
| **RTC** | `0x2012_4000` | 80, 81 | 18 | okay | Wall-clock time / timestamps for logs |
| **CAN0 / CAN1** | `0x2010_C000` / `0x2010_D000` | 56 / 57 | 14 / 15 | disabled | Bus I/O owned by one partition (needs pins or a transceiver on the board/fabric; unchecked) |
| **SPI0 / SPI1** | `0x2010_8000` / `0x2010_9000` | 54 / 55 | 10 / 11 | okay | Sensors/peripherals for an I/O partition |
| **I2C0** | `0x2010_A000` | 58 | 12 | okay | Sensors, EEPROMs (100 kHz in DT) |
| **CoreI2C (fabric)** | `0x4000_0200` | 122 | FIC0 (24) | okay | Second I2C in the reference design |
| **CorePWM (fabric)** | `0x4000_0000` (0xF0 bytes) | none | FIC0 (24) | okay | Dimming/PWM outputs; what its outputs connect to depends on the reference design, **unchecked** |
| **MMUART1 / UART2 / UART3** | `0x2010_0000` / `0x2010_2000` / `0x2010_4000` | 91 / 92 / 93 | 6 / 7 / 8 | okay / disabled / disabled | A user-space console or comms port for a partition (16550-compatible, 32-bit registers, `reg-shift` 2) |
| **CoreUART (fabric)** | `0x4000_0300` | 129 | FIC0 (24) | okay | Extra UART in the fabric |
| **Ethernet MAC0** | `0x2011_0000` (8 KiB) | 64–69 | 1 | okay (SGMII, PHY addr 11) | Networking partition (big job: needs DMA memory and a driver). Working under U-Boot ([network boot](flashing.md#network-boot)) |
| **Inter-hart mailbox (IHC)** | `0x5000_0000` (fabric) | 178–180 | FIC | disabled | Only if TALOS ever runs work on other harts outside seL4 |

**PLIC IRQ numbers** are the PLIC source IDs from the DT (decimal); pass them to `IrqControl::irq_control_get` to get an IRQ handler capability, then bind a notification, as rust-sel4's serial-device example does. The kernel was built with `MAX_IRQ 186`.

**GPIO interrupts** don't go to the PLIC directly. A mux in `mss_top_sysreg` at offset `0x54` (`GPIO_INTERRUPT_FAB_CR`) chooses whether PLIC lines 13–53 carry GPIO0/GPIO1 or GPIO2 interrupts. Not needed for blinking; needed for buttons or edge-triggered inputs later.

**Fabric (FPGA) peripherals** sit behind the FIC0 bridge (`0x4000_0000`–`0x5FFF_FFFF`) and FIC1 (`0x6000_0000`–`0x7FFF_FFFF`). They exist only because the reference design instantiates them, and their FIC clocks (bits 24–27) were on under U-Boot.

---

## 3. Console and serial ports

| UART | Address | PLIC IRQ | DT status | Wired to | Notes |
|---|---|---|---|---|---|
| MMUART0 | `0x2000_0000` | 90 | disabled | FT4232H interface 1 (HSS console, `>>`), **likely** | HSS on the E51 core uses it ⛔ |
| MMUART1 | `0x2010_0000` | 91 | okay | FT4232H interface 3, **likely** (silent so far) | Free for a partition |
| MMUART2 | `0x2010_2000` | 92 | disabled | not known | |
| MMUART3 | `0x2010_4000` | 93 | disabled | not known | Was avoided during bring-up |
| **MMUART4** | `0x2010_6000` | 94 | okay | FT4232H interface 2 (`ttyUSB2`, U-Boot/seL4 console), board-verified | ⛔ The firmware's SBI console (`Platform Console Device: mmuart`). seL4 prints through SBI, so don't drive it from user space |

All MMUARTs are 16550-compatible (`ns16550a`), 115200 baud in the DT, with 32-bit registers (`reg-io-width` 4, `reg-shift` 2: register *n* is at `base + 4·n`).

For printing from Rust today, keep using `sel4::debug_println!` (kernel → SBI → MMUART4).

---

## 4. Kernel- and firmware-owned blocks ⛔

| Block | Address | Why off-limits |
|---|---|---|
| CLINT | `0x0200_0000` | seL4 kernel timer and IPIs (reserved as `seL4,kernel-devices`) |
| PLIC | `0x0C00_0000` | seL4 kernel interrupt controller; user space gets IRQs through IRQ handler caps instead |
| `mss_top_sysreg` | `0x2000_2000` | Clock gates, resets, IOMUX, GPIO interrupt mux for **every** peripheral. Map it only into a trusted platform/config component, if at all |
| System controller mailbox | `0x3702_0800` (IRQ 96) | Talks to the FPGA system controller (device serial number, reprogramming); used by HSS |
| MMUART4 | `0x2010_6000` | SBI/firmware console, see above |
| SD/eMMC controller | `0x2000_8000` (IRQ 88) | Holds the SD card U-Boot boots from; a seL4 driver could reach it, but be careful not to corrupt the boot card |
| Firmware RAM | `0x8000_0000`–`0x801F_FFFF` | HSS/OpenSBI runtime; reserved in the seL4 device tree overlay |

---

## 5. Master table

Every block in the board's device tree. "Bit" is the bit in `SUBBLK_CLOCK_CR` (`0x2000_2084`) and `SOFT_RESET_CR` (`0x2000_2088`), from the Linux MPFS clock/reset drivers (clock index − 3); the live value `0x3FFD_FFFF` matches that layout, with reserved bit 17 the only zero.

| Block | Base | Size | PLIC IRQ (decimal) | Bit | DT status | Mark |
|---|---|---|---|---:|---|---|
| L2 cache controller | `0x0201_0000` | 4 KiB | 1–4 | n/a | n/a | · |
| CLINT | `0x0200_0000` | 48 KiB | n/a | n/a | n/a | ⛔ |
| PDMA (4 channels) | `0x0300_0000` | 32 KiB | 5–12 | n/a | n/a | · |
| PLIC | `0x0C00_0000` | 64 MiB | n/a | n/a | n/a | ⛔ |
| MMUART0 | `0x2000_0000` | 1 KiB | 90 | 5 | disabled | ⛔ |
| Watchdog 0 | `0x2000_1000` | 4 KiB | 100, 105 | AHB | disabled | · |
| `mss_top_sysreg` (+ GPIO IRQ mux `+0x54`, IOMUX `+0x200`, MSSIO `+0x204`) | `0x2000_2000` | 4 KiB | n/a | n/a | n/a | ⛔ |
| `sysreg_scb` | `0x2000_3000` | 4 KiB | n/a | n/a | n/a | ⛔ |
| SD/eMMC (Cadence SD4HC) | `0x2000_8000` | 4 KiB | 88 | 3 | okay | ⛔ |
| MMUART1 | `0x2010_0000` | 1 KiB | 91 | 6 | okay | ◆ |
| Watchdog 1 | `0x2010_1000` | 4 KiB | 101, 106 | AHB | okay | ◆ |
| MMUART2 | `0x2010_2000` | 1 KiB | 92 | 7 | disabled | ◆ |
| Watchdog 2 | `0x2010_3000` | 4 KiB | 102, 107 | AHB | disabled | · |
| MMUART3 | `0x2010_4000` | 1 KiB | 93 | 8 | disabled | ◆ |
| Watchdog 3 | `0x2010_5000` | 4 KiB | 103, 108 | AHB | disabled | · |
| MMUART4 | `0x2010_6000` | 1 KiB | 94 | 9 | okay | ⛔ |
| Watchdog 4 | `0x2010_7000` | 4 KiB | 105, 109 (as in DT) | AHB | disabled | · |
| SPI0 | `0x2010_8000` | 4 KiB | 54 | 10 | okay | ◆ |
| SPI1 | `0x2010_9000` | 4 KiB | 55 | 11 | okay | ◆ |
| I2C0 | `0x2010_A000` | 4 KiB | 58 | 12 | okay | ◆ |
| I2C1 | `0x2010_B000` | 4 KiB | 61 | 13 | disabled | ◆ |
| CAN0 | `0x2010_C000` | 4 KiB | 56 | 14 | disabled | ◆ |
| CAN1 | `0x2010_D000` | 4 KiB | 57 | 15 | disabled | ◆ |
| Ethernet MAC0 (SGMII, PHY 11) | `0x2011_0000` | 8 KiB | 64–69 | 1 | okay | ◆ |
| Ethernet MAC1 | `0x2011_2000` | 8 KiB | 70–75 | 2 | disabled | · |
| **GPIO0** (14 pins) | `0x2012_0000` | 4 KiB | via mux | 20 | disabled | ◆ |
| **GPIO1** (24 pins; LED8) | `0x2012_1000` | 4 KiB | via mux | 21 | okay | ★ |
| **GPIO2** (32 pins; LED1–7) | `0x2012_2000` | 4 KiB | via mux | 22 | okay | ★ |
| RTC | `0x2012_4000` | 4 KiB | 80, 81 | 18 | okay | ◆ |
| MSS Timer (Microchip map) | `0x2012_5000` | 4 KiB | Microchip map | 4 | not in DT | ◆ |
| USB OTG (MUSB) | `0x2020_1000` | 4 KiB | 86, 87 | 16 | disabled | · |
| QSPI (MSS) | `0x2100_0000` | 4 KiB | 85 | 19 | disabled | · |
| Crypto (Athena) | `0x2200_0000` | 64 KiB | 112 | 28 | disabled | · |
| System controller SCB / mailbox / QSPI | `0x3702_0000` / `0x3702_0800` / `0x3702_0100` | 256 B each | — / 96 / 110 | n/a | — / okay / disabled | ⛔ |
| Clock configuration (`clkcfg`) | `0x3E00_1000` | 4 KiB | n/a | n/a | n/a | ⛔ |
| Clock conditioning circuits (PLLs) | `0x3801_0000`, `0x3804_0000`, `0x3810_0000`, `0x3840_0000` | 4 KiB ×4 each | n/a | n/a | only `0x3840_0000` okay | ⛔ |
| CorePWM (fabric) | `0x4000_0000` | 240 B | none | FIC0 24 | okay | ◆ |
| CoreI2C (fabric) | `0x4000_0200` | 256 B | 122 | FIC0 24 | okay | ◆ |
| CoreUART (fabric) | `0x4000_0300` | 256 B | 129 | FIC0 24 | okay | ◆ |
| IHC mailbox (fabric) | `0x5000_0000` | 112 KiB | 178–180 | FIC | disabled | · |
| Fabric LSRAM (`generic-uio`) | `0x6000_0000` | 4 KiB | none | FIC1 25 | okay | · |
| FPGA DMA | `0x6001_0000` | 4 KiB | 120 | FIC1 25 | okay | · |

Watchdog clocks come from the AHB bus clock, not a gated bit. For Watchdog 4 the DT lists `0x69 0x6d` (105, 109); 105 also appears as Watchdog 0's `trig`. That is copied as-is and not checked.

---

## 6. Memory map (what seL4 sees)

| Range | What | seL4 |
|---|---|---|
| `0x8000_0000`–`0x801F_FFFF` | Firmware (HSS/OpenSBI) | reserved |
| `0x8020_0000`–`0x83FF_FFFF` | Cached DDR, 62 MiB | RAM untypeds (kernel + root task image load here) |
| `0x8400_0000`–`0x89FF_FFFF` | Fabric / reserved buffer | not RAM |
| `0x8A00_0000`–`0x91FF_FFFF` | Cached DDR, 128 MiB | RAM untypeds |
| `0xC400_0000`, `0x10_2200_0000`, `0x14_1200_0000` | Non-cached / high aliases of the same DDR | deliberately excluded by the overlay |
| everything else above | MMIO | **device untypeds** (except CLINT and PLIC) |

On the board, the Rust root task reported **50 untyped regions**: the RAM untypeds plus the device untypeds that cover the peripherals above.

---

## 7. Serial channels and board reset

USB-C connector **#1** is an FTDI FT4232H (`Microsemi Embedded FlashPro5`, USB ID `1514:2008`). Its four channels, and how the tools find them on Linux ([setup](getting-started.md#linux)):

| Channel | Console | Linux name (udev rule) | `by-id` fallback | Override |
|---|---|---|---|---|
| interface 0 | JTAG (FlashPro programming), not a console | `/dev/polarfire-jtag` | `/dev/serial/by-id/*FlashPro5*-if00-port0` | `JTAG_PORT` |
| interface 1 | HSS firmware (MMUART0, likely), `>>` prompt | `/dev/polarfire-hss` | `...-if01-port0` | `HSS_PORT` |
| interface 2 | U-Boot / Linux / seL4 (MMUART4, the SBI console) | `/dev/polarfire-uboot` | `...-if02-port0` | `UBOOT_PORT` |
| interface 3 | third UART (MMUART1, likely), silent so far | `/dev/polarfire-uart3` | `...-if03-port0` | `UART3_PORT` |

- **Never use `ttyUSB` numbers.** They follow the order the channels were bound, not the interface order: after the `new_id` fix on one host the U-Boot console stayed `/dev/ttyUSB0` and HSS became `/dev/ttyUSB2` until a replug. The tools look ports up by role in the order *override variable → udev name → `by-id` name* (`scripts/polarfire/ports.py`).
- Out of the box `ftdi_sio` binds only interface 2. [`host/udev/99-polarfire-discovery.rules`](../host/udev/99-polarfire-discovery.rules) binds all four on every plug-in (`new_id` with `1514 2008`) and creates the names above.
- **Reset without touching the board.** The HSS console stays live after boot and accepts `help`, which lists `YMODEM BOOT RESET HELP VERSION UPTIME DEBUG MEMTEST QSPI EMMC MMC SDCARD PAYLOAD SPI RESUME ECC`. `RESET` reboots the board into HSS → U-Boot; `scripts/board.py reset` and `flash` use it. Only power-cycling and SD-card swaps need someone at the board.
- **Don't use the HSS `YMODEM` command.** It writes eMMC/QSPI. Images are loaded with U-Boot's `loady` instead, into RAM only ([flashing](flashing.md)).
- U-Boot has no `usb`, `ums`, `dfu` or `fastboot`, and the SoC's USB OTG (MUSB, `0x2020_1000`) is disabled in the device tree, so the FT4232H serial link is the only USB path to the board.
- `bootdelay` is 2 s; any key during `Hit any key to stop autoboot` stops at `RISC-V #`.

## 8. Firmware compatibility

Which board firmware the TALOS seL4 images have been used with, and how sure we are of each value.

**Evidence levels**

- **Confirmed**: read directly from files at repository assembly (2026-10-20): the board-extracted device tree, or the seL4 SD card's root filesystem.
- **Historical**: recorded in the bring-up log at the time, but not re-checkable from files.
- **Untested**: no TALOS image has been run with it.

### Tested configuration (`sel4test.uImage` autoboot: 118 passed / 49 disabled)

| Component | Version | Evidence | Source of evidence |
|---|---|---|---|
| Linux4Microchip SD image | **2026.04.1** (Linux 6.18.17) | Confirmed | `/lib/modules/6.18.17-linux4microchip-2026.04.1-g7fbe4f69684d` on the seL4 card's root partition |
| U-Boot | **2025.07-linux4microchip-2026.04** | Confirmed | `u-boot,version` in [`board/discovery/discovery.dts`](../board/discovery/discovery.dts) (extracted from the running board) |
| FPGA reference design | **MPFS_DISCOVERY_KIT reference RTL v2507** | Confirmed | root `compatible = "microchip,mpfs-disco-kit-reference-rtl-v2507"` in the same DTS |
| Hart Software Services (HSS) | **0.99.53** | Historical | bring-up log ([bring-up guide §2](../history/bringup-guide.md#2-hardware-firmware-and-host)) |
| SBI implementation | spec v2.0, impl ID `0x8`, impl version `0x10002` | Historical | bring-up log |
| `boot-linux.scr` | from the 2026.04.1 image, header date 2026-04-29 | Confirmed | `boot/boot-linux.scr` (byte copy from the card) |
| U-Boot environment | `scriptaddr=0x8e000000`, `fdt_addr_r=0x8a000000`, `kernel_addr_r=0x80200000`, `bootdelay=2`, `boot_targets= mmc0 dhcp` | Confirmed (file); not confirmed as the board's live environment | `uboot.env` on the card (valid CRC) |

HSS and FPGA programming were **not** changed during the seL4 bring-up. The board already had them from the official setup.

Observed on the same board on 2026-10-21 (U-Boot console):

| Item | Value |
|---|---|
| Firmware banner before U-Boot | `OpenSBI v1.2` (runtime SBI version 2.0, `Platform Name: Microchip PolarFire(R) SoC`, `Domain1 Name: u-boot.bin`, boot hart 1) |
| U-Boot | `2025.07-linux4microchip-2026.04 (Apr 29 2026 - 08:52:30 +0000)`, `Model: Microchip PolarFire-SoC Discovery Kit`, `DRAM: 1 GiB (total 1.8 GiB)` |
| U-Boot serial loading | `loady` / `loadx` / `loadb` available; `loady` works up to 1.5 Mbaud (3 Mbaud fails). No `usb`, `ums`, `dfu` or `fastboot`, and the SoC's USB OTG is disabled in the device tree ([flashing](flashing.md)) |
| U-Boot network | `eth0: ethernet@20110000`, gigabit link, `dhcp` / `ping` / `tftpboot` available, no `wget` ([network boot](flashing.md#network-boot)) |
| `bdinfo` | `fdt_blob = 0xbf333da0`, `relocaddr = 0xbfb3b000`, boot hart 1 |

QEMU runs (QEMU 8.2.2 `virt` + built-in OpenSBI + Ubuntu U-Boot 2025.10 `qemu-riscv64_smode`) are emulation only and are recorded in [TEST_RESULTS](../reports/TEST_RESULTS.md); they are not Discovery Kit firmware.

### Other versions

Avnet's guide installs the **latest** FPGA design and Linux4Microchip release, which may be newer than the table above. **Newer releases are untested.** What could break:

- **Memory map**: both images expect seL4 RAM at `0x80000000–0x84000000` and `0x8a000000–0x92000000`, with the first 2 MiB reserved for SBI. A release that moves reserved regions or the HSS payload into those ranges could break seL4.
- **`scriptaddr`**: the manual steps and the autoboot script use `0x8e000000`.
- **SBI**: seL4 relies on HSS for SBI console, timer and HSM services (`UseRiscVOpenSBI=OFF`).
- **U-Boot commands**: the autoboot script needs `size`, `setexpr`, `fdt`, `test` and `iminfo` (all present in the tested U-Boot).
- **`fdt_high` with U-Boot ≥ 2025.10**: if a newer U-Boot environment sets `fdt_high=0xffffffffffffffff`, then `bootm 0x8e000000 - ${fdtcontroladdr}` fails with `Failed to reserve memory for fdt` (reproduced under QEMU with U-Boot 2025.10). Run `setenv fdt_high` first. The autoboot script already does this. The tested board's environment does not set `fdt_high`.

If you use a different version, record it in the table below and share the full serial log. Exact release-tag URLs for the tested versions were **not** verified. Use the official [Linux4Microchip releases](https://github.com/linux4microchip/meta-mchp/releases) and [Discovery Kit reference design releases](https://github.com/polarfire-soc/polarfire-soc-discovery-kit-reference-design/releases) pages.

### Results reported by teammates

| Date | Board / who | Linux4Microchip | U-Boot | HSS | FPGA design | Image | Result |
|---|---|---|---|---|---|---|---|
| 2026-10 (bring-up) | original board | 2026.04.1 | 2025.07-linux4microchip-2026.04 | 0.99.53 (historical) | v2507 | first image `sel4.uImage` `29d926e4…` (removed; in git history), manual `bootm` | 118 passed / 49 disabled |
| 2026-10 | original board | 2026.04.1 | 2025.07-linux4microchip-2026.04 | 0.99.53 (historical) | v2507 | `sel4test.uImage` `2c986076…` (then named `sel4-experimental.uImage`), **autoboot**, no typing | 118 passed / 49 disabled |
| 2026-10-21 | original board | 2026.04.1 | 2025.07-linux4microchip-2026.04 | n/a | v2507 | Rust root task, network boot (developer-tree build, load `0x80260000`) | `Hello from Rust on seL4!`, 50 untyped regions |
| 2026-10-28 | original board | 2026.04.1 | 2025.07-linux4microchip-2026.04 | n/a | v2507 | `sel4test.uImage` `2c986076…`, loaded into RAM by `scripts/board.py flash` (USB and `--lan`) | 118 passed / 49 disabled |
| | | | | | | | |

## Where this came from

- **Device tree:** [`board/discovery/discovery.dts`](../board/discovery/discovery.dts) (`/sys/firmware/fdt` from the running board, reference design v2507). The `leds` node gives the LED wiring; `__symbols__` gives the names (`gpio1`, `mmuart4`, …).
- **Board checks (2026-10-22, U-Boot `md`/`mw`):** `SUBBLK_CLOCK_CR`, `SOFT_RESET_CR`, GPIO1/GPIO2 register dumps, `GPIO_CFG`/`GPIO_OUT`/`SET_BITS`/`CLR_BITS` behaviour, and all eight LEDs lighting in order.
- **Register layouts:** Microchip's MSS GPIO register map (`GPIO_CFG[32]` at `0x00`, `GPIO_IN` `0x84`, `GPIO_OUT` `0x88`, `CLR_BITS` `0xA0`, `SET_BITS` `0xA4`) as used by Microchip's bare-metal driver and Linux `gpio-mpfs`; the clock/reset bit order from Linux `clk-mpfs`/`reset-mpfs`.
- **Not checked yet:** MSS Timer address, which pads/LEDs CorePWM drives, which FT4232H channel MMUART0/1 use, `rdtime` from user mode, GPIO interrupts.
