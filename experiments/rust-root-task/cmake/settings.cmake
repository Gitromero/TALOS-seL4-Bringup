#
# Kernel + elfloader settings for the TALOS Rust root task image.
#
# Reuses a patched sel4test checkout (kernel, seL4_tools, util_libs) so the
# kernel is configured the same way as images/sel4test.uImage. Pass it with
# -DSEL4TEST_DIR=<work-dir>/sel4test (the checkout scripts/build-sel4test.sh
# leaves behind); experiments/rust-root-task/build.sh does this.
#

cmake_minimum_required(VERSION 3.16.0)

if(NOT SEL4TEST_DIR)
  message(FATAL_ERROR "Set -DSEL4TEST_DIR=<patched sel4test checkout>")
endif()
set(project_dir "${SEL4TEST_DIR}")
list(APPEND CMAKE_MODULE_PATH ${project_dir}/kernel ${project_dir}/tools/seL4/cmake-tool/helpers/
     ${project_dir}/tools/seL4/elfloader-tool/)

set(OPENSBI_PATH "${project_dir}/tools/opensbi" CACHE STRING "OpenSBI Folder location")

include(application_settings)

set(PLATFORM "polarfire" CACHE STRING "Platform")
set(KernelSel4Arch "riscv64" CACHE STRING "")
correct_platform_strings()

find_package(seL4 REQUIRED)
sel4_configure_platform_settings()

# Same choices as scripts/build-sel4test.sh: debug kernel with printing,
# single core, no OpenSBI (HSS provides SBI), plain ELF elfloader.
ApplyCommonReleaseVerificationSettings(OFF OFF)
set(KernelPolarfireBoard "discovery" CACHE STRING "" FORCE)
set(KernelMaxNumNodes 1 CACHE STRING "" FORCE)
set(KernelIsMCS OFF CACHE BOOL "" FORCE)
set(KernelNumDomains 1 CACHE STRING "" FORCE)
set(UseRiscVOpenSBI OFF CACHE BOOL "" FORCE)
set(ElfloaderImage "elf" CACHE STRING "" FORCE)
