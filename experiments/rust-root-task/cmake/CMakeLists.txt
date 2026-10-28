#
# Packages a prebuilt Rust root task with the seL4 kernel using the C elfloader,
# the same loader that boots images/sel4test.uImage on the Discovery Kit.
#

cmake_minimum_required(VERSION 3.16.0)

include(settings.cmake)

project(talos-rust-hello C ASM)

find_package(seL4 REQUIRED)
find_package(elfloader-tool REQUIRED)

sel4_import_kernel()
sel4_import_libsel4()
# The elfloader links against libcpio; sel4test gets it via its util_libs import.
add_subdirectory(${project_dir}/projects/util_libs/libcpio libcpio)
elfloader_import_project()

set(RUST_ROOTSERVER "" CACHE FILEPATH "Prebuilt Rust root task ELF")
if("${RUST_ROOTSERVER}" STREQUAL "")
  message(FATAL_ERROR "Set -DRUST_ROOTSERVER=<path to Rust root task ELF>")
endif()

# DeclareRootserver() expects a CMake-built executable; the elfloader only needs
# this target and its ROOTSERVER_IMAGE property, so provide them directly.
add_custom_target(rootserver_image ALL DEPENDS elfloader)
set_property(TARGET rootserver_image PROPERTY ROOTSERVER_IMAGE "${RUST_ROOTSERVER}")
