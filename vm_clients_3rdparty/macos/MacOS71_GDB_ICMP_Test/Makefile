# Makefile for MacOS 7.1 GDB & ICMP Test Application
# Supports 68k and PowerPC cross-compilation

# Project configuration
PROJECT = MacOS71_GDB_ICMP_Test
VERSION = 1.0

# Source files
SRCS = src/main.c src/gdb_test.c src/icmp_test.c
OBJS = $(SRCS:.c=.o)

# Build directory
BUILD_DIR = build

# Output file
TARGET = $(BUILD_DIR)/$(PROJECT)

# Architecture configuration
# Supported: 68000, 68020, 68030, 68040, 601, 604, G3, G4
TARGET_ARCH ?= 68040

# Compiler settings
ifeq ($(TARGET_ARCH),68000)
    CC = m68k-elf-gcc
    CFLAGS = -mcpu=68000 -m68000
    DEFS = -D__mc68k__
    LDFLAGS = -mcpu=68000 -m68000 -nostdlib
    ARCH_NAME = 68000
endif

ifeq ($(TARGET_ARCH),68020)
    CC = m68k-elf-gcc
    CFLAGS = -mcpu=68020 -m68020
    DEFS = -D__mc68k__
    LDFLAGS = -mcpu=68020 -m68020 -nostdlib
    ARCH_NAME = 68020
endif

ifeq ($(TARGET_ARCH),68030)
    CC = m68k-elf-gcc
    CFLAGS = -mcpu=68030 -m68030
    DEFS = -D__mc68k__
    LDFLAGS = -mcpu=68030 -m68030 -nostdlib
    ARCH_NAME = 68030
endif

ifeq ($(TARGET_ARCH),68040)
    CC = m68k-elf-gcc
    CFLAGS = -mcpu=68040 -m68040
    DEFS = -D__mc68k__
    LDFLAGS = -mcpu=68040 -m68040 -nostdlib
    ARCH_NAME = 68040
endif

ifeq ($(TARGET_ARCH),601)
    CC = powerpc-elf-gcc
    CFLAGS = -mcpu=601 -mpowerpc
    DEFS = -D__ppc__ -D__PPC__
    LDFLAGS = -mcpu=601 -mpowerpc -nostdlib
    ARCH_NAME = 601
endif

ifeq ($(TARGET_ARCH),604)
    CC = powerpc-elf-gcc
    CFLAGS = -mcpu=604 -mpowerpc
    DEFS = -D__ppc__ -D__PPC__
    LDFLAGS = -mcpu=604 -mpowerpc -nostdlib
    ARCH_NAME = 604
endif

ifeq ($(TARGET_ARCH),G3)
    CC = powerpc-elf-gcc
    CFLAGS = -mcpu=750 -mpowerpc
    DEFS = -D__ppc__ -D__PPC__
    LDFLAGS = -mcpu=750 -mpowerpc -nostdlib
    ARCH_NAME = G3
endif

ifeq ($(TARGET_ARCH),G4)
    CC = powerpc-elf-gcc
    CFLAGS = -mcpu=7455 -mpowerpc
    DEFS = -D__ppc__ -D__PPC__
    LDFLAGS = -mcpu=7455 -mpowerpc -nostdlib
    ARCH_NAME = G4
endif

# Include paths
INCLUDES = -Isrc

# Optimization
OPTIMIZATION = -Os

# Debug flags
DEBUG_FLAGS = -g -DDEBUG

# Warning flags
WARN_FLAGS = -Wall -Wextra

# Standard flags
CFLAGS += $(OPTIMIZATION) $(WARN_FLAGS) $(DEBUG_FLAGS) $(INCLUDES) $(DEFS)

# Linker script (optional)
LINKER_SCRIPT = macos71.ld

all: $(TARGET)

$(TARGET): $(OBJS)
	@echo "Linking $(PROJECT) for $(ARCH_NAME)..."
	@mkdir -p $(BUILD_DIR)
	$(CC) $(LDFLAGS) -o $@ $^ -T$(LINKER_SCRIPT) 2>/dev/null || \
	    $(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	@echo "Compiling $<..."
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(BUILD_DIR) *.o

cleanall: clean
	rm -rf $(BUILD_DIR)

# Architecture-specific targets
target_68000: TARGET_ARCH=68000
	make clean && make

target_68020: TARGET_ARCH=68020
	make clean && make

target_68030: TARGET_ARCH=68030
	make clean && make

target_68040: TARGET_ARCH=68040
	make clean && make

target_601: TARGET_ARCH=601
	make clean && make

target_604: TARGET_ARCH=604
	make clean && make

target_G3: TARGET_ARCH=G3
	make clean && make

target_G4: TARGET_ARCH=G4
	make clean && make

# Build all targets
all_targets: target_68000 target_68020 target_68030 target_68040 target_601 target_604 target_G3 target_G4

# Help
help:
	@echo "MacOS 7.1 GDB & ICMP Test Application - Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make [TARGET=arch]    - Build for specific architecture"
	@echo "  make clean           - Clean build files"
	@echo "  make cleanall        - Remove all build files"
	@echo ""
	@echo "Supported architectures:"
	@echo "  68000, 68020, 68030, 68040 (68k family)"
	@echo "  601, 604, G3, G4 (PowerPC family)"
	@echo ""
	@echo "Examples:"
	@echo "  make TARGET=68040   - Build for 68040"
	@echo "  make TARGET=G4      - Build for PowerPC G4"
	@echo "  make all_targets    - Build for all architectures"

# Phony targets
.PHONY: all clean cleanall help all_targets target_68000 target_68020 target_68030 target_68040 target_601 target_604 target_G3 target_G4
