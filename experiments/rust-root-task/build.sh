#!/usr/bin/env bash
#
# Build the TALOS Rust root task image for the PolarFire SoC Discovery Kit.
#
#   1. Configure + build the seL4 kernel (and libsel4 headers) from a patched
#      sel4test checkout, with the same settings as images/sel4test.uImage.
#   2. Build the no_std Rust root task (rust/hello) against those headers.
#   3. Package kernel + root task with the C elfloader and wrap it as a uImage.
#
# Usage:
#   experiments/rust-root-task/build.sh <sel4test-checkout> [--reconfigure]
#
#   <sel4test-checkout> is the patched checkout scripts/build-sel4test.sh
#   leaves in <work-dir>/sel4test.
#
# Output: experiments/rust-root-task/build/images/rust-hello.uImage
#
# Requirements: docker, the pinned seL4 toolchain image (see docs/building.md) and
# a local sel4-rust-tutorial:latest image (see experiments/rust-root-task/README.md).
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;; esac

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build"
C_IMAGE="${TALOS_TOOLCHAIN_IMAGE:-trustworthysystems/camkes@sha256:77dcf9c7927c138d88434d812d8bd8b86455f9418d0895682250745b192e291e}"
RUST_IMAGE="${TALOS_RUST_IMAGE:-sel4-rust-tutorial:latest}"
ROOTSERVER="$BUILD/rust/hello.elf"
OUT="$BUILD/images/rust-hello"

die() { echo "ERROR: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: $0 <sel4test-checkout> [--reconfigure]"
[ -d "$1/kernel" ] && [ -d "$1/tools/seL4" ] || die "$1 is not a sel4test checkout"
SEL4TEST="$(cd "$1" && pwd)"
grep -q discovery "$SEL4TEST/kernel/src/plat/polarfire/config.cmake" \
    || die "$SEL4TEST/kernel lacks the Discovery Kit patch (patches/kernel/0001)"
[ "${2:-}" = "" ] || [ "${2:-}" = --reconfigure ] || die "unknown option: $2"
if [ "${2:-}" = --reconfigure ]; then
    rm -rf "$BUILD"
fi
mkdir -p "$BUILD"

run_c() {
    docker run --rm \
        -u "$(id -u):$(id -g)" -e HOME=/tmp \
        -v "$HERE:$HERE" -v "$SEL4TEST:$SEL4TEST:ro" -w "$BUILD" \
        "$C_IMAGE" bash -euo pipefail -c "$1"
}

echo "== [1/3] seL4 kernel + libsel4 headers"
if [ ! -f "$BUILD/build.ninja" ]; then
    run_c "cmake -G Ninja -DSEL4TEST_DIR=$SEL4TEST -DRUST_ROOTSERVER=$ROOTSERVER \
        -C ../cmake/settings.cmake ../cmake > cmake.log"
fi
run_c "ninja kernel.elf libsel4.a > ninja-kernel.log"

echo "== [2/3] Rust root task"
K="$SEL4TEST/kernel/libsel4"
INC="$K/include:$K/arch_include/riscv:$K/sel4_arch_include/riscv64"
INC="$INC:$K/sel4_plat_include/polarfire:$K/mode_include/64"
INC="$INC:$BUILD/libsel4/include:$BUILD/libsel4/arch_include/riscv"
INC="$INC:$BUILD/libsel4/sel4_arch_include/riscv64:$BUILD/libsel4/autoconf"
INC="$INC:$BUILD/libsel4/gen_config:$BUILD/kernel/gen_config"
docker run --rm \
    -v "$HERE:$HERE" -v "$SEL4TEST:$SEL4TEST:ro" -w "$HERE/rust" \
    -e SEL4_INCLUDE_DIRS="$INC" \
    "$RUST_IMAGE" bash -c "
        cargo build --release -p hello \
            --target-dir $BUILD/rust/target --artifact-dir $BUILD/rust"

echo "== [3/3] elfloader image + uImage"
run_c "
    ninja > ninja-image.log
    mkdir -p images
    cp elfloader/elfloader $OUT.elf
    # Same wrapping as scripts/build-sel4test.sh: U-Boot 'bootm' enters the
    # elfloader with a0=hartid, a1=fdt.
    $SEL4TEST/tools/seL4/cmake-tool/helpers/make-uimage \
        \$(command -v riscv64-unknown-elf-objcopy) \
        \$(command -v riscv64-unknown-elf-readelf) \
        $OUT.elf riscv $OUT.uImage
    mkimage -l $OUT.uImage
"
sha256sum "$OUT.uImage"
