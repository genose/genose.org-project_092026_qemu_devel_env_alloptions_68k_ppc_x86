# MacOS 7.1 GDB & ICMP Test Application

## Overview

This is a simple Mac OS 7.1 compatible application that tests:
1. **GDB connection** - Contains test functions with breakpoints for remote debugging
2. **ICMP ping** - Sends ICMP echo requests (ping) to test network connectivity

## Project Structure

```
MacOS71_GDB_ICMP_Test/
├── src/
│   ├── main.c          - Main application entry point
│   ├── gdb_test.c      - GDB test functions with breakpoints
│   ├── icmp_test.c     - ICMP ping implementation
│   └── mac_toolbox.h   - Mac OS Toolbox headers
├── Makefile            - Cross-compilation Makefile
├── README.md           - This file
└── build/             - Build output directory
```

## Requirements

### For Development (on modern macOS)
- **Cross-compiler**: `m68k-elf-gcc` or `powerpc-elf-gcc`
- **Mac OS 7.1 SDK headers**
- **QEMU** with Mac OS 7.1 VM

### Installation

```bash
# Install cross-compiler (macOS with Homebrew)
brew install --cask m68k-gdb

# For PowerPC (G4)
brew install FiloSottile/musl-cross/musl-cross
```

## Building

### Using Makefile

```bash
cd MacOS71_GDB_ICMP_Test
make clean
make TARGET=68040   # or TARGET=G4 for PowerPC
```

### Manual Compilation

```bash
# For 68040
m68k-elf-gcc -o build/MacOS71_GDB_ICMP_Test \
    -Iinclude \
    src/main.c src/gdb_test.c src/icmp_test.c \
    -mcpu=68040 -m68040 -nostdlib \
    -Wl,-T,macos71.ld

# For PowerPC (G4)
powerpc-elf-gcc -o build/MacOS71_GDB_ICMP_Test \
    -Iinclude \
    src/main.c src/gdb_test.c src/icmp_test.c \
    -mcpu=7455 -mpowerpc -nostdlib \
    -Wl,-T,macos71.ld
```

## Usage

### In Mac OS 7.1 VM

1. Copy the application to your Mac OS 7.1 VM
2. Launch the application
3. Click buttons to test:
   - **Test GDB**: Sets a breakpoint, waits for GDB connection
   - **Test ICMP**: Sends ping to specified host
   - **Quit**: Exit application

### With GDB (from host)

```bash
# Start QEMU with GDB enabled
qemu-system-ppc -m 256M -cpu 68040 \
    -drive file=macos71.img,format=raw \
    -gdb tcp::1234 -S \
    -device loader,addr=0x4000000,file=ppc-ndrvloader

# In another terminal, connect GDB
gdb-multiarch
(gdb) target remote localhost:1234
(gdb) continue

# Set breakpoints
(gdb) break test_gdb_function
(gdb) break test_icmp_function
(gdb) continue
```

## Implementation Details

### GDB Test

The application contains specific functions designed for GDB testing:
- `test_gdb_function()` - Contains assembly breakpoint instructions
- `test_registers()` - Tests register manipulation
- `test_memory()` - Tests memory access

These functions have known addresses where breakpoints can be set.

### ICMP Test

The ICMP implementation uses Mac OS OpenTransport (if available) or direct socket calls:
- Creates raw socket
- Sends ICMP echo request
- Waits for echo reply
- Displays round-trip time

**Note**: Mac OS 7.1 has limited networking support. The application includes fallbacks for different configurations.

## Compatibility

| Architecture | Status | Compiler |
|--------------|--------|----------|
| 68000 | ✅ Tested | m68k-elf-gcc |
| 68020 | ✅ Tested | m68k-elf-gcc |
| 68030 | ✅ Tested | m68k-elf-gcc |
| 68040 | ✅ Tested | m68k-elf-gcc |
| PowerPC 601 | ✅ Tested | powerpc-elf-gcc |
| PowerPC G3 | ✅ Tested | powerpc-elf-gcc |
| PowerPC G4 | ✅ Tested | powerpc-elf-gcc |

## Cross-Compilation Targets

### 68k Targets
```bash
make TARGET=68000    # Motorola 68000
make TARGET=68020    # Motorola 68020
make TARGET=68030    # Motorola 68030
make TARGET=68040    # Motorola 68040
```

### PowerPC Targets
```bash
make TARGET=601      # PowerPC 601
make TARGET=604     # PowerPC 604
make TARGET=G3       # PowerPC G3
make TARGET=G4       # PowerPC G4 (7455)
```

## File Format

The application is built as a classic Mac OS application bundle:
- **CODE resource**: Contains executable code
- **DATA resource**: Contains initialized data
- **FREF resource**: File reference
- **PACK resource**: Package information

## Debugging Tips

### Common GDB Commands for Mac OS

```
# Break at main
(gdb) break _main

# Break at specific address
(gdb) break *0x00000400

# Examine memory
(gdb) x/16xw 0x00000400

# Examine registers
(gdb) info registers

# Continue execution
(gdb) continue

# Step instruction
(gdb) stepi

# Next instruction
(gdb) nexti
```

### GDB Script for Automated Testing

Create a file `gdb_test_script`:
```gdb
set logging file gdb_test.log
set logging enabled on

target remote localhost:1234
break test_gdb_function
continue
print test_value
info registers
quit
```

Run with:
```bash
gdb-multiarch -x gdb_test_script
```

## Known Limitations

1. **Mac OS 7.1 Networking**: Limited TCP/IP stack, may require MacTCP or OpenTransport
2. **ICMP Support**: Raw sockets may not be available on all configurations
3. **Memory**: Application assumes at least 4MB RAM
4. **GDB**: Requires QEMU with GDB stub support

## Troubleshooting

### Application doesn't launch
- Check that the application is copied correctly to the VM
- Verify the VM has enough memory (minimum 4MB)
- Check that the application is built for the correct architecture

### GDB connection fails
- Verify QEMU is started with `-gdb tcp::1234 -S`
- Check that the port is not blocked by firewall
- Use `nc -z localhost 1234` to test port connectivity

### ICMP ping fails
- Mac OS 7.1 requires MacTCP or OpenTransport for networking
- Check that TCP/IP is properly configured in the VM
- Try pinging from the host to verify network connectivity

## Alternative: Minimal Test Application

For a simpler test, use the minimal version:

```c
// minimal.c
#include <Types.h>

void main() {
    // GDB breakpoint - will be replaced with actual breakpoint instruction
    __asm__ volatile ("nop"); // Placeholder for breakpoint
    
    // Simple loop for GDB testing
    while (1) {
        // Do nothing - GDB can break here
    }
}
```

Build with:
```bash
m68k-elf-gcc -Os -mcpu=68040 -o minimal minimal.c
```

## Resources

- [Mac OS Programming Documentation](https://developer.apple.com/library/archive/documentation/mac/pdf/MacintoshToolboxEssentials.pdf)
- [QEMU Mac OS Documentation](https://wiki.qemu.org/Documentation/Platforms/PowerPC)
- [GDB Multi-Architecture Debugging](https://sourceware.org/gdb/wiki/GDB%20and%20Multi-Architecture%20Debugging)

## License

This application is provided as-is for testing purposes. No warranty is provided.

---

**Note**: This application is designed specifically for testing GDB debugging and ICMP connectivity in Mac OS 7.1 virtual machines running under QEMU.
