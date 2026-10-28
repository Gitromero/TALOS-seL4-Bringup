#!/usr/bin/env bash
#
# Test scripts/install-to-boot.sh against DISPOSABLE FAT filesystem images.
# Each scenario gets a fresh 64 MiB image, attached and mounted with udisksctl
# (no root needed on a normal desktop session). Real SD cards are never used:
# every target is checked to be a loop device backed by a file in our temp dir.
#
# Usage: tests/test-installer.sh
# Requires: mkfs.vfat, udisksctl, findmnt, losetup.
set -uo pipefail
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;; esac

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$REPO/scripts/install-to-boot.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/talos-installer-test.XXXXXX")"
PASS=0; FAIL=0; LOOP=""; MNT=""

for t in mkfs.vfat udisksctl findmnt losetup; do
    command -v "$t" >/dev/null || { echo "missing $t"; exit 2; }
done

cleanup_card() {
    if [ -n "$MNT" ]; then udisksctl unmount --no-user-interaction -b "$LOOP" >/dev/null 2>&1; fi
    if [ -n "$LOOP" ]; then udisksctl loop-delete --no-user-interaction -b "$LOOP" >/dev/null 2>&1; fi
    LOOP=""; MNT=""
}
trap 'cleanup_card; rm -rf "$TMP"' EXIT

# new_card <name>: fresh FAT image with an "official" boot.scr and fitImage.
new_card() {
    cleanup_card
    local img="$TMP/$1.img"
    truncate -s 64M "$img"
    mkfs.vfat -n BOOT "$img" >/dev/null 2>&1
    LOOP="$(udisksctl loop-setup --no-user-interaction -f "$img" | sed -n 's/.* as \(\/dev\/loop[0-9]*\)\.$/\1/p')"
    [ -n "$LOOP" ] || { echo "loop-setup failed"; exit 2; }
    # Safety: the loop device must be backed by our own temp image.
    losetup -n -O BACK-FILE "$LOOP" | grep -qF "$img" || { echo "SAFETY: $LOOP not backed by $img"; exit 2; }
    MNT="$(findmnt -n -o TARGET -S "$LOOP" || true)"
    if [ -z "$MNT" ]; then
        udisksctl mount --no-user-interaction -b "$LOOP" >/dev/null
        MNT="$(findmnt -n -o TARGET -S "$LOOP")"
    fi
    cp "$REPO/boot/boot-linux.scr" "$MNT/boot.scr"
    head -c 4096 /dev/urandom > "$MNT/fitImage"
    sync
}

snapshot() { (cd "$MNT" && find . -type f -print0 | sort -z | xargs -0 sha256sum); }
sha() { sha256sum "$1" | cut -d' ' -f1; }
LINUX_SHA="$(sha "$REPO/boot/boot-linux.scr")"
AUTO_SHA="$(sha "$REPO/boot/boot-auto.scr")"
IMAGE_SHA="$(sha "$REPO/images/sel4test.uImage")"
AUTO="$REPO/boot/boot-auto.scr"

# TALOS boot scripts from the repository's first revision (the old staging
# script and the autoboot script that loaded sel4-experimental.uImage), taken
# from git history so the legacy-script guard can be tested against real bytes.
LEGACY="$TMP/legacy"; mkdir -p "$LEGACY"
ROOT_COMMIT="$(git -C "$REPO" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1 || true)"
if [ -n "$ROOT_COMMIT" ] \
    && git -C "$REPO" show "$ROOT_COMMIT:boot/boot-sel4.scr" > "$LEGACY/boot-sel4.scr" 2>/dev/null \
    && git -C "$REPO" show "$ROOT_COMMIT:experimental/boot/boot-auto.scr" > "$LEGACY/boot-auto-old.scr" 2>/dev/null; then
    HAVE_LEGACY=1
else
    HAVE_LEGACY=0
fi

# check <description> <condition...>
check() {
    local d="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); echo "  PASS  $d"
    else FAIL=$((FAIL + 1)); echo "  FAIL  $d"; fi
}
is() { [ "$(sha "$MNT/$1")" = "$2" ]; }
absent() { [ ! -e "$MNT/$1" ]; }
no_tmp() { [ -z "$(find "$MNT" -name '*.talos-tmp')" ]; }
run() { "$@" >"$TMP/out.log" 2>&1; echo $?; }
same_as() { [ "$(snapshot)" = "$1" ]; }

repo_copy() {  # independent copy of the repository for tampering
    rm -rf "$TMP/repo"; cp -a "$REPO" "$TMP/repo"; echo "$TMP/repo/scripts/install-to-boot.sh"
}

