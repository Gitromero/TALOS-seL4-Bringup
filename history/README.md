# History

How the seL4 bring-up on the Discovery Kit actually happened, kept as a record. The guides in [docs/](../docs/) describe how to use the repository **today**; the files here describe what was done, tried and observed at the time, and may name tools and paths that have since changed (for example the former `scripts/pf`, `usb-flash.sh` and `network-flash.sh`, replaced by `scripts/board.py` on 2026-10-28).

| File | What it is |
|---|---|
| [bringup-log.md](bringup-log.md) | Dated log of the bring-up, newest entry last: what was verified on the board, when, and what was not. **Add a dated entry** when you verify or change something important. |
| [bringup-guide.md](bringup-guide.md) | The engineering narrative of the port, from the first board inspection and QEMU smoke test through the first failed and successful boots, the reproducible image, Linux consoles, the Rust root task and network boot. |
| [first-bringup/](first-bringup/README.md) | The Docker build wrapper and pre-hardware notes that produced the first image. |

Evidence for the files the repository ships (build report, test results, privacy audit) is in [reports/](../reports/), and where each file came from in [docs/provenance.md](../docs/provenance.md).
