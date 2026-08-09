# MacOS71_GDB_ICMP_Test Integration Guide

**Version:** 1.0.0  
**Date:** 2026-08-09  
**Status:** ✅ Complete

---

## 📋 Overview

This document describes the complete integration of the **MacOS71_GDB_ICMP_Test** example application with the **custom bootloader**. The example demonstrates:

- Network connectivity testing via ICMP ping
- Bootloader detection and API usage
- GDB debugging integration
- Architecture-specific builds (68k and PPC)
- Fallback behavior when bootloader is not present

---

## 🎯 Purpose

The **MacOS71_GDB_ICMP_Test** application serves as a reference implementation for developers who want to:

1. Integrate their applications with the custom bootloader
2. Test network connectivity from within QEMU
3. Debug applications using GDB
4. Support both 68k and PowerPC architectures
5. Handle cases where the bootloader may not be present

---

## 📁 Project Structure

```
custom-bootloader/examples/MacOS71_GDB_ICMP_Test/
├── main.c              # Main application entry point and tests
├── main.h              # (Optional - not currently used)
├── debug_utils.h       # Debug utilities header
├── debug_utils.c       # Debug utilities implementation
├── icmp.h              # ICMP header (NEW - Session 2)
├── icmp.c              # ICMP implementation (NEW - Session 2)
├── Makefile            # Build system (NEW - Session 2)
├── test_app.sh         # Test script (NEW - Session 2)
└── README.md           # Example documentation
```

---

## 🆕 Recent Additions (Session 2 - 2026-08-09)

### 1. icmp.h - ICMP Header

**Purpose:** Provide ICMP functionality for network connectivity testing

**Key Features:**
- ICMP result codes (`ICMP_SUCCESS`, `ICMP_TIMEOUT`, etc.)
- ICMP header structure (`ICMPHeader`)
- Function declarations:
  - `icmp_init()` - Initialize ICMP subsystem
  - `icmp_shutdown()` - Shutdown ICMP subsystem
  - `icmp_ping()` - Send ICMP echo request
  - `icmp_checksum()` - Calculate ICMP checksum (RFC 1071)
  - `icmp_error_string()` - Get error description
  - `icmp_resolve_hostname()` - Resolve hostname to IP
  - `icmp_is_network_available()` - Check network availability

**Architecture Support:** Motorola 68k (with PPC fallbacks)

**Example Usage:**
```c
#include "icmp.h"

ICMPResult result = icmp_ping("127.0.0.1", 2000);
if (result == ICMP_SUCCESS) {
    debug_info("Ping successful!\n");
} else {
    debug_error("Ping failed: %s\n", icmp_error_string(result));
}
```

---

### 2. icmp.c - ICMP Implementation

**Purpose:** Implement ICMP functionality for QEMU environments

**Key Implementation Details:**

#### Network Availability Check
- Uses `is_qemu()` to detect QEMU environment
- Assumes networking is available in QEMU
- For real Mac, assumes networking is available (would use Gestalt in real implementation)

#### Hostname Resolution
- Supports `localhost` and `127.0.0.1`
- Falls back to `127.0.0.1` for unknown hostnames
- Returns IP address in network byte order

#### ICMP Ping Implementation
- Simulated ping for demonstration purposes
- For `127.0.0.1`: Always returns `ICMP_SUCCESS` with simulated delay
- For other addresses: Simulates based on sequence number
- Can simulate timeouts for testing error handling

#### Checksum Calculation
- Implements RFC 1071 compliant checksum
- Handles both even and odd length buffers
- Properly folds 32-bit sum to 16 bits

**Note:** This is a **simulated implementation** for demonstration. In a real application on Mac OS 7.1, you would use MacTCP or OpenTransport APIs.

---

### 3. Makefile - Build System

**Purpose:** Compile the example application for multiple architectures

**Supported Architectures:**
- **68k Family:** 68000, 68020, 68030, 68040
- **PowerPC Family:** 601, 604, 604ev, G3, G4, 7410, 7455, 970

**Key Features:**
- Architecture-specific compiler flags
- Custom linker script support
- Multiple build targets:
  - `make` - Build for default (68040)
  - `make TARGET=68040` - Build for specific architecture
  - `make clean` - Clean build files
  - `make all_targets` - Build for all architectures
  - `make debug` - Build with debug symbols
  - `make run` - Show QEMU run command
  - `make help` - Show help

**Cross-Compiler Configuration:**
```bash
# For Retro68 toolchain (macOS)
export M68K_PREFIX=m68k-apple-macos-
export PPC_PREFIX=powerpc-apple-macos-

# For ELF toolchain
export M68K_PREFIX=m68k-elf-
export PPC_PREFIX=powerpc-elf-

# Or use the setup script
../../setup-cross-compilers.sh
```

