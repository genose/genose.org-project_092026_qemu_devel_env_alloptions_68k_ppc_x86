# MacOS71_GDB_ICMP_Test - ICMP Test Application with GDB Integration

**Project:** genose.org - Custom Bootloader Integration Example  
**Type:** Example Application  
**Architecture:** Motorola 68k (m68k)  
**Environment:** QEMU and Real Mac  
**Debugging:** GDB with Bootloader Integration  

---

## 📋 OVERVIEW

This directory contains an example application (`MacOS71_GDB_ICMP_Test`) that demonstrates how to:

1. **Integrate with the custom bootloader** for enhanced debugging
2. **Detect bootloader presence** (with or without bootloader)
3. **Use TRAP #15 API** for debugging functions
4. **Generate backtraces** on errors
5. **Trigger GDB breaks** from application code
6. **Work on both QEMU and real Mac hardware** with fallback mechanisms

### Features

- ✅ **Bootloader Detection**: Checks if custom bootloader is present
- ✅ **QEMU Detection**: Detects virtualization environment
- ✅ **GDB Integration**: Can trigger GDB breaks via bootloader
- ✅ **Backtrace Generation**: Captures call stack on errors
- ✅ **Fallback Support**: Works without bootloader (uses standard debugging)
- ✅ **ICMP Test**: Example ICMP ping implementation

---

## 📁 FILE STRUCTURE

```
MacOS71_GDB_ICMP_Test/
├── README.md                    # This file
├── main.c                      # Main application
├── icmp.c                     # ICMP implementation
├── icmp.h                     # ICMP header
├── debug_utils.c              # Debug utilities
├── debug_utils.h              # Debug utilities header
├── Makefile                   # Build configuration
├── link_script.ld             # Linker script
└── test_app.sh                # Test script
```

---

## 🏗️ ARCHITECTURE

### Integration Model

```
┌─────────────────────────────────────────────────────────────┐
│                 MacOS71_GDB_ICMP_Test Application                │
├─────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │   ICMP Module    │    │  Debug Module    │                 │
│  │                 │    │                  │                 │
│  │ - Send Ping      │    │ - Bootloader     │                 │
│  │ - Receive Reply  │◄───┤   Detection     │                 │
│  │ - Timeout Logic  │    │ - Backtrace Gen. │                 │
│  └────────┬────────┘    │ - GDB Trigger    │                 │
│           │              └────────┬────────┘                 │
│           ▼                       │                              │
│  ┌────────────────────────────────┼──────────────────┐          │
│  │            Conditional Debugging Interface             │          │
│  │                                                      │          │
│  │  if (bootloader_present) {                           │          │
│  │      use_bootloader_api();    // TRAP #15          │          │
│  │  } else {                                                │          │
│  │      use_standard_debug();   // MacsBug, etc.      │          │
│  │  }                                                     │          │
│  └──────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│                     Custom Bootloader                           │
│  - NMI Handler (vector 0x7C)                                   │
│  - TRAP #15 Handler (vector 0xBC)                              │
│  - Shared Memory (0x00F00000)                                  │
│  - UART GDB Trigger (0x50F0C000)                               │
└─────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│                          GDB                                  │
│  - Receives break via UART                                     │
│  - Displays backtrace                                          │
│  - Allows debugging                                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 DEPENDENCIES

### Required Tools

- **Compiler**: Retro68 or m68k-elf-gcc
- **Assembler**: m68k-elf-as
- **Linker**: m68k-elf-ld
- **QEMU**: For testing (qemu-system-m68k)
- **GDB**: For debugging (gdb-multiarch)

### Required Headers

The application uses headers from the custom bootloader:

```
../../include/config.h
../../include/bootloader_api.h
../../include/debug_shared.h
```

---

## 📥 INSTALLATION & BUILD

### Build from Source

```bash
cd vm-assistant/custom-bootloader/examples/MacOS71_GDB_ICMP_Test
make clean
make
```

### Build Options

| Target | Description |
|--------|-------------|
| `make` | Build application |
| `make clean` | Clean build files |
| `make debug` | Build with debug symbols |
| `make release` | Build optimized version |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CC` | `m68k-elf-gcc` | C compiler |
| `AS` | `m68k-elf-as` | Assembler |
| `LD` | `m68k-elf-ld` | Linker |
| `CFLAGS` | `-O2 -Wall` | Compiler flags |