echo "== 1. fresh install"
new_card fresh
check "dry run exits 0" [ "$(run "$INSTALL" "$MNT")" = 0 ]
check "dry run wrote nothing" absent boot-linux.scr
check "apply exits 0" [ "$(run "$INSTALL" "$MNT" --apply)" = 0 ]
check "boot-linux.scr = Linux script" is boot-linux.scr "$LINUX_SHA"
check "boot.scr = autoboot script" is boot.scr "$AUTO_SHA"
check "sel4test.uImage matches" is sel4test.uImage "$IMAGE_SHA"
check "no temp files left" no_tmp

echo "== 2. reinstall"
check "second apply exits 0" [ "$(run "$INSTALL" "$MNT" --apply)" = 0 ]
check "backup still Linux script" is boot-linux.scr "$LINUX_SHA"
check "--verify exits 0" [ "$(run "$INSTALL" "$MNT" --verify)" = 0 ]
check "--verify reports image match" grep -q 'sel4test.uImage: matches' "$TMP/out.log"

echo "== 3. autoboot boot.scr with missing backup"
new_card nobackup; cp "$AUTO" "$MNT/boot.scr"; snap="$(snapshot)"
check "refuses" [ "$(run "$INSTALL" "$MNT" --apply)" != 0 ]
check "card unchanged" same_as "$snap"

echo "== 4. backup that is a TALOS script"
new_card badbackup; cp "$AUTO" "$MNT/boot-linux.scr"; snap="$(snapshot)"
check "refuses" [ "$(run "$INSTALL" "$MNT" --apply)" != 0 ]
check "card unchanged" same_as "$snap"

echo "== 5. invalid boot scripts on the card"
new_card invalidscr; printf 'not a script' > "$MNT/boot.scr"; snap="$(snapshot)"
check "garbage boot.scr refused" [ "$(run "$INSTALL" "$MNT" --apply)" != 0 ]
check "card unchanged" same_as "$snap"
new_card invalidbackup; printf 'junk' > "$MNT/boot-linux.scr"; snap="$(snapshot)"
check "garbage boot-linux.scr refused" [ "$(run "$INSTALL" "$MNT" --apply)" != 0 ]
check "card unchanged" same_as "$snap"

echo "== 6. corrupted checksum file"
new_card badsums; snap="$(snapshot)"
I2="$(repo_copy)"; sed -i '1s/^./0/' "$TMP/repo/images/SHA256SUMS"
check "wrong hash refused" [ "$(run "$I2" "$MNT" --apply)" != 0 ]
I2="$(repo_copy)"; sed -i '/sel4test.uImage/d' "$TMP/repo/images/SHA256SUMS"
check "missing entry refused" [ "$(run "$I2" "$MNT" --apply)" != 0 ]
I2="$(repo_copy)"; sed -i '1s/^\(.\{20\}\).*\(  images\)/\1\2/' "$TMP/repo/images/SHA256SUMS"
check "truncated hash refused" [ "$(run "$I2" "$MNT" --apply)" != 0 ]
I2="$(repo_copy)"; : > "$TMP/repo/images/SHA256SUMS"
check "empty checksum file refused" [ "$(run "$I2" "$MNT" --apply)" != 0 ]
check "card unchanged" same_as "$snap"

echo "== 7. CRLF checksum file (Windows checkout)"
I2="$(repo_copy)"; sed -i 's/$/\r/' "$TMP/repo/images/SHA256SUMS"
new_card crlf-guard; cp "$AUTO" "$MNT/boot.scr"; snap="$(snapshot)"
check "CRLF: autoboot boot.scr without backup still refused" [ "$(run "$I2" "$MNT" --apply)" != 0 ]
check "CRLF: card unchanged (backup not clobbered)" same_as "$snap"
new_card crlf-ok
check "CRLF: normal install succeeds" [ "$(run "$I2" "$MNT" --apply)" = 0 ]
check "CRLF: backup is the Linux script" is boot-linux.scr "$LINUX_SHA"

echo "== 8. missing or corrupted repository image"
new_card badimage; snap="$(snapshot)"
I2="$(repo_copy)"; rm "$TMP/repo/images/sel4test.uImage"
check "missing image refused" [ "$(run "$I2" "$MNT" --apply)" != 0 ]
I2="$(repo_copy)"; printf 'X' | dd of="$TMP/repo/images/sel4test.uImage" bs=1 seek=100000 conv=notrunc status=none
check "corrupted image refused" [ "$(run "$I2" "$MNT" --apply)" != 0 ]
check "card unchanged" same_as "$snap"

