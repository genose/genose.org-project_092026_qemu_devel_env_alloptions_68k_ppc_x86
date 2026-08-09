#!/bin/bash

# Injection du noyau/bootloader custom directement en RAM émulée
qemu-system-m68k \
    -M q800 \
    -bios quadra800.rom \
    -kernel ./bootloader.img \
    -gdb tcp::2346 \
    -S \
    -drive file=disk.img,format=raw,media=disk

