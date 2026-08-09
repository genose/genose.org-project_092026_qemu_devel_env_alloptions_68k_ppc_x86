/***************************************************************************
 * Custom Bootloader - Makefile
 * 
 * Build system for the universal FATBIN bootloader supporting 68k and PowerPC.
 * 
 * Usage:
 *   make all              - Build all targets
 *   make clean            - Clean all build products
 *   make bootloader_m68k  - Build 68k-only bootloader
 *   make bootloader_ppc   - Build PPC-only bootloader
 *   make bootloader_fatbin - Build FATBIN (both architectures)
 *   make debug            - Build with debug symbols
 *   make release           - Build optimized for size
 *   make test             - Run tests
 *   make install           - Install to system
 *   make docs             - Generate documentation
 ***************************************************************************/

# Project configuration
PROJECT = custom-bootloader
VERSION = 1.0.0

# Directories
SRC_DIR = src
INCLUDE_DIR = include
BUILD_DIR = build
DOCS_DIR = docs
DIST_DIR = dist

# Toolchain configuration
# These can be overridden on the command line
CC = gcc
CXX = g++
AS = as
LD = ld
AR = ar
OC = objcopy
OBJDUMP = objdump
NM = nm
STRIP = strip

# Cross-compilation tools (can be overridden)
CC_68K = m68k-elf-gcc
AS_68K = m68k-elf-as
LD_68K = m68k-elf-ld

CC_PPC = powerpc-elf-gcc
AS_PPC = powerpc-elf-as
LD_PPC = powerpc-elf-ld

# Compiler flags
CFLAGS = -Wall -Wextra -Werror -O2 -g
CFLAGS += -I$(INCLUDE_DIR) -D__BOOTLOADER__
CFLAGS += -mcpu=68040 -m68040

CFLAGS_PPC = -Wall -Wextra -Werror -O2 -g
CFLAGS_PPC += -I$(INCLUDE_DIR) -D__BOOTLOADER__ -D__PPC__
CFLAGS_PPC += -m32 -mcpu=750

# Debug flags
DEBUG_CFLAGS = -O0 -g3 -DDEBUG=1 -DDEBUG_VERBOSE=1

# Release flags
RELEASE_CFLAGS = -Os -DNDEBUG -DDEBUG=0

# Assembly flags
ASFLAGS = 
ASFLAGS_PPC = 

# Linker flags
LDFLAGS = -T bootloader.ld -nostdlib
LDFLAGS_68K = -T bootloader_68k.ld -nostdlib
LDFLAGS_PPC = -T bootloader_ppc.ld -nostdlib

# Output files
TARGET_M68K = $(BUILD_DIR)/bootloader_m68k.bin
TARGET_PPC = $(BUILD_DIR)/bootloader_ppc.bin
TARGET_FATBIN = $(BUILD_DIR)/bootloader_fatbin.bin
TARGET_DEBUG = $(BUILD_DIR)/bootloader_debug.bin
TARGET_RELEASE = $(BUILD_DIR)/bootloader.bin

# Intermediate files
TARGET_M68K_ELF = $(BUILD_DIR)/bootloader_m68k.elf
TARGET_PPC_ELF = $(BUILD_DIR)/bootloader_ppc.elf
TARGET_FATBIN_ELF = $(BUILD_DIR)/bootloader_fatbin.elf

# Object files
OBJS_COMMON = \
	$(BUILD_DIR)/src/common/boot.o \
	$(BUILD_DIR)/src/common/vectors.o \
	$(BUILD_DIR)/src/common/messages.o

OBJS_CPU_M68K = \
	$(BUILD_DIR)/src/cpu/m68k/detect.o \
	$(BUILD_DIR)/src/cpu/m68k/display.o \
	$(BUILD_DIR)/src/cpu/m68k/backtrace.o \
	$(BUILD_DIR)/src/cpu/m68k/helpers.o

OBJS_CPU_PPC = \
	$(BUILD_DIR)/src/cpu/ppc/detect.o \
	$(BUILD_DIR)/src/cpu/ppc/display.o \
	$(BUILD_DIR)/src/cpu/ppc/backtrace.o \
	$(BUILD_DIR)/src/cpu/ppc/helpers.o

OBJS_API = \
	$(BUILD_DIR)/src/api/api_entry.o \
	$(BUILD_DIR)/src/api/api_68k.o \
	$(BUILD_DIR)/src/api/api_ppc.o

OBJS_LIB = \
	$(BUILD_DIR)/src/lib/string.o \
	$(BUILD_DIR)/src/lib/memory.o \
	$(BUILD_DIR)/src/lib/debug.o \
	$(BUILD_DIR)/src/lib/printf.o

OBJS_68K = $(OBJS_COMMON) $(OBJS_CPU_M68K) $(OBJS_API) $(OBJS_LIB)
OBJS_PPC = $(OBJS_COMMON) $(OBJS_CPU_PPC) $(OBJS_API) $(OBJS_LIB)