---

## 🚀 USAGE

### With Custom Bootloader

The application automatically detects and uses the bootloader if present:

```bash
# Start QEMU with custom bootloader
qemu-system-m68k -kernel ../../build/bootloader_fatbin.bin \
    -m 128M -serial stdio -nographic \
    -gdb tcp::2346

# In another terminal, run the application
# It will automatically use the bootloader API
```

### Without Custom Bootloader

The application falls back to standard debugging:

```bash
# Start QEMU with standard Mac OS
qemu-system-m68k -kernel macos_rom.bin \
    -m 128M -serial stdio -nographic

# The application will use standard Mac OS debugging
```

### GDB Debugging

```bash
# Start QEMU with GDB stub
qemu-system-m68k -kernel bootloader.bin \
    -m 128M -serial stdio -nographic \
    -gdb tcp::2346

# Connect GDB
gdb-multiarch -ex "target remote localhost:2346"

# In GDB:
(gdb) break main
(gdb) continue
(gdb) info registers
(gdb) backtrace
```

---

## 📄 API USAGE EXAMPLES

### Basic Bootloader Detection

```c
#include "bootloader_api.h"

if (bootloader_check_presence()) {
    // Bootloader is present
    if (bootloader_check_env()) {
        // Running in QEMU
        bootloader_trigger_gdb();
    }
}
```

### Debug Break with Backtrace

```c
#include "bootloader_api.h"

void handle_error(const char *message) {
    // Log error
    bootloader_log_message(message);
    
    // Generate backtrace
    DebuggerContext *ctx = DEBUGGER_CTX;
    ctx->backtrace_count = generate_backtrace_68k(ctx->backtrace, 20);
    
    // Trigger GDB
    debug_break();
}
```

### Conditional Debugging

```c
#include "bootloader_api.h"

void critical_function(void) {
    if (is_bootloader_present()) {
        // Use bootloader debugging
        bootloader_set_debug(DEBUG_VERBOSE);
        debug_break_if_possible();
    } else {
        // Fallback to standard debugging
        // (e.g., MacsBug, Debugger trap, etc.)
        __asm__ volatile ("trap #14");  // MacsBug break
    }
}
```

---

## 🛡️ SAFETY & BEST PRACTICES

### Always Check for Bootloader

```c
// GOOD: Check before using
if (bootloader_check_presence()) {
    bootloader_trigger_gdb();
}

// BAD: Assume bootloader is present
bootloader_trigger_gdb();  // May crash if not present!
```

### Use Maximum Depth for Backtrace

```c
// GOOD: Limit depth
uint32_t bt[20];
int depth = generate_backtrace_68k(bt, 20);

// BAD: Unlimited depth (risk of infinite loop)
uint32_t bt[1000];
int depth = generate_backtrace_68k(bt, 1000);
```

### Compile with Frame Pointers

```bash
# GOOD: Frame pointers enabled
m68k-elf-gcc -O2 -fno-omit-frame-pointer -o app.elf app.c

# BAD: Frame pointers omitted (backtrace won't work!)
m68k-elf-gcc -O2 -fomit-frame-pointer -o app.elf app.c
```

### Handle All Error Cases

```c
int error = bootloader_call_raw(
    BOOTLOADER_DUMP_MEMORY,
    address,
    size,
    NULL
);

if (error != API_ERROR_SUCCESS) {
    // Handle error appropriately
    handle_api_error(error);
}
```

---

## 📊 COMPATIBILITY

### Architecture Support

| Feature | 68k | PPC | Notes |
|---------|-----|-----|-------|
| Bootloader Detection | ✅ | ✅ | Via magic number |
| QEMU Detection | ✅ | ✅ | Multiple methods |
| TRAP #15 API | ✅ | ✅ | Full support |
| NMI Handler | ✅ | ✅ | Emergency breaks |
| Backtrace | ✅ | ✅ | Architecture-specific |
| GDB Trigger | ✅ | ✅ | UART 0x50F0C000 |
| ICMP Test | ✅ | ⚠️ | 68k focused |

