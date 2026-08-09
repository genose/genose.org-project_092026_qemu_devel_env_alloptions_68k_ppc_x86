# Custom Bootloader - FATBIN 68k/PPC Universal

## Overview

A universal bootloader supporting both Motorola 68k (68000-68060) and PowerPC (601-970) architectures in a single FATBIN executable. Designed for QEMU, Shoebill, and other emulators requiring flexible boot environments.

## Features

### CPU Detection & Support
- **68k Family**: 68000, 68010, 68020, 68030, 68040, 68060
- **PPC Family**: PPC601, PPC603, PPC604, PPC750, PPC7410, PPC7455, PPC970
- Automatic detection via illegal instruction testing and PVR register reading
- Fallback to generic configuration for unknown CPUs

### Exception Handling
- MacsBug-style exception vectors
- Stack frame capture (Type 7 for 68040+, standard for others)
- GDB breakpoints at 0x1000
- Status code storage at 0x1004

### Standardized Messages
- "Loading ..."
- "(CPU_NAME) running ..."
- "Boot OS ..."
- "Failure (code 0xXX)"

### Developer API
- Fixed addresses: 0x2000-0x21FF
- BootInfo structure
- AppVectors for application-specific branching
- APITable for API function pointers

### Backtrace Support
- Stack walking for 68k (Type 7 frame support)
- LR-based backtrace for PPC
- Symbol resolution helpers

### Utility Helpers
- String manipulation (copy, compare, length)
- Memory operations (copy, set, compare)
- Debug output (hex dump, register dump)
- printf implementation

## Project Structure

```
custom-bootloader/
├── Makefile                    # Build configuration
├── include/
│   ├── config.h                # System constants & CPU IDs
│   ├── api.h                   # Developer API definitions
│   └── helpers.h               # Helper function declarations
├── src/
│   ├── common/
│   │   ├── boot.s              # Main entry point & vectors
│   │   ├── vectors.s           # Exception handlers
│   │   └── messages.s          # Standardized message strings
│   ├── cpu/
│   │   ├── m68k/
│   │   │   ├── detect.s        # 68k CPU detection
│   │   │   ├── display.s       # 68k display routines
│   │   │   ├── backtrace.s     # 68k backtrace
│   │   │   └── helpers.s       # 68k-specific helpers
│   │   └── ppc/
│   │       ├── detect.s        # PPC CPU detection
│   │       ├── display.s       # PPC display routines
│   │       ├── backtrace.s     # PPC backtrace
│   │       └── helpers.s       # PPC-specific helpers
│   ├── api/
│   │   ├── api_entry.s        # API initialization
│   │   ├── api_68k.s           # 68k API implementation
│   │   └── api_ppc.s           # PPC API implementation
│   └── lib/
│       ├── string.s           # String helpers
│       ├── memory.s           # Memory helpers
│       ├── debug.c            # Debug helpers (C)
│       └── printf.c            # printf implementation
└── docs/
    ├── ARCHITECTURE.md         # Architecture details
    ├── BOOT_PROCESS.md         # Boot process documentation
    ├── API_REFERENCE.md        # API reference
    ├── BACKTRACE.md            # Backtrace documentation
    └── HELPERS.md              # Helper functions reference
```

## Quick Start

### Build

```bash
cd custom-bootloader
make clean all
```

Available targets:
- `make all` - Build all versions
- `make bootloader_m68k` - Build 68k version
- `make bootloader_ppc` - Build PPC version
- `make bootloader_fatbin` - Build FATBIN combined version
- `make debug` - Build with debug symbols
- `make test` - Run tests
- `make install` - Install to system
- `make clean` - Clean all

### Usage

Load the bootloader in your emulator:

```bash
# For QEMU
qemu-system-m68k -kernel bootloader_fatbin -m 128M
qemu-system-ppc -kernel bootloader_fatbin -m 256M

# For debugging with GDB
qemu-system-ppc -kernel bootloader_fatbin -s -S -gdb tcp::1234
```

Then connect GDB:

```bash
gdb-multiarch -ex "target remote localhost:1234" -ex "break *0x1000" -ex "continue"
```

## GDB Breakpoint

The bootloader sets a breakpoint at address **0x1000** for debugging purposes.
Status code is stored at **0x1004** (0 = success, non-zero = error code).

## CPU-Specific Notes

### 68k Series
- **68000**: Basic exception handling, no MMU support
- **68010**: Added VBR (Vector Base Register)
- **68020**: Added 32-bit addressing, more registers
- **68030**: Added MMU, burst mode
- **68040**: Added Type 7 stack frames, CPUSHA instruction
- **68060**: Enhanced MMU, pipeline improvements

### PPC Series
- **PPC601**: First PowerPC implementation (PVR: 0x0001)
- **PPC603**: Enhanced with better power management (PVR: 0x0003)
- **PPC604**: Better performance, more features (PVR: 0x0004)
- **PPC750**: G3 processor (PVR: 0x0008)
- **PPC7410**: G4 processor (PVR: 0x000C)
- **PPC7455**: Enhanced G4 (PVR: 0x800C)
- **PPC970**: G5 processor (PVR: 0x0039)

## License

This project is licensed under the MIT License. See LICENSE for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a pull request

## References

- [QEMU Documentation](https://www.qemu.org/docs/master/)
- [Shoebill Emulator](https://github.com/pruten/shoebill)
- [MacsBug Reference](https://en.wikipedia.org/wiki/MacsBug)
- [Motorola 68k Manuals](https://www.nxp.com/docs/en/reference-manual/MC68000UM.pdf)
- [PowerPC Architecture](https://www.ibm.com/docs/en/aix/7.2?topic=reference-powerpc-architecture)