# Source files
SRCS_COMMON = \
	src/common/boot.s \
	src/common/vectors.s \
	src/common/messages.s

SRCS_CPU_M68K = \
	src/cpu/m68k/detect.s \
	src/cpu/m68k/display.s \
	src/cpu/m68k/backtrace.s \
	src/cpu/m68k/helpers.s

SRCS_CPU_PPC = \
	src/cpu/ppc/detect.s \
	src/cpu/ppc/display.s \
	src/cpu/ppc/backtrace.s \
	src/cpu/ppc/helpers.s

SRCS_API = \
	src/api/api_entry.s \
	src/api/api_68k.s \
	src/api/api_ppc.s

SRCS_LIB = \
	src/lib/string.s \
	src/lib/memory.s \
	src/lib/debug.c \
	src/lib/printf.c

# Default target
all: $(TARGET_FATBIN) $(TARGET_M68K) $(TARGET_PPC)

# Build targets
.PHONY: build
build: all

# Clean target
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

# Install target
.PHONY: install
install: all
	mkdir -p /boot
	cp $(TARGET_RELEASE) /boot/bootloader.bin

# Test target
.PHONY: test
test: $(TARGET_DEBUG)
	qemu-system-m68k -kernel $(TARGET_DEBUG) -m 128M -serial stdio -nographic

# Documentation target
.PHONY: docs
docs:
	# Generate documentation (if doxygen is available)
	@echo "Generating documentation..."
	@if command -v doxygen >/dev/null 2>&1; then \
		doxygen docs/Doxyfile; \
	fi

# FATBIN target
$(TARGET_FATBIN): $(OBJS_68K) $(OBJS_PPC) | $(BUILD_DIR)
	@echo "Linking FATBIN bootloader..."
	$(LD) $(LDFLAGS) -o $(TARGET_FATBIN_ELF) $(OBJS_68K) $(OBJS_PPC)
	$(OC) -O binary $(TARGET_FATBIN_ELF) $(TARGET_FATBIN)

# 68k target
$(TARGET_M68K): $(OBJS_68K) | $(BUILD_DIR)
	@echo "Linking 68k bootloader..."
	$(LD_68K) $(LDFLAGS_68K) -o $(TARGET_M68K_ELF) $(OBJS_68K)
	$(OC) -O binary $(TARGET_M68K_ELF) $(TARGET_M68K)

# PPC target
$(TARGET_PPC): $(OBJS_PPC) | $(BUILD_DIR)
	@echo "Linking PPC bootloader..."
	$(LD_PPC) $(LDFLAGS_PPC) -o $(TARGET_PPC_ELF) $(OBJS_PPC)
	$(OC) -O binary $(TARGET_PPC_ELF) $(TARGET_PPC)

# Debug build
$(TARGET_DEBUG): CFLAGS += $(DEBUG_CFLAGS)
$(TARGET_DEBUG): $(OBJS_68K) $(OBJS_PPC) | $(BUILD_DIR)
	@echo "Linking debug bootloader..."
	$(LD) $(LDFLAGS) -o $(TARGET_FATBIN_ELF) $(OBJS_68K) $(OBJS_PPC)
	$(OC) -O binary $(TARGET_FATBIN_ELF) $(TARGET_DEBUG)

# Release build
$(TARGET_RELEASE): CFLAGS += $(RELEASE_CFLAGS)
$(TARGET_RELEASE): $(OBJS_68K) $(OBJS_PPC) | $(BUILD_DIR)
	@echo "Linking release bootloader..."
	$(LD) $(LDFLAGS) -o $(TARGET_FATBIN_ELF) $(OBJS_68K) $(OBJS_PPC)
	$(OC) -O binary -S $(TARGET_FATBIN_ELF) $(TARGET_RELEASE)

# Common object files
$(BUILD_DIR)/src/common/boot.o: src/common/boot.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/src/common/vectors.o: src/common/vectors.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/src/common/messages.o: src/common/messages.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -o $@ $<

# 68k CPU object files
$(BUILD_DIR)/src/cpu/m68k/detect.o: src/cpu/m68k/detect.s
	@mkdir -p $(dir $@)
	$(AS_68K) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/src/cpu/m68k/display.o: src/cpu/m68k/display.s
	@mkdir -p $(dir $@)
	$(AS_68K) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/src/cpu/m68k/backtrace.o: src/cpu/m68k/backtrace.s
	@mkdir -p $(dir $@)
	$(AS_68K) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/src/cpu/m68k/helpers.o: src/cpu/m68k/helpers.s
	@mkdir -p $(dir $@)
	$(AS_68K) $(ASFLAGS) -o $@ $<

# PPC CPU object files
$(BUILD_DIR)/src/cpu/ppc/detect.o: src/cpu/ppc/detect.s
	@mkdir -p $(dir $@)
	$(AS_PPC) $(ASFLAGS_PPC) -o $@ $<

