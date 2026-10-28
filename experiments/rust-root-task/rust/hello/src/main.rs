//
// TALOS: minimal no_std Rust root task for the PolarFire SoC Discovery Kit.
//
// Based on the seL4 Rust tutorial's root-task/hello-world example
// (Copyright 2023, Colias Group, LLC, BSD-2-Clause).
//

#![no_std]
#![no_main]

use sel4_root_task::root_task;

#[root_task]
fn main(bootinfo: &sel4::BootInfoPtr) -> ! {
    sel4::debug_println!("Hello from Rust on seL4!");
    sel4::debug_println!(
        "TALOS: Rust root task running, {} untyped regions available",
        bootinfo.untyped_list().len()
    );

    sel4::init_thread::suspend_self()
}
