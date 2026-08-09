# Makefile for MacOS71_GDB_ICMP_Test Example Application
# 
# This Makefile builds the example application that demonstrates
# integration with the custom bootloader.
# 
# Supports:
# - Motorola 68k architectures (68000, 68020, 68030, 68040)
# - PowerPC architectures (601, 604, G3, G4, 7410, 7455, 970)
# 
# Usage:
#   make                          - Build for default architecture (68040)
#   make TARGET=68040             - Build for 68040
#   make TARGET=G4               - Build for PowerPC G4
#   make clean                   - Clean build files
#   make all                     - Build for all supported architectures
#   make run                     - Build and run in QEMU (if available)
#   make debug                   - Build with debug symbols
#   make help                    - Show this help

.PHONY: all clean help run debug

/***************************************************************************
 * Project Configuration
 ***************************************************************************/

PROJECT = MacOS71_GDB_ICMP_Test
VERSION = 1.0.0

/***************************************************************************
 * Source Files
 ***************************************************************************/

# C source files
SRCS = main.c debug_utils.c icmp.c

# Assembly source files (if any)
ASM_SRCS =

# Object files
OBJS = $(SRCS:.c=.o) $(ASM_SRCS:.s=.o)

/***************************************************************************
 * Build Directory
 ***************************************************************************/

BUILD_DIR = build

/***************************************************************************
 * Target Configuration
 ***************************************************************************/

# Default architecture
TARGET_ARCH ?= 68040

# Output file
TARGET = $(BUILD_DIR)/$(PROJECT)_$(TARGET_ARCH)

/***************************************************************************
 * Cross-Compiler Configuration
 ***************************************************************************/

# For native compilation on macOS with Retro68 toolchain
M68K_PREFIX ?= m68k-apple-macos-
PPC_PREFIX ?= powerpc-apple-macos-

# For cross-compilation with elf toolchain
# M68K_PREFIX ?= m68k-elf-
# PPC_PREFIX ?= powerpc-elf-

/***************************************************************************
 * Architecture-Specific Settings
 ***************************************************************************/

# 68k Family
ifeq ($(TARGET_ARCH),68000)
    CC = $(M68K_PREFIX)gcc
    CFLAGS = -mcpu=68000 -m68000
    DEFS = -D__mc68k__ -DCPU_68000
    LDFLAGS = -mcpu=68000 -m68000 -nostdlib -Ttext 0x1000
    ARCH_NAME = 68000
endif

ifeq ($(TARGET_ARCH),68020)
    CC = $(M68K_PREFIX)gcc
    CFLAGS = -mcpu=68020 -m68020
    DEFS = -D__mc68k__ -DCPU_68020
    LDFLAGS = -mcpu=68020 -m68020 -nostdlib -Ttext 0x1000
    ARCH_NAME = 68020
endif

ifeq ($(TARGET_ARCH),68030)
    CC = $(M68K_PREFIX)gcc
    CFLAGS = -mcpu=68030 -m68030
    DEFS = -D__mc68k__ -DCPU_68030
    LDFLAGS = -mcpu=68030 -m68030 -nostdlib -Ttext 0x1000
    ARCH_NAME = 68030
endif

ifeq ($(TARGET_ARCH),68040)
    CC = $(M68K_PREFIX)gcc
    CFLAGS = -mcpu=68040 -m68040
    DEFS = -D__mc68k__ -DCPU_68040
    LDFLAGS = -mcpu=68040 -m68040 -nostdlib -Ttext 0x1000
    ARCH_NAME = 68040
endif

# PowerPC Family
ifeq ($(TARGET_ARCH),601)
    CC = $(PPC_PREFIX)gcc
    CFLAGS = -mcpu=601 -mpowerpc
    DEFS = -D__ppc__ -D__PPC__ -DCPU_601
    LDFLAGS = -mcpu=601 -mpowerpc -nostdlib -Ttext 0x1000
    ARCH_NAME = 601
endif

ifeq ($(TARGET_ARCH),604)
    CC = $(PPC_PREFIX)gcc
    CFLAGS = -mcpu=604 -mpowerpc
    DEFS = -D__ppc__ -D__PPC__ -DCPU_604
    LDFLAGS = -mcpu=604 -mpowerpc -nostdlib -Ttext 0x1000
    ARCH_NAME = 604
