# First bring-up

Files from the original developer seL4 checkout (`sel4test/board/discovery/`), kept as a record. Neither is used by the current tools.

| File | Notes |
|---|---|
| `build.sh` | Docker build wrapper that produced the first image (`sel4.uImage`, since removed; see git history). Copied unchanged. It only works from inside a sel4test checkout (it uses `../..` as the checkout root and writes `build-polarfire/`) and a per-user container image `user_img-$(whoami)` unless `SEL4_DOCKER_IMAGE` is set. The current, reproducible build is [`scripts/build-sel4test.sh`](../../scripts/build-sel4test.sh). |
| `bringup-notes.md` | Original pre-hardware progress log, with the local username replaced by `<user>`. Its "Hardware test results: (none yet)" predates the successful board run recorded in [the bring-up guide](../bringup-guide.md). |

The board's device tree from the same directory is still in use: [board/discovery/](../../board/discovery/README.md).