### Environment Support

| Environment | Status | Notes |
|-------------|--------|-------|
| QEMU m68k | ✅ Full | All features |
| QEMU PPC | ⚠️ Partial | API works, ICMP not tested |
| Real Mac 68k | ✅ Full | Fallback to standard debug |
| Basilisk II | ⚠️ Partial | May need adjustments |
| SheepShaver | ⚠️ Partial | May need adjustments |

---

## 🧪 TESTING

### Test ICMP Functionality

```bash
# Build and run
make clean && make

# Start QEMU
qemu-system-m68k -kernel output/app.bin -m 128M -serial stdio -nographic

# The application will:
# 1. Initialize
# 2. Detect environment
# 3. Send ICMP ping
# 4. Wait for reply
# 5. Display results
```

### Test Debug Break

```bash
# Add error injection to main.c
void test_debug_break(void) {
    int *null_ptr = NULL;
    *null_ptr = 0;  // This will crash
}

# Rebuild and run
make clean && make
qemu-system-m68k -kernel output/app.bin -m 128M -serial stdio -nographic -gdb tcp::2346

# When crash occurs, GDB will attach and show backtrace
```

### Test Bootloader Integration

```bash
# Build bootloader
cd ../../
make clean && make

# Build application
cd examples/MacOS71_GDB_ICMP_Test
make clean && make

# Create combined image
cat ../../build/bootloader_fatbin.bin output/app.bin > combined.bin

# Run in QEMU
qemu-system-m68k -kernel combined.bin -m 128M -serial stdio -nographic -gdb tcp::2346
```

---

## 🐛 TROUBLESHOOTING

### Problem: Backtrace is empty

**Cause**: Code compiled with `-fomit-frame-pointer`

**Solution**: Recompile with `-fno-omit-frame-pointer`

```bash
make clean
CFLAGS="-O2 -fno-omit-frame-pointer" make
```

---

### Problem: GDB doesn't attach

**Cause 1**: GDB stub not started

**Solution**: Add `-gdb tcp::2346` to QEMU command line

**Cause 2**: UART address incorrect

**Solution**: Verify UART address is 0x50F0C000 for your Mac model

---

### Problem: Bootloader not detected

**Cause 1**: Magic number not set

**Solution**: Ensure bootloader is built and installed correctly

**Cause 2**: Different memory layout

**Solution**: Check if magic number is at 0x00002010

---

### Problem: Application crashes on real Mac

**Cause**: Using bootloader API without checking presence

**Solution**: Always check `bootloader_check_presence()` first

---

## 🎓 NOTES

1. **ICMP Implementation**: The ICMP test is simplified for demonstration. Real implementation would need proper network stack.

2. **GDB Integration**: The GDB integration works best with QEMU's built-in GDB stub. Real Mac hardware would need different debugging approaches.

3. **Performance**: The debug features have minimal overhead when not used. In production, consider compiling without debug support.

4. **Portability**: The code is designed to work across different Mac models and emulators.

5. **Extensibility**: The architecture allows easy addition of new test cases and debugging features.

---

## 📚 REFERENCES

- [../../docs/BOOTLOADER-API-SPEC.md](../../docs/BOOTLOADER-API-SPEC.md) - API specification
- [../../docs/DUAL-BACKTRACE-ENGINE.md](../../docs/DUAL-BACKTRACE-ENGINE.md) - Backtrace implementation
- [../../docs/QEMU-DETECTION.md](../../docs/QEMU-DETECTION.md) - QEMU detection methods
- [../../include/bootloader_api.h](../../include/bootloader_api.h) - API header

---

## 📜 LICENSE

This example is provided as-is for educational and development purposes. It is part of the genose.org custom bootloader project.

---

*Generated by Mistral Vibe - MacOS71_GDB_ICMP_Test Example*
*Date: 2026-08-09*
