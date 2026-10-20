#!/bin/bash
#
# Configure and build sel4test for the PolarFire SoC Discovery Kit inside the
# seL4 build container (user_img-<user>, from seL4-CAmkES-L4v-dockerfiles).
#
# The repo is mounted at its host path so CMake paths are valid on both sides,
# and the container runs as the invoking user so outputs are not root-owned.
#
# Usage: board/discovery/build.sh [--reconfigure]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$REPO/build-polarfire"
IMAGE="${SEL4_DOCKER_IMAGE:-user_img-$(whoami)}"

CONFIGURE=0
if [ ! -f "$BUILD/build.ninja" ] || [ "${1:-}" = "--reconfigure" ]; then
    CONFIGURE=1
fi

mkdir -p "$BUILD"

docker run --rm -t \
    -u "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$REPO:$REPO" -w "$BUILD" \
    "$IMAGE" bash -c "
        set -e
        if [ $CONFIGURE = 1 ]; then
            ../init-build.sh \
                -DPLATFORM=polarfire \
                -DKernelPolarfireBoard=discovery \
                -DRELEASE=OFF \
                -DSMP=OFF \
                -DUseRiscVOpenSBI=OFF \
                -DElfloaderImage=uimage \
                -DLibSel4PlatSupportUseDebugPutChar=ON
        fi
        ninja
        # sel4test forces ElfloaderImage=elf for polarfire, so wrap the ELF
        # here. U-Boot 'bootm' then enters it with a0=hartid, a1=fdt.
        ../tools/seL4/cmake-tool/helpers/make-uimage \
            \$(command -v riscv64-unknown-elf-objcopy) \
            \$(command -v riscv64-unknown-elf-readelf) \
            images/sel4test-driver-image-riscv-polarfire riscv \
            images/sel4test-driver-image-riscv-polarfire.uImage
        mkimage -l images/sel4test-driver-image-riscv-polarfire.uImage
    "
