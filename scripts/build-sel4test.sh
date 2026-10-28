#!/usr/bin/env bash
#
# Build the TALOS seL4/sel4test image (images/sel4test.uImage) for the
# PolarFire SoC Discovery Kit from clean, pinned upstream sources plus this
# repository's patches. Never touches an existing seL4 checkout.
#
# Usage:
#   scripts/build-sel4test.sh <new-empty-work-dir> [--update-repo]
#
# Requirements: git, repo (Google repo launcher), docker, network access to
# github.com. The toolchain container is pulled by digest (about 10 GB).
#
# Outputs land in <work-dir>/out/. With --update-repo they are also copied
# into images/ and boot/ in this repository and images/SHA256SUMS is
# regenerated.
#
# The patched checkout stays in <work-dir>/sel4test; rust-root-task/build.sh
# uses it to build the Rust root task against the same kernel.
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;; esac

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST_URL=https://github.com/seL4/sel4test-manifest.git
MANIFEST_SHA=11c9090d597e20d9a39474ec94be9f33f2964d6b
# Generic upstream seL4 build image (not a per-user image), pinned by digest.
TOOLCHAIN_IMAGE="${TALOS_TOOLCHAIN_IMAGE:-trustworthysystems/camkes@sha256:77dcf9c7927c138d88434d812d8bd8b86455f9418d0895682250745b192e291e}"
# Fixed timestamp (manifest commit time, 2026-09-22 16:02:56 UTC) for uImage
# and script headers, so rebuilds are byte-comparable.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1790092976}"
# The checkout is mounted at this generic path inside the container, and
# compiler prefix maps strip it, so no host path can reach the binaries.
CPATH_IN=/build/sel4test

die() { echo "ERROR: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: $0 <new-empty-work-dir> [--update-repo]"
WORK="$1"
UPDATE_REPO=0
[ "${2:-}" = "" ] || [ "${2:-}" = --update-repo ] || die "unknown option: $2"
[ "${2:-}" = --update-repo ] && UPDATE_REPO=1
for t in git repo docker sha256sum; do command -v "$t" >/dev/null || die "$t not found"; done
if [ -e "$WORK" ] && [ -n "$(ls -A "$WORK")" ]; then die "$WORK exists and is not empty"; fi
mkdir -p "$WORK/sel4test" "$WORK/out"
WORK="$(cd "$WORK" && pwd)"
SRC="$WORK/sel4test"

echo "== 1. Fetch pinned sources"
(cd "$SRC" && repo init -q -u "$MANIFEST_URL" -b "$MANIFEST_SHA" --no-repo-verify && repo sync -q -c -j8 --no-clone-bundle)
cmp -s "$SRC/.repo/manifests/default.xml" "$REPO/source/sel4test-manifest-pinned.xml" \
    || die "fetched manifest differs from source/sel4test-manifest-pinned.xml"
# Every project must sit exactly at the revision the manifest pins.
(cd "$SRC" && repo forall -c 'test "$(git rev-parse HEAD)" = "$REPO_RREV" || { echo "$REPO_PATH not at $REPO_RREV" >&2; exit 1; }') \
    || die "a project is not at its pinned revision"
(cd "$SRC" && repo forall -c 'echo "$REPO_PATH $(git rev-parse HEAD)"') > "$WORK/out/source-revisions.txt"

echo "== 2. Apply patches"
git -C "$SRC/kernel" apply --whitespace=nowarn "$REPO/patches/kernel/0001-polarfire-add-discovery-kit-board.patch"
git -C "$SRC/projects/sel4test" apply --whitespace=nowarn "$REPO/patches/sel4test/0001-sel4test-driver-talos-banner.patch"

echo "== 3. Build in container $TOOLCHAIN_IMAGE"
docker run --rm \
    -u "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH \
    -v "$SRC:$CPATH_IN" -v "$REPO/boot:/talos-boot:ro" -w "$CPATH_IN" \
    "$TOOLCHAIN_IMAGE" bash -euo pipefail -c "
        mkdir -p build && cd build
        MAP='-ffile-prefix-map=$CPATH_IN/='
        ../init-build.sh -G Ninja \
            -DPLATFORM=polarfire \
            -DKernelPolarfireBoard=discovery \
            -DRELEASE=OFF \
            -DSMP=OFF \
            -DUseRiscVOpenSBI=OFF \
            -DElfloaderImage=uimage \
            -DLibSel4PlatSupportUseDebugPutChar=ON \
            -DCMAKE_C_FLAGS=\"\$MAP\" \
            -DCMAKE_CXX_FLAGS=\"\$MAP\" \
            -DCMAKE_ASM_FLAGS=\"\$MAP\" > ../configure.log
        ninja > ../ninja.log
        # sel4test forces ElfloaderImage=elf for polarfire; wrap it as a
        # legacy uImage (load = entry = ELF entry) exactly as the original bring-up build did.
        ../tools/seL4/cmake-tool/helpers/make-uimage \
            \$(command -v riscv64-unknown-elf-objcopy) \
            \$(command -v riscv64-unknown-elf-readelf) \
            images/sel4test-driver-image-riscv-polarfire riscv \
            images/sel4test-driver-image-riscv-polarfire.uImage
        mkimage -A riscv -O linux -T script -C none -n '' \
            -d /talos-boot/boot-auto.cmd images/boot-auto.scr > /dev/null
        grep -E '^(PLATFORM|KernelPolarfireBoard|RELEASE|SMP|UseRiscVOpenSBI|ElfloaderImage|LibSel4PlatSupportUseDebugPutChar|CMAKE_BUILD_TYPE|KernelPrinting|KernelDebugBuild|KernelMaxNumNodes|Sel4testHaveTimer|Sel4testHaveCache|CMAKE_C_FLAGS):' CMakeCache.txt > ../cmake-settings.txt
        riscv64-unknown-elf-gcc --version | head -1 > ../toolchain.txt
    "

echo "== 4. Collect outputs"
B="$SRC/build/images"
cp "$B/sel4test-driver-image-riscv-polarfire.uImage" "$WORK/out/sel4test.uImage"
cp "$B/sel4test-driver-image-riscv-polarfire" "$WORK/out/sel4test.elf"
cp "$B/boot-auto.scr" "$WORK/out/boot-auto.scr"
cp "$SRC/cmake-settings.txt" "$SRC/toolchain.txt" "$WORK/out/"
(cd "$WORK/out" && sha256sum sel4test.uImage sel4test.elf boot-auto.scr | tee SHA256SUMS)

if [ "$UPDATE_REPO" = 1 ]; then
    echo "== 5. Update repository images/ and boot/ artifacts"
    cp "$WORK/out/sel4test.uImage" "$REPO/images/sel4test.uImage"
    cp "$WORK/out/boot-auto.scr" "$REPO/boot/boot-auto.scr"
    (cd "$REPO" && sha256sum images/sel4test.uImage boot/boot-auto.scr boot/boot-linux.scr \
        > images/SHA256SUMS && cat images/SHA256SUMS)
fi
echo "Build complete: $WORK/out"
