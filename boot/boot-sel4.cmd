echo === seL4 Discovery Kit Boot Test ===
echo Loading seL4 image...

if load mmc 0:${distro_bootpart} ${scriptaddr} sel4.uImage; then
    iminfo ${scriptaddr}
    echo seL4 image loaded successfully.
else
    echo ERROR: Could not load sel4.uImage
fi