$(BUILD_DIR)/src/cpu/ppc/display.o: src/cpu/ppc/display.s
	@mkdir -p $(dir $@)
	$(AS_PPC) $(ASFLAGS_PPC) -o $@ $<

$(BUILD_DIR)/src/cpu/ppc/backtrace.o: src/cpu/ppc/backtrace.s
	@mkdir -p $(dir $@)
	$(AS_PPC) $(ASFLAGS_PPC) -o $@ $<

$(BUILD_DIR)/src/cpu/ppc/helpers.o: src/cpu/ppc/helpers.s
	@mkdir -p $(dir $@)
	$(AS_PPC) $(ASFLAGS_PPC) -o $@ $<

# API object files
$(BUILD_DIR)/src/api/api_entry.o: src/api/api_entry.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/src/api/api_68k.o: src/api/api_68k.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/src/api/api_ppc.o: src/api/api_ppc.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -o $@ $<

# Library object files
$(BUILD_DIR)/src/lib/string.o: src/lib/string.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/src/lib/memory.o: src/lib/memory.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/src/lib/debug.o: src/lib/debug.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD_DIR)/src/lib/printf.o: src/lib/printf.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Phony targets
.PHONY: all clean build install test docs

# Additional targets

# List all source files
list-sources:
	@echo "Source files:"
	@find src -type f \( -name "*.s" -o -name "*.c" \)

# Show size information
size: $(TARGET_RELEASE)
	@echo "Bootloader size:"
	@size $(TARGET_RELEASE)
	@objdump -h $(TARGET_RELEASE)

# Disassemble
Disassemble: $(TARGET_RELEASE)
	@echo "Disassembling bootloader..."
	@objdump -d -M intel $(TARGET_RELEASE)

# Clean all
clean-all: clean
	rm -rf dist
	find . -name "*.o" -delete
	find . -name "*.elf" -delete
	find . -name "*.bin" -delete

# Archive for distribution
package: clean all
	mkdir -p $(DIST_DIR)
	cp $(TARGET_RELEASE) $(DIST_DIR)/bootloader.bin
	cp $(TARGET_M68K) $(DIST_DIR)/bootloader_m68k.bin
	cp $(TARGET_PPC) $(DIST_DIR)/bootloader_ppc.bin
	cp $(TARGET_FATBIN) $(DIST_DIR)/bootloader_fatbin.bin
	cp README.md $(DIST_DIR)/README.txt
	cp docs/*.md $(DIST_DIR)/docs/
	cd $(DIST_DIR) && tar -czvf ../$(PROJECT)-$(VERSION).tar.gz *

# Run in QEMU (68k)
qemu-m68k: $(TARGET_M68K)
	qemu-system-m68k -kernel $(TARGET_M68K) -m 128M -serial stdio -nographic

# Run in QEMU (PPC)
qemu-ppc: $(TARGET_PPC)
	qemu-system-ppc -kernel $(TARGET_PPC) -m 256M -serial stdio -nographic

# Run in QEMU (FATBIN)
qemu-fatbin: $(TARGET_FATBIN)
	qemu-system-ppc -kernel $(TARGET_FATBIN) -m 256M -serial stdio -nographic

# Run with GDB debugging
gdb: $(TARGET_DEBUG)
	qemu-system-ppc -kernel $(TARGET_DEBUG) -s -S -gdb tcp::1234 -serial stdio -nographic &
	sleep 1
	gdb-multiarch -ex "target remote localhost:1234" -ex "break *0x1000" -ex "continue"

# Show help
.PHONY: help
help:
	@echo "Custom Bootloader Build System"
	@echo "================================"
	@echo ""
	@echo "Build targets:"
	@echo "  make all              - Build all targets"
	@echo "  make clean            - Clean all build products"
	@echo "  make bootloader_m68k  - Build 68k-only bootloader"
	@echo "  make bootloader_ppc   - Build PPC-only bootloader"
	@echo "  make bootloader_fatbin - Build FATBIN (both architectures)"
	@echo "  make debug            - Build with debug symbols"
	@echo "  make release           - Build optimized for size"
	@echo "  make test             - Run tests"
	@echo "  make install           - Install to system"
	@echo "  make package           - Create distribution package"
	@echo ""
	@echo "Utility targets:"
	@echo "  make list-sources      - List all source files"
	@echo "  make size              - Show size information"
	@echo "  make Disassemble       - Disassemble bootloader"
	@echo "  make docs              - Generate documentation"
	@echo "  make qemu-m68k         - Run in QEMU 68k emulator"
	@echo "  make qemu-ppc          - Run in QEMU PPC emulator"
	@echo "  make qemu-fatbin       - Run in QEMU with FATBIN"
	@echo "  make gdb               - Run with GDB debugging"
	@echo "  make help              - Show this help message"

# Include dependency files if they exist
-include $(wildcard $(BUILD_DIR)/*.d)