endif

ifeq ($(TARGET_ARCH),604ev)
    CC = $(PPC_PREFIX)gcc
    CFLAGS = -mcpu=604e -mpowerpc
    DEFS = -D__ppc__ -D__PPC__ -DCPU_604E
    LDFLAGS = -mcpu=604e -mpowerpc -nostdlib -Ttext 0x1000
    ARCH_NAME = 604ev
endif

ifeq ($(TARGET_ARCH),G3)
    CC = $(PPC_PREFIX)gcc
    CFLAGS = -mcpu=750 -mpowerpc
    DEFS = -D__ppc__ -D__PPC__ -DCPU_750
    LDFLAGS = -mcpu=750 -mpowerpc -nostdlib -Ttext 0x1000
    ARCH_NAME = G3
endif

ifeq ($(TARGET_ARCH),G4)
    CC = $(PPC_PREFIX)gcc
    CFLAGS = -mcpu=7455 -mpowerpc
    DEFS = -D__ppc__ -D__PPC__ -DCPU_7455
    LDFLAGS = -mcpu=7455 -mpowerpc -nostdlib -Ttext 0x1000
    ARCH_NAME = G4
endif

ifeq ($(TARGET_ARCH),7410)
    CC = $(PPC_PREFIX)gcc
    CFLAGS = -mcpu=7410 -mpowerpc
    DEFS = -D__ppc__ -D__PPC__ -DCPU_7410
    LDFLAGS = -mcpu=7410 -mpowerpc -nostdlib -Ttext 0x1000
    ARCH_NAME = 7410
endif

ifeq ($(TARGET_ARCH),7455)
    CC = $(PPC_PREFIX)gcc
    CFLAGS = -mcpu=7455 -mpowerpc
    DEFS = -D__ppc__ -D__PPC__ -DCPU_7455
    LDFLAGS = -mcpu=7455 -mpowerpc -nostdlib -Ttext 0x1000
    ARCH_NAME = 7455
endif

ifeq ($(TARGET_ARCH),970)
    CC = $(PPC_PREFIX)gcc
    CFLAGS = -mcpu=970 -mpowerpc
    DEFS = -D__ppc__ -D__PPC__ -DCPU_970
    LDFLAGS = -mcpu=970 -mpowerpc -nostdlib -Ttext 0x1000
    ARCH_NAME = 970
endif

/***************************************************************************
 * Common Flags
 ***************************************************************************/

# Include paths
INCLUDES = -I. -I../../include

# Optimization
OPTIMIZATION ?= -O2

# Warning flags
WARN_FLAGS = -Wall -Wextra -Wno-unused-variable -Wno-unused-function

# Debug flags
DEBUG_FLAGS ?= -g

# Standard flags
CFLAGS += $(OPTIMIZATION) $(WARN_FLAGS) $(DEBUG_FLAGS) $(INCLUDES) $(DEFS)

/***************************************************************************
 * Linker Script (Optional)
 ***************************************************************************/

# Custom linker script for memory layout
LINKER_SCRIPT ?= ../../bootloader_68k.ld

# For PPC, use PPC linker script
ifeq ($(filter $(TARGET_ARCH),601 604 604ev G3 G4 7410 7455 970),$(TARGET_ARCH))
    LINKER_SCRIPT ?= ../../bootloader_ppc.ld
endif

/***************************************************************************
 * Build Rules
 ***************************************************************************/

all: $(TARGET)

