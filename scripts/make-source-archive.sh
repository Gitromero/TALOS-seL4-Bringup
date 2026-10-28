#!/usr/bin/env bash
#
# Create the "corresponding source" archive for the seL4 image distributed in
# this repository (GPL-2.0-only kernel plus BSD/MIT user-level code).
#
# The archive contains:
#   upstream/<path>/   pristine sources of every project at the pinned SHA
#                      (git archive of the exact manifest revision, no .git)
#   talos/             this repository's patches, board files, build scripts,
#                      pinned manifest, boot script sources and license texts
#   SOURCE-README.txt  how the pieces fit together
#
# Usage: scripts/make-source-archive.sh <synced-sel4test-checkout> <output-dir>
#   <synced-sel4test-checkout> is a `repo` checkout at the pinned manifest, e.g.
#   the <work-dir>/sel4test created by build-sel4test.sh. Local patches
#   applied there do not matter: only committed HEADs are archived.
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;; esac

REPO="$(cd "$(dirname "$0")/.." && pwd)"
die() { echo "ERROR: $*" >&2; exit 1; }
[ $# -eq 2 ] || die "usage: $0 <synced-sel4test-checkout> <output-dir>"
SRC="$(cd "$1" && pwd)"
OUT="$2"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1790092976}"
NAME=talos-sel4-bringup-corresponding-source
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME/upstream" "$STAGE/$NAME/talos"

cmp -s "$SRC/.repo/manifests/default.xml" "$REPO/source/sel4test-manifest-pinned.xml" \
    || die "checkout manifest differs from source/sel4test-manifest-pinned.xml"

# Pristine upstream trees at the pinned revisions, plus the repo linkfiles.
(cd "$SRC" && repo forall -c 'test "$(git rev-parse HEAD)" = "$REPO_RREV" || exit 1; echo "$REPO_PATH $REPO_RREV"') \
    > "$STAGE/$NAME/upstream/REVISIONS.txt" || die "a project is not at its pinned revision"
while read -r path rev; do
    mkdir -p "$STAGE/$NAME/upstream/$path"
    git -C "$SRC/$path" archive --format=tar "$rev" | tar -x -C "$STAGE/$NAME/upstream/$path"
done < "$STAGE/$NAME/upstream/REVISIONS.txt"
cp "$REPO/source/sel4test-manifest-pinned.xml" "$STAGE/$NAME/upstream/manifest.xml"

for d in patches board source boot scripts LICENSES; do
    mkdir -p "$STAGE/$NAME/talos/$(dirname "$d")"
    cp -a "$REPO/$d" "$STAGE/$NAME/talos/$d"
done
rm -f "$STAGE/$NAME/talos/boot/"*.scr
cp "$REPO/THIRD_PARTY_NOTICES.md" "$STAGE/$NAME/talos/"

cat > "$STAGE/$NAME/SOURCE-README.txt" <<'EOF'
Corresponding source for the TALOS seL4 Discovery Kit image
(images/sel4test.uImage).

upstream/   Unmodified sources at the revisions in upstream/REVISIONS.txt,
            laid out as the `repo` checkout described by upstream/manifest.xml.
            Recreate the top-level links that repo creates:
              ln -s tools/seL4/cmake-tool/init-build.sh init-build.sh
              ln -s tools/seL4/cmake-tool/griddle griddle
              ln -s projects/sel4test/easy-settings.cmake easy-settings.cmake
talos/      TALOS changes and build scripts:
              patches/kernel/0001-*.patch       (Discovery Kit board support, board MAC zeroed)
              patches/sel4test/0001-*.patch     (TALOS banner)
              scripts/build-sel4test.sh         (the build that produced the image)
            Apply patches with `git apply` or `patch -p1` inside the named
            project directory, then build as described in the scripts.
Licenses: see talos/THIRD_PARTY_NOTICES.md and talos/LICENSES/, and the
LICENSE*/LICENSES files inside each upstream project.
EOF

# Deterministic tarball: sorted names, fixed owner and mtime.
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$SOURCE_DATE_EPOCH" \
    -C "$STAGE" -cf - "$NAME" | xz -9 -T1 > "$OUT/$NAME.tar.xz"
(cd "$OUT" && sha256sum "$NAME.tar.xz" | tee "$NAME.tar.xz.sha256")
