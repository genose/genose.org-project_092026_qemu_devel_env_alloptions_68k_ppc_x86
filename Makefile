# Cross-compilateur fourni par ton environnement Retro68
CC = m68k-apple-macos-gcc
OBJCOPY = m68k-apple-macos-objcopy
CFLAGS = -m68040 -ffreestanding -nostdlib

all: bootloader.img

bootloader.elf: boot.S main.c
	$(CC) $(CFLAGS) -Ttext 0x0 -o bootloader.elf boot.S main.c

bootloader.img: bootloader.elf
	$(OBJCOPY) -O binary bootloader.elf bootloader.img