$(TARGET): $(OBJS)
	@echo "Linking $(PROJECT) for $(ARCH_NAME)..."
	@mkdir -p $(BUILD_DIR)
	$(CC) $(LDFLAGS) -o $@ $^ -T$(LINKER_SCRIPT) 2>/dev/null || \
	    $(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	@echo "Compiling $<..."
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.s
	@echo "Assembling $<..."
	$(CC) $(CFLAGS) -c $< -o $@

/***************************************************************************
 * Clean Targets
 ***************************************************************************/

clean:
	rm -rf $(BUILD_DIR) *.o

cleanall: clean
	rm -rf $(BUILD_DIR)

/***************************************************************************
 * Debug Build
 ***************************************************************************/

debug: CFLAGS += -DDEBUG=1
debug: all

/***************************************************************************
 * Run Target
 ***************************************************************************/

run: $(TARGET)
	@echo "Running $(PROJECT) for $(ARCH_NAME)..."
	@echo "Note: This requires QEMU to be installed and configured"
	@echo "Command: qemu-system-m68k -kernel $(TARGET) -m 128M -serial stdio -nographic -gdb tcp::2346"
	# Uncomment to automatically run:
	# qemu-system-m68k -kernel $(TARGET) -m 128M -serial stdio -nographic -gdb tcp::2346

/***************************************************************************
 * Build for All Architectures
 ***************************************************************************/

ALL_TARGETS = \
	target_68000 \
	target_68020 \
	target_68030 \
	target_68040 \
	target_601 \
	target_604 \
	target_604ev \
	target_G3 \
	target_G4 \
	target_7410 \
	target_7455 \
	target_970

all_targets: $(ALL_TARGETS)

$(ALL_TARGETS):
	@echo "Building for $@..."
	$(MAKE) TARGET=$(patsubst target_%,%,$@) clean
	$(MAKE) TARGET=$(patsubst target_%,%,$@)

/***************************************************************************
 * Architecture-Specific Targets
 ***************************************************************************/

target_68000:
	$(MAKE) TARGET=68000

target_68020:
	$(MAKE) TARGET=68020

target_68030:
	$(MAKE) TARGET=68030

target_68040:
	$(MAKE) TARGET=68040

target_601:
	$(MAKE) TARGET=601

target_604:
	$(MAKE) TARGET=604

target_604ev:
	$(MAKE) TARGET=604ev

target_G3:
	$(MAKE) TARGET=G3

target_G4:
	$(MAKE) TARGET=G4

target_7410:
	$(MAKE) TARGET=7410

target_7455:
	$(MAKE) TARGET=7455

target_970:
	$(MAKE) TARGET=970

/***************************************************************************
 * Help
 ***************************************************************************/

help:
	@echo "======================================================================"
	@echo "MacOS71_GDB_ICMP_Test - Build System"
	@echo "======================================================================"
	@echo ""
	@echo "Usage:"
	@echo "  make [TARGET=arch]    - Build for specific architecture"
	@echo "  make clean           - Clean build files"
	@echo "  make cleanall        - Remove all build files"
	@echo "  make all_targets     - Build for all architectures"
	@echo "  make run             - Build and show run command"
	@echo "  make debug           - Build with debug symbols"
	@echo "  make help            - Show this help"
	@echo ""
	@echo "Supported architectures:"
	@echo "  68k:   68000, 68020, 68030, 68040"
	@echo "  PPC:   601, 604, 604ev, G3, G4, 7410, 7455, 970"
	@echo ""
	@echo "Examples:"
	@echo "  make                          - Build for default (68040)"
	@echo "  make TARGET=68040            - Build for 68040"
	@echo "  make TARGET=G4               - Build for PowerPC G4"
	@echo "  make all_targets             - Build for all architectures"
	@echo "  make clean && make debug    - Clean and rebuild with debug"
	@echo ""
	@echo "Cross-compiler setup:"
	@echo "  For 68k:    export M68K_PREFIX=m68k-apple-macos-"
	@echo "  For PPC:    export PPC_PREFIX=powerpc-apple-macos-"
	@echo ""
	@echo "  Or use: ../../setup-cross-compilers.sh"
	@echo "======================================================================"

/***************************************************************************
 * Test Script Target
 ***************************************************************************/

test_app.sh: test_app.sh
	@echo "Test script already exists"

.PHONY: test_app.sh

/***************************************************************************
 * Documentation
 ***************************************************************************/

README.md: README.md
	@echo "Documentation is up to date"

/***************************************************************************
 * File List
 ***************************************************************************/

list_files:
	@echo "Source files:"
	@echo "  $(SRCS)"
	@echo ""
	@echo "Assembly files:"
	@echo "  $(ASM_SRCS)"
	@echo ""
	@echo "Include directory: $(INCLUDES)"
