#!/bin/bash
qemu-system-ppc \
-L /Users/xenon/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu \
-m 768 \
-smp 1 \
-device sungem,mac=52:54:00:12:34:56,netdev=net0 \
-netdev vmnet-shared,id=net0 \
-display cocoa \
-machine mac99,via=cuda \
-cpu 7455 \
-accel tcg,tb-size=128 \
-vga none \
-device VGA,vgamem_mb=16,edid=on \
-drive if=none,media=cdrom,id=drive1,file=/tmp/volatile_hd/Mac_OS_9.2.2_Unsupported_G4s.iso,readonly=on \
-device ide-cd,bus=ide.0,unit=1,drive=drive1,bootindex=0 \
-device loader,addr=0x4000000,file=/Users/xenon/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu/ppc-ndrvloader
