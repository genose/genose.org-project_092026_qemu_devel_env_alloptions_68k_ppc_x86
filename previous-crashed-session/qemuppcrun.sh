#!/bin/bash

qemu-system-ppc \
  -M mac99 \
  -cpu G3 \
  -m 2G \
  -accel tcg \
  -hda /Users/xenon/qemu_vms/MacOS9.2_foreveredition/MacOS9.2_foreveredition.img \
  -cdrom ./Mac_OS_9.2.2_Unsupported_G4s.iso \
  -netdev user,id=net0,net=192.168.100.0/24,hostfwd=tcp::2222-:22,hostfwd=tcp::548-:548,hostfwd=tcp::445-:445 \
  -device virtio-net-pci,netdev=net0 \
  -netdev socket,id=appletalk,listen=:644 \
  -device virtio-net-pci,netdev=appletalk \
  -display cocoa \
  -vga std \
  -fsdev local,id=shared,path=/tmp/volatile_hd,security_model=none \
  -device virtio-9p-pci,fsdev=shared,mount_tag=shared \
  -name MacOS9.2_foreveredition