**Example Build Commands:**
```bash
# Build for 68040
make TARGET=68040

# Build for PowerPC G4
make TARGET=G4

# Build all architectures
make all_targets

# Clean and rebuild with debug
make clean && make debug
```

---

### 4. test_app.sh - Test Script

**Purpose:** Automated testing of the example application

**Key Features:**
- Colorized output for clarity
- Requirement checking (QEMU, cross-compilers)
- Multiple test types:
  1. **Build Test** - Compiles the application
  2. **Bootloader Detection Test** - Verifies bootloader detection code
  3. **QEMU Execution Test** - Runs application in QEMU
  4. **GDB Connection Test** - Tests GDB debugging

**Usage:**
```bash
# Run all tests for default architecture (68040)
./test_app.sh

# Run tests for specific architecture
./test_app.sh 68040
./test_app.sh G4

# Run with custom timeout
./test_app.sh --timeout 60

# Run with custom debug port
./test_app.sh --debug-port 1234

# Show help
./test_app.sh --help
```

**Architecture-Specific QEMU Commands:**
- **68k:** `qemu-system-m68k -M quadra800 -m 128M -serial stdio -nographic -kernel <binary> -gdb tcp::2346`
- **PPC:** `qemu-system-ppc -M mac99 -m 256M/512M -serial stdio -nographic -kernel <binary> -gdb tcp::2346 -via pmu`

---

## 🔗 Bootloader Integration

### API Usage

The example application uses the bootloader API through `debug_utils.h` and `debug_utils.c`.

**Key API Functions Used:**

#### Bootloader Detection
```c
#include "../../include/bootloader_api.h"

int bootloader_present = debug_init();
if (bootloader_present) {
    debug_info("Bootloader detected!\n");
    uint32_t version = bootloader_get_version();
    uint32_t cpu_type = bootloader_get_cpu_type();
}
```

#### QEMU Detection
```c
int qemu_detected = is_qemu();
// or
int qemu_detected = bootloader_check_env();
```

#### Debug Output
```c
debug_error("Error: %s\n", message);
debug_info("Info: %s\n", message);
debug_warn("Warning: %s\n", message);
debug_verbose("Verbose: %s\n", message);
```

#### Debug Break
```c
// Trigger debug break (GDB will intercept)
debug_break();

// Conditional break (only if bootloader present and in QEMU)
debug_break_if_possible();
```

#### Backtrace Generation
```c
// Generate and print backtrace
debug_print_backtrace(10);

// Get backtrace into buffer
uint32_t buffer[20];
int depth = generate_backtrace(buffer, 20);
print_backtrace(buffer, depth);
```

#### Memory Dump
```c
debug_dump_memory(address, size);
debug_dump_memory_formatted(address, size, 16);
```

---

## 🎛️ Configuration

### Application Configuration (main.c)

```c
#define TEST_HOST       "127.0.0.1"
#define TEST_COUNT      4
#define TEST_TIMEOUT    2000
#define TEST_INTERVAL   1000
```

### Debug Configuration (debug_utils.h)

```c
#define APP_NAME         "MacOS71_GDB_ICMP_Test"
#define APP_VERSION      0x00010000
#define APP_ID           0x4D616349  // "MacI"

DebugLevel current_debug_level = DEBUG_LEVEL_INFO;
```

---

## 📊 Test Flow

The application follows this test flow:

1. **Initialization**
   - Initialize debug system (`debug_init()`)
   - Detect bootloader presence
   - Detect QEMU environment
   - Print banner with configuration

2. **Run Tests**
   - Initialize ICMP subsystem (`icmp_init()`)
   - Run ping tests to `TEST_HOST`
   - For each ping:
     - Send ICMP echo request
     - Wait for reply (simulated)
     - Check result
     - On error: Generate backtrace

3. **Cleanup**
   - Shutdown ICMP (`icmp_shutdown()`)
   - Shutdown debug system (`debug_shutdown()`)
   - Return exit code (0 = success, 1 = errors)

4. **Summary**
   - Print test summary
   - Show debug statistics

---

## 🔧 Fallback Behavior

The application gracefully handles cases where the bootloader is not present:

### Without Bootloader
- `debug_init()` returns 0
- `bootloader_check_env()` uses fallback magic number check
- `bootloader_trigger_gdb()` uses `illegal` instruction
- All debug functions still work (output to serial)
- Backtrace generation uses frame pointer chain

### With Bootloader
- Full API access via TRAP #15
- Enhanced debugging capabilities
- GDB integration through UART
- Shared memory for context passing

---

## 📈 Architecture Support

### 68k Architecture
- **Frame Pointer:** Uses `%a6` register
- **Backtrace:** Follows frame pointer chain
- **API:** TRAP #15 handler
- **Compilation:** `-mcpu=68040 -m68040 -fno-omit-frame-pointer`

