# BOOTLOADER API SPECIFICATION

**Project:** genose.org - Custom Bootloader  
**Version:** 1.0.2  
**Date:** 2026-08-09  

---

## 📋 TABLE OF CONTENTS

1. [Overview](#-overview)
2. [API Architecture](#-api-architecture)
3. [TRAP #15 Interface](#-trap-15-interface)
4. [Function Reference](#-function-reference)
5. [Data Structures](#-data-structures)
6. [Usage Examples](#-usage-examples)
7. [Error Handling](#-error-handling)
8. [Bootloader Presence Detection](#-bootloader-presence-detection)

---

## 🎯 OVERVIEW

The **Custom Bootloader API** provides a standardized interface for applications to interact with the bootloader's debugging and monitoring capabilities. The API is designed to be:

- **Architecture Independent**: Works on both 68k and PPC
- **Non-Intrusive**: Minimal overhead when not used
- **Emergency Capable**: Functions even when system is partially crashed
- **GDB Integrated**: Seamless integration with GNU Debugger

### Key Features

| Feature | Description |
|---------|-------------|
| **NMI Handler** | Level 7 interrupt handler for emergency debugging |
| **TRAP #15** | Software interrupt for API calls |
| **Shared Memory** | Communication via memory-mapped structures |
| **Backtrace** | Call stack generation for both architectures |
| **QEMU Detection** | Detects virtualization environment |
| **GDB Integration** | Triggers GDB breaks and provides context |

---

## 🏗️ API ARCHITECTURE

### Layered Design

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│  - Application code                                             │
│  - Uses bootloader_api.h                                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 API Wrapper Layer                              │
│  - bootloader_trigger_gdb()                                    │
│  - bootloader_check_env()                                      │
│  - debug_break()                                              │
│  - generate_backtrace_68k() / generate_backtrace_ppc()         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 TRAP #15 Interface                              │
│  - Software interrupt (vector 0xBC / 47)                      │
│  - Function dispatch via D0 register                           │
│  - Parameters via A0, D1, etc.                                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Bootloader Core                                │
│  - api_trap_handler (dispatcher)                              │
│  - Function implementations                                   │
│  - Shared memory management                                   │
└─────────────────────────────────────────────────────────────┘
```

### Communication Methods

1. **TRAP #15**: Primary method for function calls
2. **Shared Memory**: Data exchange via fixed addresses
3. **NMI Handler**: Emergency path for frozen systems
4. **UART**: GDB communication via serial port

### Address Map

| Address | Size | Purpose |
|---------|------|---------|
| 0x0000007C | 4 | NMI Handler Vector |
| 0x000000BC | 4 | TRAP #15 Handler Vector |
| 0x00002000 | 4 | BootInfo Pointer |
| 0x00002004 | 4 | AppVectors Pointer |
| 0x00002008 | 4 | APITable Pointer |
| 0x0000200C | 4 | API Status Flags |
| 0x00002010 | 4 | API Magic Number (0xDEADBEEF) |
| 0x00F00000 | 256B | Debugger Context (Shared Memory) |
| 0x00F00100 | 4KB | Debug Stack |
| 0x00F01100 | 4KB | Log Buffer |

---

## 🚪 TRAP #15 INTERFACE

### Overview

TRAP #15 (vector 47 at 0x000000BC) is the primary entry point for the bootloader API. Applications call functions by:

1. Loading the function ID into `D0`
2. Loading parameters into `A0`, `D1`, etc.
3. Executing `TRAP #15`
4. Reading results from `D0` and error code from `D1`

### Calling Convention

#### Input

| Register | Purpose | Function IDs Using It |
|----------|---------|----------------------|
| D0 | Function ID | All |
| A0 | Pointer parameter 1 | DUMP_MEMORY, LOG_MESSAGE, GET_BACKTRACE, GET_BOOTINFO |
| D1 | Value parameter 1 | DUMP_MEMORY (size), SET_DEBUG, GET_BACKTRACE (depth) |

#### Output

| Register | Purpose |
|----------|---------|
| D0 | Function result |
| D1 | Error code (0 = success) |
| A0 | Pointer result (if applicable) |

### Installation

The bootloader installs the TRAP #15 handler during initialization:

```c
// In bootloader
install_trap15_handler();
```

Applications can verify installation:

```c
if (bootloader_check_presence()) {
    // Bootloader is present and API is available
}
```

---

## 📚 FUNCTION REFERENCE

### Function List

| ID | Name | Description | 68k | PPC | D0 | A0 | D1 |
|----|------|-------------|-----|-----|----|----|----|
| 0 | TRIGGER_GDB | Force GDB break | ✅ | ✅ | - | - | - |
| 1 | CHECK_ENV | Detect QEMU | ✅ | ✅ | Result | - | - |
| 2 | GET_VERSION | Get bootloader version | ✅ | ✅ | Version | - | - |
| 3 | SET_DEBUG | Set debug level | ✅ | ✅ | - | - | Level |
| 4 | DUMP_MEMORY | Dump memory region | ✅ | ✅ | - | Address | Size |
| 5 | LOG_MESSAGE | Log message | ✅ | ✅ | - | String | - |
| 6 | GET_CPU_TYPE | Get CPU type | ✅ | ✅ | Type | - | - |
| 7 | GET_API_MAGIC | Get magic number | ✅ | ✅ | Magic | - | - |
| 8 | INSTALL_NMI | Install NMI handler | ✅ | ✅ | - | - | - |
| 9 | GET_BACKTRACE | Generate backtrace | ✅ | ✅ | Count | Buffer | Depth |
| 10 | CHECK_PRESENCE | Check bootloader | ✅ | ✅ | Result | - | - |
| 11 | GET_BOOTINFO | Get BootInfo pointer | ✅ | ✅ | - | Pointer | - |
| 12 | SET_BREAKPOINT | Set breakpoint | ✅ | ✅ | - | Address | - |
| 13 | CLEAR_BREAKPOINT | Clear breakpoint | ✅ | ✅ | - | Address | - |
| 14 | STEP_EXECUTION | Single step | ⚠️ | ⚠️ | - | - | - |
| 15 | CONTINUE | Continue execution | ⚠️ | ⚠️ | - | - | - |

### Detailed Descriptions

#### 0: TRIGGER_GDB

**Purpose**: Force a GDB break to allow debugging

**Behavior**:
- **QEMU**: Sends BREAK character (0x03) to UART at 0x50F0C000
- **Real Mac**: Executes `illegal` instruction to trigger exception

**Parameters**: None

**Returns**: D0 = 0 (success), D1 = 0

**Example**:
```c
bootloader_trigger_gdb();
```

**Use Case**: Emergency debugging when application detects an error

---

#### 1: CHECK_ENV

**Purpose**: Detect if running in QEMU or on real hardware

**Parameters**: None

**Returns**: D0 = 1 (QEMU) or 0 (Real Mac), D1 = 0

**Example**:
```c
int is_qemu = bootloader_check_env();
```

**Use Case**: Environment-specific behavior

---

#### 2: GET_VERSION

**Purpose**: Get the bootloader version number

**Parameters**: None

**Returns**: D0 = version (e.g., 0x00010002 for v1.0.2), D1 = 0

**Example**:
```c
uint32_t version = bootloader_get_version();
```

**Use Case**: Version compatibility checking

---

#### 3: SET_DEBUG

**Purpose**: Set the debug verbosity level

**Parameters**: D1 = level (0=silent, 1=normal, 2=verbose)

**Returns**: D0 = 0, D1 = 0

**Example**:
```c
bootloader_set_debug(DEBUG_VERBOSE);
```

**Use Case**: Control debug output level

---

#### 4: DUMP_MEMORY

**Purpose**: Dump a memory region to the debug console

**Parameters**:
- A0 = starting address
- D1 = size in bytes

**Returns**: D0 = 0, D1 = 0

**Example**:
```c
bootloader_dump_memory(0x00100000, 256);
```

**Use Case**: Inspect memory contents during debugging

---

#### 5: LOG_MESSAGE

**Purpose**: Log a message to the debug console

**Parameters**: A0 = pointer to null-terminated string

**Returns**: D0 = 0, D1 = 0

**Example**:
```c
bootloader_log_message("Error occurred!\n");
```

**Use Case**: Debug output that works with or without GDB

---

#### 6: GET_CPU_TYPE

**Purpose**: Get the detected CPU type

**Parameters**: None

**Returns**: D0 = CPU_ID_* constant from config.h, D1 = 0

**Example**:
```c
uint32_t cpu = bootloader_get_cpu_type();
if (cpu == CPU_ID_68040) {
    // 68040-specific code
}
```

**Use Case**: CPU-specific optimizations

---

#### 7: GET_API_MAGIC

**Purpose**: Verify the bootloader API is present by reading the magic number

**Parameters**: None

**Returns**: D0 = API_MAGIC_NUMBER (0xDEADBEEF), D1 = 0

**Example**:
```c
uint32_t magic = bootloader_get_api_magic();
if (magic == 0xDEADBEEF) {
    // API is present
}
```

**Use Case**: Bootloader presence verification

---

#### 8: INSTALL_NMI

**Purpose**: Install the NMI (Non-Maskable Interrupt) handler

**Parameters**: None

**Returns**: D0 = 0, D1 = 0

**Example**:
```c
bootloader_install_nmi();
```

**Use Case**: Enable emergency debugging for frozen systems

---

#### 9: GET_BACKTRACE

**Purpose**: Generate a backtrace and store it in the provided buffer

**Parameters**:
- A0 = pointer to buffer (20 uint32_t elements)
- D1 = maximum depth

**Returns**: D0 = actual depth captured, D1 = 0

**Example**:
```c
uint32_t bt[20];
int depth = bootloader_call_raw(BOOTLOADER_GET_BACKTRACE, (uint32_t)bt, 20, NULL);
```

**Use Case**: Error reporting with call stack

---

#### 10: CHECK_PRESENCE

**Purpose**: Check if the custom bootloader is present

**Parameters**: None

**Returns**: D0 = 1 (present) or 0 (not present), D1 = 0

**Example**:
```c
if (bootloader_check_presence()) {
    // Use bootloader features
}
```

**Note**: This checks the magic number at API_MAGIC_NUMBER_ADDRESS

---

#### 11: GET_BOOTINFO

**Purpose**: Get a pointer to the BootInfo structure

**Parameters**: None

**Returns**: A0 = pointer to BootInfo, D0 = 0, D1 = 0

**Example**:
```c
BootInfo *info = bootloader_get_bootinfo();
if (info) {
    // Access BootInfo fields
}
```

**Use Case**: Access bootloader information

---

#### 12: SET_BREAKPOINT

**Purpose**: Set a breakpoint at a specific address

**Parameters**: A0 = address

**Returns**: D0 = 0, D1 = 0

**Example**:
```c
bootloader_set_breakpoint(0x00100000);
```

**Status**: ⚠️ Partially implemented - requires breakpoint handler

---

#### 13: CLEAR_BREAKPOINT

**Purpose**: Clear a breakpoint at a specific address

**Parameters**: A0 = address

**Returns**: D0 = 0, D1 = 0

**Example**:
```c
bootloader_clear_breakpoint(0x00100000);
```

**Status**: ⚠️ Partially implemented

---

#### 14: STEP_EXECUTION

**Purpose**: Execute a single instruction (single-step)

**Parameters**: None

**Returns**: D0 = 0, D1 = 0

**Status**: ⚠️ Not yet implemented

---

#### 15: CONTINUE

**Purpose**: Continue execution after a breakpoint

**Parameters**: None

**Returns**: D0 = 0, D1 = 0

**Status**: ⚠️ Not yet implemented

---

## 🗃️ DATA STRUCTURES

### DebuggerContext

The `DebuggerContext` structure is stored at `0x00F00000` and contains the complete CPU state and debug information.

```c
typedef struct {
    /* CPU Registers */
    uint32_t registers_d[8];      /* D0-D7 */
    uint32_t registers_a[7];      /* A0-A6 */
    uint32_t usp;                 /* User Stack Pointer (A7) */
    uint32_t ssp;                 /* Supervisor Stack Pointer */
    uint32_t pc;                  /* Program Counter */
    uint16_t sr;                  /* Status Register */
    
    /* Exception Information */
    uint32_t exception_vector;    /* Which exception occurred */
    uint32_t exception_pc;        /* PC at time of exception */
    uint16_t exception_sr;        /* SR at time of exception */
    uint32_t exception_address;   /* Address that caused exception */
    uint32_t exception_format;    /* Exception format word */
    
    /* Environment Flags */
    uint32_t is_qemu;             /* 1 = QEMU, 0 = real Mac */
    uint32_t bootloader_present;  /* 1 = custom bootloader present */
    uint32_t nmi_handler_installed;
    uint32_t trap15_handler_installed;
    
    /* Control Flags */
    uint32_t resume_flag;         /* 1 = resume execution */
    uint32_t step_flag;           /* 1 = single-step */
    uint32_t breakpoint_hit;      /* 1 = breakpoint was hit */
    uint32_t manual_break;        /* 1 = manual break */
    
    /* Backtrace */
    uint32_t backtrace[20];       /* Return addresses */
    uint32_t backtrace_count;     /* Number of frames */
    
    /* Error Information */
    uint32_t last_error_code;
    uint32_t last_error_pc;
    uint32_t last_error_addr;
    uint32_t error_count;
    
    /* Application Information */
    uint32_t app_id;
    uint32_t app_version;
    char     app_name[32];
    
    /* Statistics */
    uint32_t nmi_count;
    uint32_t trap15_count;
    uint32_t gdb_break_count;
    uint32_t backtrace_count;
    
    /* Reserved */
    uint32_t reserved[8];
} DebuggerContext;
```

**Size**: 256 bytes

**Access**: `DEBUGGER_CTX` macro or `(DebuggerContext*)0x00F00000`

---

### BootInfo

The `BootInfo` structure is stored at the address pointed to by `0x00002000`.

```c
typedef struct {
    uint32_t cpu_type;           /* Detected CPU type */
    uint32_t memory_size;        /* Total memory size */
    uint32_t memory_start;       /* Memory start address */
    uint32_t memory_end;         /* Memory end address */
    uint32_t boot_device;        /* Boot device */
    uint32_t bootloader_version; /* Bootloader version */
    uint32_t api_version;        /* API version */
} BootInfo;
```

---

### AppVectors

Application-specific vectors for callbacks.

```c
typedef struct {
    void (*app_entry)(void);     /* Application entry point */
    void (*error_handler)(uint32_t); /* Error callback */
    void (*debug_handler)(void);  /* Debug callback */
    void (*backtrace_handler)(uint32_t*, int); /* Backtrace callback */
} AppVectors;
```

---

## 💻 USAGE EXAMPLES

### Example 1: Basic Debugging

```c
#include "bootloader_api.h"

void my_function(void) {
    // Check if bootloader is present
    if (bootloader_check_presence()) {
        // Initialize debug system
        debug_init("MyApp", 0x00010000);
        
        // Set debug level
        bootloader_set_debug(DEBUG_VERBOSE);
        
        // Log a message
        bootloader_log_message("Starting my_function\n");
    }
    
    // ... application code ...
    
    // Check for error
    if (error_detected) {
        bootloader_log_message("Error detected!\n");
        debug_break();  // Trigger GDB
    }
}
```

---

### Example 2: Error Handling with Backtrace

```c
#include "bootloader_api.h"

void handle_error(int code) {
    // Store error info
    DebuggerContext *ctx = DEBUGGER_CTX;
    ctx->last_error_code = code;
    ctx->last_error_pc = get_current_pc();
    
    // Generate backtrace
    uint32_t bt[20];
    ctx->backtrace_count = generate_backtrace_68k(bt, 20);
    memcpy(ctx->backtrace, bt, ctx->backtrace_count * sizeof(uint32_t));
    
    // Log error
    bootloader_log_message("Error occurred!\n");
    
    // Trigger GDB
    bootloader_trigger_gdb();
}
```

---

### Example 3: Conditional Debugging

```c
#include "bootloader_api.h"

void critical_section(void) {
    // Only enable debugging in QEMU
    if (bootloader_check_presence() && bootloader_check_env()) {
        bootloader_set_debug(DEBUG_VERBOSE);
        
        // Enable NMI handler for emergency breaks
        bootloader_install_nmi();
    }
    
    // ... critical code ...
    
    // Emergency check
    if (is_bootloader_present()) {
        debug_break_if_possible();
    }
}
```

---

### Example 4: Memory Inspection

```c
#include "bootloader_api.h"

void inspect_memory(uint32_t address, uint32_t size) {
    if (bootloader_check_presence()) {
        bootloader_log_message("Memory dump:\n");
        bootloader_dump_memory(address, size);
    }
}
```

---

### Example 5: Application Registration

```c
#include "bootloader_api.h"

int main(void) {
    // Register with bootloader
    debug_init("MacOS71_GDB_ICMP_Test", 0x00010000);
    
    // Set up error handling
    // ...
    
    // Main application loop
    while (1) {
        // ...
    }
    
    return 0;
}
```

---

## ❌ ERROR HANDLING

### Error Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | API_ERROR_SUCCESS | Operation completed successfully |
| 1 | API_ERROR_INVALID_FUNCTION | Invalid function ID |
| 2 | API_ERROR_INVALID_PARAMETER | Invalid parameter |
| 3 | API_ERROR_NOT_IMPLEMENTED | Function not yet implemented |
| 4 | API_ERROR_NOT_PRESENT | Bootloader not present |
| 5 | API_ERROR_ENVIRONMENT | Environment error (e.g., wrong architecture) |

### Error Handling in Applications

```c
int error = bootloader_call_raw(
    BOOTLOADER_DUMP_MEMORY,
    address,
    size,
    NULL
);

if (error != API_ERROR_SUCCESS) {
    // Handle error
    switch (error) {
        case API_ERROR_INVALID_FUNCTION:
            bootloader_log_message("Invalid function ID\n");
            break;
        case API_ERROR_INVALID_PARAMETER:
            bootloader_log_message("Invalid parameter\n");
            break;
        case API_ERROR_NOT_PRESENT:
            bootloader_log_message("Bootloader not present\n");
            break;
        default:
            bootloader_log_message("Unknown error\n");
            break;
    }
}
```

### Error Recovery

The API is designed to be fault-tolerant:

1. **Invalid Function**: Returns error but doesn't crash
2. **Invalid Parameters**: Validated before processing
3. **Bootloader Not Present**: Functions return 0 or error code
4. **Memory Errors**: Handled via bus error handlers

---

## 🔍 BOOTLOADER PRESENCE DETECTION

### Methods

Applications can detect if the custom bootloader is present using multiple methods:

#### Method 1: Magic Number Check (Fastest)

```c
int is_present = (magic_number == 0xDEADBEEF);
```

#### Method 2: TRAP #15 Call

```c
int is_present = bootloader_check_presence();
```

#### Method 3: NMI Handler Check

```c
int is_present = check_nmi_handler_present();
```

#### Method 4: Combined Check

```c
int is_present = is_bootloader_present();
```

### Fallback Behavior

If the bootloader is not present:
- API functions return error codes
- `bootloader_trigger_gdb()` executes `illegal` instruction
- Shared memory may not be available

### Code Example with Fallback

```c
void my_debug_function(void) {
    if (is_bootloader_present()) {
        // Use bootloader API
        bootloader_trigger_gdb();
    } else {
        // Fallback: Use standard Mac OS debugging
        // (e.g., MacsBug, Debugger, etc.)
        __asm__ volatile ("illegal");
    }
}
```

---

## 📊 COMPATIBILITY

### Architecture Support

| Feature | 68k | PPC | Notes |
|---------|-----|-----|-------|
| TRAP #15 | ✅ | ✅ | Full support |
| NMI Handler | ✅ | ✅ | Vector 0x7C |
| Shared Memory | ✅ | ✅ | 0x00F00000 |
| Backtrace | ✅ | ✅ | Different algorithms |
| QEMU Detection | ✅ | ✅ | Architecture-specific |
| GDB Trigger | ✅ | ✅ | UART 0x50F0C000 |

### Compiler Compatibility

- **GCC m68k**: Full support (recommended)
- **GCC PPC**: Full support (recommended)
- **Retro68**: Full support with `-fno-omit-frame-pointer`
- **Other Compilers**: May work with adjustments

### Optimization Compatibility

| Optimization | Backtrace Support | Notes |
|--------------|-------------------|-------|
| -O0 | ✅ | Best support |
| -O1 | ✅ | Good support |
| -O2 | ⚠️ | Works but may have gaps |
| -O3 | ⚠️ | Works but may have gaps |
| -Os | ⚠️ | Works but may have gaps |
| -fomit-frame-pointer | ❌ | **NOT SUPPORTED** |

---

## 🎯 BEST PRACTICES

### For Application Developers

1. **Always check for bootloader presence** before calling API functions
2. **Use `-fno-omit-frame-pointer`** for all code that needs backtracing
3. **Limit backtrace depth** to prevent stack overflow
4. **Test in both QEMU and real hardware** (if possible)
5. **Provide fallback behavior** for when bootloader is not present
6. **Use `debug_break()`** instead of raw `TRAP #15` calls
7. **Register your application** with `debug_init()` early in startup

### For Bootloader Developers

1. **Install handlers early** in boot process
2. **Preserve original vectors** when possible
3. **Handle all error cases** gracefully
4. **Keep API backward compatible**
5. **Document all functions** thoroughly
6. **Test with real applications**

---

## 📚 SEE ALSO

- [DUAL-BACKTRACE-ENGINE.md](DUAL-BACKTRACE-ENGINE.md) - Backtrace implementation
- [QEMU-DETECTION.md](QEMU-DETECTION.md) - QEMU detection methods
- [ARCHITECTURE.md](ARCHITECTURE.md) - Overall architecture
- [config.h](../include/config.h) - Configuration constants
- [bootloader_api.h](../include/bootloader_api.h) - API header

---

*Generated by Mistral Vibe - Bootloader API Specification*
*Date: 2026-08-09*
*Version: 1.0.2*
