# Third-party notices

The binary images in this repository (`images/sel4.uImage`, `experimental/images/sel4-experimental.uImage`) are built from third-party open-source software. This file reproduces the notices that the licences require to travel with binary distributions. The full licence texts are in [`LICENSES/`](LICENSES/).

**How this list was made (experimental build, 2026-10-20):** every source and header file recorded in the build's ninja dependency log (595 files) was scanned for its `SPDX-License-Identifier` and copyright lines. musl libc and the statically linked compiler runtime (`libgcc`) are built or linked outside that log and were added by hand. The verified baseline image was built from the same pinned sources and options, so the same list applies to it. This is an engineering inventory, **not legal advice**.

| Component | Where it comes from | Licence (SPDX) | Text |
|---|---|---|---|
| seL4 microkernel (in the image) | `kernel` @ `0f108291…` + TALOS patches | GPL-2.0-only (one header BSD-3-Clause) | [GPL-2.0-only](LICENSES/GPL-2.0-only.txt), [seL4 licence note](LICENSES/seL4-kernel-LICENSE.md) |
| seL4 ELF loader | `tools/seL4` @ `f1f63d93…` | GPL-2.0-only, BSD-3-Clause | [GPL-2.0-only](LICENSES/GPL-2.0-only.txt), [BSD-3-Clause](LICENSES/BSD-3-Clause.txt) |
| libsel4 | `kernel/libsel4` | BSD-2-Clause | [BSD-2-Clause](LICENSES/BSD-2-Clause.txt) |
| sel4test (test driver and tests) | `projects/sel4test` @ `b00d84fc…` + TALOS banner patch | BSD-2-Clause | [BSD-2-Clause](LICENSES/BSD-2-Clause.txt) |
| seL4_libs, sel4_projects_libs | pinned in manifest | BSD-2-Clause | [BSD-2-Clause](LICENSES/BSD-2-Clause.txt) |
| sel4runtime | pinned in manifest | BSD-2-Clause, MIT | [BSD-2-Clause](LICENSES/BSD-2-Clause.txt), [MIT](LICENSES/MIT.txt) |
| util_libs (incl. libfdt, sglib) | pinned in manifest | BSD-2-Clause; "GPL-2.0-or-later OR BSD-2-Clause" (libfdt); GPL-2.0-or-later (`libfdt/fdtget.c`); MIT | [BSD-2-Clause](LICENSES/BSD-2-Clause.txt), [GPL-2.0-or-later](LICENSES/GPL-2.0-or-later.txt), [MIT](LICENSES/MIT.txt) |
| musl libc | `projects/musllibc` @ `b0005f86…` | MIT | [musl COPYRIGHT](LICENSES/musl-COPYRIGHT.txt) |
| nanopb | `tools/nanopb` 0.4.9.1 | Zlib | [nanopb licence](LICENSES/nanopb-Zlib.txt) |
| libgcc (compiler runtime, statically linked) | GCC 14.2.0 in the toolchain container | GPL-3.0-or-later WITH GCC-exception-3.1 | The GCC Runtime Library Exception permits distributing the resulting binary under the terms of the program's own licences |
| Discovery Kit device tree (`board/discovery/discovery.dts`, `mpfs_discovery.dts`) | Decompiled from the board's Linux4Microchip firmware DT | No tag after decompilation. Upstream Microchip MPFS DTS files are "(GPL-2.0 OR MIT)", © Microchip Technology Inc. **Not confirmed for this exact blob** | [GPL-2.0](LICENSES/GPL-2.0-only.txt) / [MIT](LICENSES/MIT.txt) |

## Copyright notices

Copyright lines found in the compiled sources (BSD-2-Clause, BSD-3-Clause and MIT require these to be reproduced with binaries):

```text
Copyright 1999-2004 University of New South Wales
Copyright 2005-2014 Rich Felker, et al.
Copyright 2005-2020 Rich Felker, et al.            (musl libc)
Copyright 2006, 2012, 2014 David Gibson, IBM Corporation
Copyright 2010-2017 The Regents of the University of California
Copyright 2011 The Chromium OS Authors. All rights reserved.
Copyright 2011 Petteri Aimonen                     (nanopb)
Copyright 2012 Kim Phillips, Freescale Semiconductor
Copyright 2012 Ryan Fox
Copyright 2014, 2016 General Dynamics C4 Systems
Copyright 2014-2020 Data61, CSIRO (ABN 41 687 119 230)
Copyright 2015, 2016 Hesham Almatary
Copyright 2016 Free Electrons
Copyright 2016 NextThing Co
Copyright 2017 wonder-mice
Copyright 2017, 2020 DornerWorks
Copyright 2018 embedded brains GmbH
Copyright 2021 HENSOLDT Cyber
Copyright 2024, 2025 UNSW
Copyright 2025 Indan Zupancic
Copyright Marian Vittek                            (sglib)
```

The BSD-2-Clause, BSD-3-Clause and MIT conditions and disclaimers that apply to these notices are in [`LICENSES/`](LICENSES/).

## GPL source availability

The images contain GPL-2.0-only code (kernel, ELF loader) and one GPL-2.0-or-later file. Under GPLv2 §3, binary distribution must be accompanied by the complete corresponding source, or by an offer of it. When binaries are distributed by offering download from a designated place, offering the source from **the same place** counts as distributing it. Links to upstream repositories alone are not relied on here.

For a release, publish the archive produced by [`experimental/scripts/make-source-archive.sh`](experimental/scripts/make-source-archive.sh) **next to the binaries** (e.g. as a GitHub release asset). It contains the pristine pinned upstream sources, all TALOS patches, and the build scripts for both images. See [docs/BUILD_PROVENANCE.md](docs/BUILD_PROVENANCE.md#licensing-and-attribution) for the remaining open licensing questions.

## TALOS-authored files

The team has **not yet chosen a licence** for its own documentation and scripts (see the release blockers in [README.md](README.md#publication-status)). Patches to GPL-2.0-only kernel files are themselves GPL-2.0-only. The sel4test banner patch follows sel4test's BSD-2-Clause.