### PowerPC Architecture
- **Frame Pointer:** Uses `R1` register (stack pointer)
- **Backtrace:** Follows back chain and LR save areas
- **API:** TRAP #15 handler (PPC implementation)
- **Compilation:** `-mcpu=7455 -mpowerpc -fno-omit-frame-pointer`

---

## 🧪 Testing Scenarios

### Scenario 1: With Custom Bootloader
```bash
# Build bootloader
cd ../..
make clean && make all

# Combine with application
cat build/bootloader_fatbin.bin \
    examples/MacOS71_GDB_ICMP_Test/build/MacOS71_GDB_ICMP_Test_68040 > combined.bin

# Run in QEMU
qemu-system-m68k -kernel combined.bin -m 128M -serial stdio -nographic -gdb tcp::2346
```

### Scenario 2: Without Bootloader (Standalone)
```bash
# Build application only
cd examples/MacOS71_GDB_ICMP_Test
make TARGET=68040

# Run in QEMU
qemu-system-m68k -kernel build/MacOS71_GDB_ICMP_Test_68040 \
    -m 128M -serial stdio -nographic -gdb tcp::2346
```

### Scenario 3: With GDB Debugging
```bash
# Terminal 1: Start QEMU
qemu-system-m68k -kernel combined.bin -m 128M -serial stdio -nographic -gdb tcp::2346

# Terminal 2: Connect GDB
gdb-multiarch -ex "set architecture m68k" -ex "target remote localhost:2346"
```

---

## 🐛 Error Handling

### Error Codes (icmp.h)
```c
typedef enum {
    ICMP_SUCCESS         = 0,    // Ping successful
    ICMP_TIMEOUT         = -1,   // Request timed out
    ICMP_HOST_UNREACH   = -2,   // Host unreachable
    ICMP_NETWORK_ERROR  = -3,   // Network error
    ICMP_RESOLVE_ERROR  = -4,   // Could not resolve hostname
    ICMP_GENERIC_ERROR  = -5,   // Generic error
    ICMP_INVALID_ARGUMENT = -6  // Invalid argument
} ICMPResult;
```

### Debug Error Codes (debug_utils.h)
```c
typedef enum {
    ERROR_SUCCESS           = 0,
    ERROR_GENERIC           = 1,
    ERROR_MEMORY           = 2,
    ERROR_TIMEOUT          = 3,
    ERROR_INVALID_ARGUMENT = 4,
    ERROR_NOT_IMPLEMENTED  = 5,
    ERROR_NOT_PRESENT      = 6,
    ERROR_QEMU_ONLY        = 7
} ErrorCode;
```

---

## 📚 Related Documentation

- [BOOTLOADER-API-SPEC.md](BOOTLOADER-API-SPEC.md) - Bootloader API specifications
- [DUAL-BACKTRACE-ENGINE.md](DUAL-BACKTRACE-ENGINE.md) - Backtrace implementation for 68k/PPC
- [QEMU-DETECTION.md](QEMU-DETECTION.md) - QEMU detection methods
- [bootloader_api.h](../include/bootloader_api.h) - API header file
- [debug_shared.h](../include/debug_shared.h) - Shared memory structures

---

## 🎯 Best Practices

### For Application Developers

1. **Always check bootloader presence** before using API
2. **Use `-fno-omit-frame-pointer`** for backtrace support
3. **Provide fallback behavior** for non-bootloader environments
4. **Initialize debug system early** in application startup
5. **Use debug macros** (`DEBUG_ASSERT`, `DEBUG_PRINT`) instead of raw calls
6. **Handle errors gracefully** with proper error codes
7. **Test in both environments** (with and without bootloader)

### For Testing

1. **Start with localhost** for network tests
2. **Use short timeouts** (500-1000ms) for quick testing
3. **Test error handling** by forcing failures
4. **Verify backtrace** works in both environments
5. **Test GDB connection** before full debugging sessions

---

## 📊 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-08-09 | Initial release - All files created and integrated |

---

## 🔗 Quick Start

```bash
# 1. Install cross-compilers
cd custom-bootloader
echo "M68K_PREFIX=m68k-apple-macos-" >> ~/.bashrc
echo "PPC_PREFIX=powerpc-apple-macos-" >> ~/.bashrc
source ~/.bashrc

# 2. Build the example
cd examples/MacOS71_GDB_ICMP_Test
make TARGET=68040

# 3. Test the application
./test_app.sh

# 4. (Optional) Test with bootloader
cd ../..
make clean && make all
cat build/bootloader_68k.bin examples/MacOS71_GDB_ICMP_Test/build/MacOS71_GDB_ICMP_Test_68040 > combined.bin
qemu-system-m68k -kernel combined.bin -m 128M -serial stdio -nographic -gdb tcp::2346
```

---

*Documentation generated by Mistral Vibe*  
*Date: 2026-08-09*  
*Session: Documentation Update*
