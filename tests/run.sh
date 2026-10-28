#!/usr/bin/env bash
#
# Run every offline check: no board, network or root needed.
#
#   1. Python unit tests (tests/test_*.py): the flash sequence against a
#      simulated U-Boot, the serial-share broker on a pseudo-terminal, port
#      lookup, TFTP staging, every tool's command line, repository hygiene
#      (links, permissions, stale names, privacy, image hashes).
#   2. shellcheck on the shell scripts, if shellcheck is installed.
#   3. tests/test-installer.sh (SD-card installer on disposable FAT images),
#      if mkfs.vfat and udisksctl are installed.
#
# Usage: tests/run.sh
# Exit status: 0 if everything that ran passed. Skipped steps are listed.
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;; esac

REPO="$(cd "$(dirname "$0")/.." && pwd)"
failed=() skipped=()

echo "== Python unit tests"
python3 -B -m unittest discover -s "$REPO/tests" -t "$REPO/tests" || failed+=(unittest)

echo "== shellcheck"
if command -v shellcheck >/dev/null; then
    (cd "$REPO" && git ls-files -co --exclude-standard '*.sh' | xargs shellcheck -S warning) \
        && echo "ok" || failed+=(shellcheck)
else
    skipped+=("shellcheck (not installed)")
fi

echo "== SD-card installer"
if command -v mkfs.vfat >/dev/null && command -v udisksctl >/dev/null; then
    "$REPO/tests/test-installer.sh" || failed+=(test-installer)
else
    skipped+=("tests/test-installer.sh (needs mkfs.vfat and udisksctl)")
fi

echo
for s in "${skipped[@]+"${skipped[@]}"}"; do echo "skipped: $s"; done
if ((${#failed[@]})); then
    echo "FAILED: ${failed[*]}"
    exit 1
fi
echo "all checks that ran passed"
