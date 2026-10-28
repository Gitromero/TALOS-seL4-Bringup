#!/usr/bin/env bash
#
# Install TALOS seL4 files onto an official Linux4Microchip SD card's FAT boot
# partition, preserving the Linux boot script as boot-linux.scr.
#
# DRY RUN BY DEFAULT: nothing is written unless --apply is given.
# This is a convenience wrapper around the manual steps in README.md; the
# manual procedure is the reference.
#
# Usage:
#   scripts/install-to-boot.sh <boot-partition> [--apply]                 sel4test.uImage + autoboot boot.scr
#   scripts/install-to-boot.sh <boot-partition> --restore-linux [--apply] put boot-linux.scr back as boot.scr
#   scripts/install-to-boot.sh <boot-partition> --verify                  read-only: report what is on the card
#
# Safety rules enforced:
#   * boot-linux.scr (the Linux recovery script) is never overwritten or deleted.
#   * A TALOS (seL4) script is never saved as the Linux backup.
#   * Every write goes to a *.talos-tmp file first, is synced and hash-checked,
#     and only then renamed into place; boot.scr is replaced last, so an
#     interrupted run leaves a card that still boots Linux.
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;; esac

REPO="$(cd "$(dirname "$0")/.." && pwd)"

die() { echo "ERROR: $*" >&2; exit 1; }
note() { echo "$*"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

usage() {
    sed -n '/^# Usage:/,/^# Safety/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
    exit 2
}

# Test-only hook: abort at a named stage to simulate an interrupted install.
checkpoint() {
    if [ "${TALOS_TEST_ABORT_AT:-}" = "$1" ]; then
        echo "TEST HOOK: aborting at stage '$1'" >&2
        exit 99
    fi
}

# Print the expected SHA-256 for <path> from <sums-file>. Tolerates CRLF line
# endings and the '*' binary-mode marker; fails unless exactly one well-formed
# entry exists.
expected_sha() {
    local sums="$1" want="$2" out
    [ -f "$sums" ] || die "checksum file missing: $sums"
    out="$(tr -d '\r' < "$sums" | awk -v f="$want" '
        { name = $2; sub(/^\*/, "", name) }
        name == f { n++; h = $1 }
        END { if (n == 1 && h ~ /^[0-9a-f]{64}$/) print h }')"
    [ -n "$out" ] || die "no valid checksum for '$want' in $sums"
    echo "$out"
}

# Verify a repository file against its recorded hash.
check_repo_file() {
    local sums="$1" rel="$2" want
    want="$(expected_sha "$sums" "$rel")"
    [ -f "$REPO/$rel" ] || die "repository file missing: $rel"
    [ "$(sha "$REPO/$rel")" = "$want" ] || die "repository file $rel does not match its checksum; re-download"
    echo "$want"
}

# True if <file> starts with the U-Boot legacy image magic and is a script.
is_uboot_script() {
    local f="$1" hdr
    [ -f "$f" ] && [ "$(stat -c %s "$f")" -gt 72 ] || return 1
    hdr="$(od -An -tx1 -N32 "$f" | tr -d ' \n')"
    # bytes 0-3: magic 27051956; byte 30: image type (6 = script)
    [ "${hdr:0:8}" = 27051956 ] && [ "${hdr:60:2}" = 06 ]
}

# ---------------------------------------------------------------- arguments
[ $# -ge 1 ] || usage
BOOT="$1"; shift
MODE=install
APPLY=0
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        --restore-linux) [ "$MODE" = install ] || die "conflicting modes"; MODE=restore ;;
        --verify) [ "$MODE" = install ] || die "conflicting modes"; MODE=verify ;;
        -h|--help) usage ;;
        *) die "unknown option: $arg" ;;
    esac
done
[ "$MODE" != verify ] || [ "$APPLY" = 0 ] || die "--verify is read-only; do not combine with --apply"

# ------------------------------------------------- repository file hashes
SUMS="$REPO/images/SHA256SUMS"
SRC_IMAGE=images/sel4test.uImage; DST_IMAGE=sel4test.uImage
SRC_SCRIPT=boot/boot-auto.scr
SCRIPT_SHA="$(check_repo_file "$SUMS" "$SRC_SCRIPT")"
[ "$MODE" != install ] || IMAGE_SHA="$(check_repo_file "$SUMS" "$SRC_IMAGE")"
# TALOS scripts from earlier repository revisions may still be on teammates'
# cards: the staging script boot-sel4.scr and the autoboot script that loaded
# sel4-experimental.uImage. They must never be mistaken for the Linux backup.
LEGACY_TALOS_SCRIPTS=(
    8aabe37f2891eb2aabe33783cdb10aad19ecb78640d534e81a5fb89834f349fb
    d1102ea1c35f14b7a959b6c23c4b1c7e4d0cbbd4dad9274d53e30a4ad28ff399
)
TALOS_SCRIPTS=("$SCRIPT_SHA" "${LEGACY_TALOS_SCRIPTS[@]}")
is_talos_script() {
    local h; h="$(sha "$1")"
    for t in "${TALOS_SCRIPTS[@]}"; do [ "$h" = "$t" ] && return 0; done
    return 1
}

# ------------------------------------------------------ target validation
# TALOS_SKIP_FSTYPE_CHECK=1 exists only for testing against a plain directory.
[ -d "$BOOT" ] || die "not a directory: $BOOT"
BOOT="$(cd "$BOOT" && pwd -P)"
if [ "${TALOS_SKIP_FSTYPE_CHECK:-0}" != 1 ]; then
    command -v findmnt >/dev/null || die "findmnt not found; use the manual procedure"
    [ "$(findmnt -n -o TARGET --target "$BOOT")" = "$BOOT" ] \
        || die "$BOOT is not itself a mount point"
    FSTYPE="$(findmnt -n -o FSTYPE --target "$BOOT")"
    [ "$FSTYPE" = vfat ] || die "$BOOT is $FSTYPE, expected vfat (FAT boot partition)"
