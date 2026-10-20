# Privacy audit

**Date:** 2026-10-20 · **Tool:** [`../scripts/privacy_audit.py`](../scripts/privacy_audit.py) · **Machine-readable results:** [`privacy-audit.json`](privacy-audit.json)

Re-run with:

```bash
python3 -I experimental/scripts/privacy_audit.py experimental/images/sel4-experimental.uImage \
  experimental/boot/boot-auto.scr images/sel4.uImage boot/boot-sel4.scr boot/boot-linux.scr \
  board/discovery/discovery.dtb --json experimental/reports/privacy-audit.json
```

## Method

For each file, the tool extracts every printable string of 4 or more characters and checks it for:

- the build host's **username**, **home directory** and **hostname**, searched literally (reported only as `<user>`, `<home>`, `<hostname>`, so the report itself leaks nothing)
- **absolute paths** under common roots (`/home`, `/root`, `/Users`, `/build`, `/tmp`, `/media`, …)
- **email addresses**, **IPv4 addresses**, textual **MAC addresses**
- secret-like words (`password`, `token`, `api_key`, private-key headers, GitHub/AWS key prefixes)

It also locates every embedded **flattened device tree**, validates it with `dtc`, and lists its `local-mac-address` values and any unique-ID properties (`serial-number`, `kaslr-seed`, `rng-seed`, `board-serial`). The ELF before wrapping (not shipped) and the U-Boot scripts were also checked by hand with `strings`. The DTB inside both images was decompiled and diffed.

## Results

| File | User / home / host | Absolute paths | Email / IPv4 / MAC text | Embedded DTB MAC | Secret-like |
|---|---|---|---|---|---|
| `experimental/images/sel4-experimental.uImage` | **0 / 0 / 0** | 0, plus 1 toolchain path (below) | 0 / 0 / 0 | **all zero** | 1: the word "token" in `Failed to allocate memory for ack token` (sel4test message) |
| ELF before wrapping (not shipped) | 0 / 0 / 0 | 0, plus 1 toolchain path | 0 / 0 / 0 | all zero | same "token" message |
| `experimental/boot/boot-auto.scr` | 0 / 0 / 0 | 0 | 0 / 0 / 0 | n/a | 0 |
| `images/sel4.uImage` (**verified baseline**) | **0 / 594 / 0**; the username appears 594 times, as part of the home path | **253 distinct** paths under the developer's home | 0 / 0 / 0 | **`00 04 a3 6d f8 11`** | same "token" message |
| `boot/boot-sel4.scr`, `boot/boot-linux.scr` | 0 / 0 / 0 | 0 | 0 / 0 / 0 | n/a | 0 |
| `board/discovery/discovery.dtb` (baseline source) | 0 / 0 / 0 | 0 | 0 / 0 / 0 | **`00 04 a3 6d f8 11`** | 0 |

**Toolchain path:** `/build/reproducible-path/gcc-riscv64-unknown-elf-19/build/riscv64-unknown-elf/libgcc`. This is the build directory of the upstream Debian-built cross compiler, baked into its prebuilt `libgcc`. It is the same in every build made with this toolchain, including the baseline. It identifies the toolchain, not any TALOS machine.

**Source-path form in the experimental image:** 591 strings are relative paths such as `kernel/include/machine.h` and `build/kernel/generated/…`, produced by `-ffile-prefix-map=/build/sel4test/=`. They contain no host information.

## What was removed (experimental build only)

| Item | How | Effect |
|---|---|---|
| Developer home path and username in about 600 assertion/debug strings | Built in a generic container path, with compiler prefix maps removing it | None at run time. Assertion messages show `kernel/…` instead of absolute paths. |
| Board MAC `00:04:a3:6d:f8:11` in the kernel DTS and embedded DTB | [`0002-mpfs-discovery-zero-board-mac.patch`](../patches/kernel/0002-mpfs-discovery-zero-board-mac.patch) sets it to zeros, matching the board's second, unused MAC node | **None for seL4/sel4test**, which never touch Ethernet. Linux, U-Boot and HSS use their own device trees, so the board's networking under Linux is unaffected. A future seL4 network driver must obtain a real MAC elsewhere. |

The DTS was **not** replaced by an upstream device tree. The upstream Linux `mpfs-disco-kit.dts` describes memory as one 1 GiB bank (`memory@80000000`, size `0x40000000`) with an HSS region at `0xbfc00000`. The verified seL4 configuration depends on the firmware's actual carve-outs (`0x80000000`+64 MiB, `0x8a000000`+128 MiB, the alias windows the overlay deletes). Switching sources would change the memory map that was verified on hardware. Only the board-unique value was removed. Every other property was kept, including `u-boot,version` and `bootargs`, which are generic release strings rather than identifiers.

## What remains

- **Verified baseline:** `images/sel4.uImage` still contains the developer's home path and username (594 occurrences) and the board MAC. `board/discovery/discovery.dts/.dtb` and `patches/kernel/0001-…` contain the MAC. These files are kept byte-for-byte as the verified recovery baseline and **are not sanitized**.
- **Experimental image:** device identity data generic to the board model remains (compatible strings, the reference-design version `v2507`, the U-Boot version string, and Linux `bootargs`). No serial numbers, seeds, unique IDs, IP addresses or credentials were found.

## Conclusion

Within the scope of these checks, the experimental image and autoboot script contain **no username, home directory, hostname, host-specific absolute path, IP address, email address, credential or board-unique MAC**. This is evidence from pattern and string scanning plus device-tree inspection, not a formal proof. Data stored in a form these checks can't see, such as compressed or encoded data, was not separately analysed; the image contains no compressed sections, since the ELF loader payload is an uncompressed CPIO archive. The verified baseline is **not** sanitized and must not be described as such.
