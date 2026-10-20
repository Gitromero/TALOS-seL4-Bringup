# TALOS experimental seL4 autoboot CANDIDATE -- NOT verified on a physical board.
# Loads sel4-experimental.uImage, validates image and U-Boot's own device tree,
# checks for memory overlap, then runs bootm with no user interaction.
# On any failed check it falls back to the Linux script boot-linux.scr.
echo === TALOS experimental seL4 autoboot (candidate, not hardware-verified) ===
setenv talos_img sel4-experimental.uImage
setenv talos_addr 0x8e000000
setenv talos_ok 1
if test -z "${devtype}"; then setenv devtype mmc; fi
if test -z "${devnum}"; then setenv devnum 0; fi
if test -z "${distro_bootpart}"; then setenv distro_bootpart 1; fi

# 1. Device tree: fdtcontroladdr is the same value bdinfo prints as fdt_blob.
if test -z "${fdtcontroladdr}"; then
    echo TALOS: fdtcontroladdr is not set
    setenv talos_ok 0
elif fdt addr ${fdtcontroladdr}; then
    fdt header get talos_fdt_size totalsize
    echo TALOS: FDT at 0x${fdtcontroladdr}, 0x${talos_fdt_size} bytes
else
    echo TALOS: no valid FDT at 0x${fdtcontroladdr}
    setenv talos_ok 0
fi

# 2. Image size and overlap check before anything is loaded.
if test ${talos_ok} = 1; then
    if size ${devtype} ${devnum}:${distro_bootpart} ${talos_img}; then
        setexpr talos_end ${talos_addr} + ${filesize}
        setexpr talos_fdt_end ${fdtcontroladdr} + ${talos_fdt_size}
        if test 0x${talos_end} -le 0x${fdtcontroladdr}; then
            echo TALOS: image range ends below FDT
        elif test 0x${talos_fdt_end} -le ${talos_addr}; then
            echo TALOS: FDT ends below image range
        else
            echo TALOS: image range overlaps the FDT
            setenv talos_ok 0
        fi
    else
        echo TALOS: ${talos_img} not found
        setenv talos_ok 0
    fi
fi

# 3. Load and verify the image (iminfo checks header and data CRC).
if test ${talos_ok} = 1; then
    if load ${devtype} ${devnum}:${distro_bootpart} ${talos_addr} ${talos_img}; then
        if iminfo ${talos_addr}; then
            # Let bootm copy the FDT to free memory (the path the board's saved
            # environment takes: it has no fdt_high). fdt_high=all-ones would mean
            # "use in place", which U-Boot >= 2025.10 rejects because U-Boot itself
            # reserves the control FDT's memory. RAM-only change, never saved.
            setenv fdt_high
            echo TALOS: booting seL4 with FDT 0x${fdtcontroladdr}
            bootm ${talos_addr} - ${fdtcontroladdr}
            echo TALOS: bootm returned
        else
            echo TALOS: image check failed
        fi
    else
        echo TALOS: load failed
    fi
fi

# 4. Fallback: hand over to the Linux boot script if it is there.
echo TALOS: seL4 not started, trying boot-linux.scr
if load ${devtype} ${devnum}:${distro_bootpart} ${talos_addr} boot-linux.scr; then
    source ${talos_addr}
    echo TALOS: boot-linux.scr returned without booting Linux
else
    echo TALOS: boot-linux.scr not found, no fallback available
fi