fi
[ -f "$BOOT/fitImage" ] || die "$BOOT/fitImage missing: wrong partition?"
[ -f "$BOOT/boot.scr" ] || die "$BOOT/boot.scr missing: wrong partition?"
is_uboot_script "$BOOT/boot.scr" || die "$BOOT/boot.scr is not a U-Boot script image; fix the card manually"

BACKUP="$BOOT/boot-linux.scr"
if [ -e "$BACKUP" ]; then
    is_uboot_script "$BACKUP" || die "boot-linux.scr exists but is not a U-Boot script; fix manually"
    ! is_talos_script "$BACKUP" || die "boot-linux.scr is a TALOS seL4 script, not a Linux backup; fix manually"
fi

describe() {
    if is_talos_script "$1"; then
        [ "$(sha "$1")" = "$SCRIPT_SHA" ] && echo "TALOS autoboot script (current)" \
                                          || echo "TALOS script from an earlier repository revision"
    else
        echo "non-TALOS script (assumed Linux)"
    fi
}

note "Target boot partition: $BOOT"
note "  boot.scr:       $(describe "$BOOT/boot.scr")"
if [ -e "$BACKUP" ]; then note "  boot-linux.scr: present, valid, not TALOS"; else note "  boot-linux.scr: absent"; fi

# ------------------------------------------------------------ verify mode
if [ "$MODE" = verify ]; then
    if [ -e "$BOOT/$DST_IMAGE" ]; then
        want="$(expected_sha "$SUMS" "$SRC_IMAGE")"
        [ "$(sha "$BOOT/$DST_IMAGE")" = "$want" ] && note "  $DST_IMAGE: matches repository" \
                                                   || note "  $DST_IMAGE: DOES NOT MATCH repository"
    else
        note "  $DST_IMAGE: absent"
    fi
    for f in sel4.uImage sel4-experimental.uImage; do
        if [ -e "$BOOT/$f" ]; then
            note "  $f: image from an earlier repository revision (unused; safe to delete)"
        fi
    done
    leftovers="$(find "$BOOT" -maxdepth 1 -name '*.talos-tmp' | wc -l)"
    [ "$leftovers" = 0 ] || note "  $leftovers leftover *.talos-tmp file(s) from an interrupted run (safe to delete)"
    exit 0
fi

[ "$APPLY" = 1 ] && note "Mode: $MODE, APPLY (files will be written)" \
                 || note "Mode: $MODE, dry run (no changes; add --apply to write)"

# Staged copy: <src> -> <dst>.talos-tmp, sync, verify, rename over <dst>, sync, verify.
stage_copy() {
    local src="$1" dst="$2" want="$3" tmp="$2.talos-tmp"
    note "  + $src -> $dst (staged via ${tmp##*/})"
    [ "$APPLY" = 1 ] || return 0
    rm -f "$tmp"
    cp "$src" "$tmp" || { rm -f "$tmp"; die "copy to $tmp failed (card unchanged apart from removed temp file)"; }
    sync
    [ "$(sha "$tmp")" = "$want" ] || { rm -f "$tmp"; die "verification of $tmp failed"; }
    checkpoint "before-rename:${dst##*/}"
    mv -f "$tmp" "$dst"
    sync
    [ "$(sha "$dst")" = "$want" ] || die "verification of $dst failed after rename"
}

# Remove temp files left by an interrupted earlier run (only our own names).
for t in "$BOOT"/*.talos-tmp; do
    [ -e "$t" ] || continue
    note "Removing leftover ${t##*/} from an earlier interrupted run"
    [ "$APPLY" = 1 ] && rm -f "$t"
done

# ----------------------------------------------------------- restore mode
if [ "$MODE" = restore ]; then
    [ -e "$BACKUP" ] || die "no boot-linux.scr on the card; restore manually from repository boot/boot-linux.scr (see docs/troubleshooting.md#restore-linux-boot)"
    stage_copy "$BACKUP" "$BOOT/boot.scr" "$(sha "$BACKUP")"
    [ "$APPLY" = 1 ] && note "Done. boot.scr is the Linux script again. Unmount/eject before removing the card." \
                     || note "Dry run complete. Nothing was changed."
    exit 0
fi

# ----------------------------------------------------------- install modes
# 1) Linux backup: created once, from a non-TALOS boot.scr, never overwritten.
if [ -e "$BACKUP" ]; then
    note "Backup boot-linux.scr already exists; it will not be touched."
elif is_talos_script "$BOOT/boot.scr"; then
    die "boot.scr is already a TALOS script but no boot-linux.scr backup exists; restore the Linux script first (docs/troubleshooting.md#restore-linux-boot)"
else
    note "Backing up current boot.scr as boot-linux.scr:"
    stage_copy "$BOOT/boot.scr" "$BACKUP" "$(sha "$BOOT/boot.scr")"
fi
checkpoint after-backup

# 2) Image first, boot script last: until the final rename the card still boots
#    whatever boot.scr it had before.
note "Installing sel4test files:"
stage_copy "$REPO/$SRC_IMAGE" "$BOOT/$DST_IMAGE" "$IMAGE_SHA"
checkpoint after-image
stage_copy "$REPO/$SRC_SCRIPT" "$BOOT/boot.scr" "$SCRIPT_SHA"

if [ "$APPLY" = 1 ]; then
    note "Done. Hashes on the card match. Unmount/eject the card before removing it."
    note "Optional: re-mount and run '$0 <boot-partition> --verify' to re-check from the card."
else
    note "Dry run complete. Nothing was changed."
fi