echo "== 9. full filesystem"
new_card full
avail=$(df --output=avail -B1 "$MNT" | tail -1)
head -c $((avail - 1048576)) /dev/zero > "$MNT/filler" 2>/dev/null; sync
check "install fails" [ "$(run "$INSTALL" "$MNT" --apply)" != 0 ]
check "boot.scr still Linux" is boot.scr "$LINUX_SHA"
check "backup is Linux script" is boot-linux.scr "$LINUX_SHA"
check "no temp files left" no_tmp
check "no partial sel4test.uImage" absent sel4test.uImage
rm -f "$MNT/filler"; sync
check "retry after freeing space succeeds" [ "$(run "$INSTALL" "$MNT" --apply)" = 0 ]
check "boot.scr now autoboot" is boot.scr "$AUTO_SHA"

echo "== 10. interrupted installation"
for stage in after-backup before-rename:sel4test.uImage after-image before-rename:boot.scr; do
    new_card "int-${stage//[:.]/-}"
    rc="$(TALOS_TEST_ABORT_AT="$stage" run "$INSTALL" "$MNT" --apply)"
    check "abort at $stage: interrupted (rc=$rc)" [ "$rc" = 99 ]
    check "abort at $stage: boot.scr still Linux" is boot.scr "$LINUX_SHA"
    check "abort at $stage: backup intact" is boot-linux.scr "$LINUX_SHA"
    check "abort at $stage: rerun succeeds" [ "$(run "$INSTALL" "$MNT" --apply)" = 0 ]
    check "abort at $stage: boot.scr now autoboot" is boot.scr "$AUTO_SHA"
    check "abort at $stage: temp files cleaned" no_tmp
done

echo "== 11. restore Linux"
check "restore exits 0" [ "$(run "$INSTALL" "$MNT" --restore-linux --apply)" = 0 ]
check "boot.scr = Linux script" is boot.scr "$LINUX_SHA"
check "backup kept" is boot-linux.scr "$LINUX_SHA"
new_card restore-nobackup; cp "$AUTO" "$MNT/boot.scr"; snap="$(snapshot)"
check "restore without backup refused" [ "$(run "$INSTALL" "$MNT" --restore-linux --apply)" != 0 ]
check "card unchanged" same_as "$snap"

if [ "$HAVE_LEGACY" = 1 ]; then
    echo "== 12. cards set up from an earlier repository revision"
    for old in boot-sel4.scr boot-auto-old.scr; do
        new_card "legacy-guard-${old%.scr}"; cp "$LEGACY/$old" "$MNT/boot.scr"; snap="$(snapshot)"
        check "$old as boot.scr, no backup: refused" [ "$(run "$INSTALL" "$MNT" --apply)" != 0 ]
        check "$old as boot.scr, no backup: card unchanged" same_as "$snap"
        new_card "legacy-backup-${old%.scr}"; cp "$LEGACY/$old" "$MNT/boot-linux.scr"; snap="$(snapshot)"
        check "$old as boot-linux.scr: refused" [ "$(run "$INSTALL" "$MNT" --apply)" != 0 ]
        check "$old as boot-linux.scr: card unchanged" same_as "$snap"
        new_card "legacy-upgrade-${old%.scr}"
        cp "$MNT/boot.scr" "$MNT/boot-linux.scr"; cp "$LEGACY/$old" "$MNT/boot.scr"
        : > "$MNT/sel4.uImage"; : > "$MNT/sel4-experimental.uImage"
        check "$old with Linux backup: upgrade succeeds" [ "$(run "$INSTALL" "$MNT" --apply)" = 0 ]
        check "$old with Linux backup: boot.scr now autoboot" is boot.scr "$AUTO_SHA"
        check "$old with Linux backup: backup still Linux" is boot-linux.scr "$LINUX_SHA"
        check "$old: --verify flags old images" [ "$(run "$INSTALL" "$MNT" --verify)" = 0 ]
        check "$old: --verify output names sel4.uImage" grep -q 'sel4.uImage: image from an earlier' "$TMP/out.log"
    done
else
    echo "== 12. skipped: repository has no git history with the earlier TALOS scripts"
fi

echo "== 13. not a FAT mount point"
mkdir -p "$TMP/plain"; cp "$REPO/boot/boot-linux.scr" "$TMP/plain/boot.scr"; : > "$TMP/plain/fitImage"
check "plain directory refused" [ "$(run "$INSTALL" "$TMP/plain" --apply)" != 0 ]
check "bad option refused" [ "$(run "$INSTALL" "$TMP/plain" --bogus)" != 0 ]
check "--verify with --apply refused" [ "$(run "$INSTALL" "$TMP/plain" --verify --apply)" != 0 ]

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
