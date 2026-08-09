# DUAL-ARCHITECTURE BACKTRACE ENGINE

**Project:** genose.org - Custom Bootloader  
**Author:** Mistral Vibe (with user contributions)  
**Version:** 1.0  
**Date:** 2026-08-09  

---

## 📌 Overview

This document specifies the **Backtrace Engine** implementation for both **Motorola 68k** and **PowerPC (PPC)** architectures. The backtrace engine enables applications to generate call stack traces when errors occur, which can then be used for debugging via GDB or the bootloader's emergency debug shell.

### Key Features

- **Architecture-Agnostic Design**: Works on both 68k and PPC
- **Frame Pointer Based**: Uses standard calling conventions
- **Zero Runtime Overhead**: Only active when debugging
- **GDB Integration**: Backtraces can be parsed by GDB
- **Emergency Use**: Works even when system is partially crashed

---

## 🛠️ Implementation Details

### 1. Motorola 68k Backtrace

#### Calling Convention

Under **GCC for m68k**, the compiler uses the following calling convention:

- **Frame Pointer**: `%a6` (A6 register) - Points to the current stack frame
- **Stack Pointer**: `%a7` (A7 register) - Points to the top of the stack
- **Return Address**: Stored at `%a6 + 4` (immediately after the saved frame pointer)
- **Previous Frame**: The old `%a6` is stored at the address pointed to by `%a6`

#### Stack Frame Layout

```
High Addresses
    +------------------+
    |   ...           |  <-- Previous stack contents
    +------------------+
    |  Saved A6       |  <-- Frame pointer to caller's frame
    +------------------+
A6->|  Return PC      |  <-- Return address (where to go after function returns)
    +------------------+
    |  Local Var 1    |  <-- Local variables
    +------------------+
    |  Local Var 2    |
    +------------------+
    |  Saved Regs     |  <-- Optionally saved registers
    +------------------+
    |  Function Args  |  <-- Function arguments
    +------------------+
Low Addresses
```

#### Generation Algorithm (68k)

```c
typedef uint32_t backtrace_buffer[20];

int generate_backtrace_68k(uint32_t *buffer, int max_depth) {
    register uint32_t *frame_ptr __asm__("a6");  // Get current frame pointer
    int depth = 0;
    
    while (frame_ptr != 0 && depth < max_depth) {
        // Get return address (frame_ptr + 4)
        buffer[depth] = *(frame_ptr + 1);
        
        // Move to previous frame (address stored at frame_ptr)
        frame_ptr = (uint32_t *)*(frame_ptr);
        
        depth++;
    }
    
    return depth;  // Number of frames captured
}
```

#### Assembly Implementation

```assembly
; Input: A0 = buffer pointer, D1 = max depth
; Output: D0 = number of frames
; Clobbers: D0-D3, A0-A2

generate_backtrace_68k:
    movem.l %d2-%d3/%a1-%a2, -(sp)
    move.l  %a6, %a1              ; Get current frame pointer
    moveq   #0, %d0               ; Depth counter
    
.bt_loop:
    cmp.l   #0, %a1              ; Check if frame is null
    beq     .bt_done
    cmp.l   %d1, %d0             ; Check max depth
    bge     .bt_done
    
    move.l  4(%a1), %d2          ; Get return address
    move.l  %d2, (%a0)+          ; Store and increment buffer
    move.l  (%a1), %a1           ; Move to previous frame
    addq.l  #1, %d0
    bra     .bt_loop
    
.bt_done:
    movem.l (%sp)+, %d2-%d3/%a1-%a2
    rts
```

---

### 2. PowerPC Backtrace

#### Calling Convention

Under **GCC for PowerPC**, the ABI (Application Binary Interface) defines:

- **Stack Pointer**: `R1` - Points to the current stack frame
- **Link Register**: `LR` - Contains the return address
- **Back Chain**: Points to the previous stack frame (stored at `R1 + 0`)
- **Saved LR**: The old `LR` is stored at `R1 + 8` when a function calls another function

#### Stack Frame Layout

```
High Addresses
    +------------------+
    |   ...           |  <-- Previous stack contents
    +------------------+
R1->|  Back Chain     |  <-- Points to previous frame (R1 of caller)
    +------------------+
    |  Saved CR       |  <-- Condition Register (optional)
    +------------------+
    |  Saved LR       |  <-- Link Register (return address) at +8
    +------------------+
    |  Saved R31-R14  |  <-- Non-volatile registers (optional)
    +------------------+
    |  Local Vars     |  <-- Local variables
    +------------------+
    |  Function Args  |  <-- Function arguments
    +------------------+
Low Addresses
```

#### Generation Algorithm (PPC)

```c
int generate_backtrace_ppc(uint32_t *buffer, int max_depth) {
    register uint32_t *stack_ptr __asm__("r1");  // Get current stack pointer
    int depth = 0;
    
    while (stack_ptr != 0 && depth < max_depth) {
        // Get parent frame pointer (back chain)
        uint32_t *parent_stack = (uint32_t *)*(stack_ptr);
        
        if (parent_stack == 0) break;
        
        // Get saved LR (at parent_stack + 8)
        buffer[depth] = *(parent_stack + 2);  // +8 bytes = +2 longwords
        
        // Move to parent frame
        stack_ptr = parent_stack;
        
        depth++;
    }
    
    return depth;
}
```

#### Assembly Implementation (PPC)

```assembly
; Input: R3 = buffer pointer, R4 = max depth
; Output: R3 = number of frames
; Clobbers: R0, R2-R7

generate_backtrace_ppc:
    mflr    0                  ; Save LR
    stwu    1, -32(1)         ; Allocate stack space
    stw     31, 28(1)          ; Save R31
    mr      31, 3             ; Save buffer pointer
    mr      30, 4             ; Save max depth
    li      3, 0              ; Depth counter
    
    mr      4, 1             ; Stack pointer in R4
    
.bt_loop:
    cmpwi   4, 0
    beq     .bt_done
    cmpw    3, 30
    bge     .bt_done
    
    lwz     0(4), 5          ; Get back chain (parent frame)
    cmpwi   5, 0
    beq     .bt_done
    
    lwz     8(5), 6          ; Get saved LR from parent frame
    stw     6, 0(31)          ; Store in buffer
    addi    31, 31, 4         ; Increment buffer
    
    mr      4, 5             ; Move to parent frame
    addi    3, 3, 1          ; Increment depth
    bra     .bt_loop
    
.bt_done:
    lwz     31, 28(1)
    addi    1, 1, 32
    mtlr    0
    blr
```

---

## 🔌 Integration with Bootloader

### TRAP #15 API (Function 9: GET_BACKTRACE)

The bootloader provides a TRAP #15 interface for applications to request backtrace generation.

#### Usage from Application

```c
#include "bootloader_api.h"

uint32_t backtrace[20];
int count = bootloader_call_raw(
    BOOTLOADER_GET_BACKTRACE,
    (uint32_t)backtrace,
    20,
    NULL
);
```

Or using the convenience wrapper:

```c
uint32_t backtrace[20];
int depth = 0;

if (bootloader_check_presence()) {
    // Use architecture-specific backtrace
    #ifdef __m68k__
    depth = generate_backtrace_68k(backtrace, 20);
    #elif defined(__PPC__)
    depth = generate_backtrace_ppc(backtrace, 20);
    #endif
    
    // Store in shared memory for bootloader
    DebuggerContext *ctx = DEBUGGER_CTX;
    ctx->backtrace_count = depth;
    for (int i = 0; i < depth; i++) {
        ctx->backtrace[i] = backtrace[i];
    }
    
    // Trigger GDB
    bootloader_trigger_gdb();
}
```

---

## 📊 Backtrace Format

### Output Format

Backtraces are stored as an array of **32-bit addresses** representing the return addresses of each function in the call stack.

```
backtrace[0] = Address of most recent function (current)
backtrace[1] = Address of caller
backtrace[2] = Address of caller's caller
...
backtrace[n-1] = Address of entry point
```

### GDB Compatibility

The backtrace format is compatible with GDB's `backtrace` command. When loaded into GDB:

```
(gdb) info frame
(gdb) backtrace
```

### Symbol Resolution

To resolve symbols from addresses:

```c
; In bootloader
symbol_lookup:
    ; Input: D0 = address
    ; Output: A0 = symbol name string, D0 = symbol address
    ; Returns: D1 = 0 (found) or 1 (not found)
```

---

## 🎯 Usage Patterns

### Pattern 1: Emergency Debug Break

```c
#include "bootloader_api.h"

void some_function(void) {
    // Check for error condition
    if (error_condition) {
        // Generate backtrace
        uint32_t bt[20];
        int depth = generate_backtrace_68k(bt, 20);
        
        // Store in shared memory
        DebuggerContext *ctx = DEBUGGER_CTX;
        ctx->backtrace_count = depth;
        memcpy(ctx->backtrace, bt, depth * sizeof(uint32_t));
        
        // Trigger debug
        debug_break();
    }
}
```

### Pattern 2: Assert Macro

```c
#define DEBUG_ASSERT(cond) \
    do { \
        if (!(cond)) { \
            bootloader_log_message("ASSERT FAILED: " #cond "\n"); \
            debug_break(); \
        } \
    } while (0)

; Usage
DEBUG_ASSERT(pointer != NULL);
```

### Pattern 3: Error Handler

```c
void error_handler(const char *message, int code) {
    // Log the error
    bootloader_log_message(message);
    
    // Store error info
    DebuggerContext *ctx = DEBUGGER_CTX;
    ctx->last_error_code = code;
    ctx->last_error_pc = get_current_pc();
    
    // Generate backtrace
    ctx->backtrace_count = generate_backtrace_68k(ctx->backtrace, 20);
    
    // Break to debugger
    bootloader_trigger_gdb();
}
```

### Pattern 4: Conditional Debug

```c
void critical_function(void) {
    // Only break if bootloader is present
    if (is_bootloader_present() && bootloader_check_env()) {
        debug_break_if_possible();
    }
    
    // ... rest of function
}
```

---

## 🛡️ Safety Considerations

### Frame Pointer Omission

**WARNING**: The backtrace engine **requires** that functions are compiled **WITHOUT** the `-fomit-frame-pointer` optimization flag.

```bash
# CORRECT: Frame pointers enabled
m68k-elf-gcc -O2 -fno-omit-frame-pointer -o app.elf app.c

# INCORRECT: Frame pointers omitted
m68k-elf-gcc -O2 -fomit-frame-pointer -o app.elf app.c
```

Without frame pointers, the backtrace will be incomplete or incorrect.

### Stack Corruption

The backtrace engine assumes:
1. The stack is valid and readable
2. Frame pointers are properly maintained
3. No stack corruption has occurred

If the stack is corrupted, the backtrace may:
- Return incorrect addresses
- Cause a crash when accessing invalid memory
- Loop infinitely

### Maximum Depth

Always specify a **maximum depth** to prevent infinite loops in case of corrupted stack frames.

```c
// SAFE: Limited depth
int depth = generate_backtrace_68k(buffer, 20);

// UNSAFE: No limit
int depth = generate_backtrace_68k(buffer, 0xFFFFFFFF);
```

---

## 🧪 Testing

### Test in QEMU

```bash
# Start QEMU with GDB stub
qemu-system-m68k -kernel bootloader.bin \
    -m 128M -serial stdio -nographic \
    -gdb tcp::2346

# In another terminal, connect GDB
gdb-multiarch -ex "target remote localhost:2346"

# Trigger a backtrace from application
# GDB will receive the backtrace and display it
```

### Test Backtrace Generation

```c
#include "bootloader_api.h"

void test_backtrace(void) {
    uint32_t bt[10];
    int depth = generate_backtrace_68k(bt, 10);
    
    bootloader_log_message("Backtrace:");
    for (int i = 0; i < depth; i++) {
        char msg[32];
        snprintf(msg, sizeof(msg), "  %d: 0x%08X\n", i, bt[i]);
        bootloader_log_message(msg);
    }
}

int main(void) {
    debug_init("TestApp", 0x00010000);
    test_backtrace();
    return 0;
}
```

---

## 📝 API Reference

| Function | ID | Description | Architecture |
|----------|----|-------------|--------------|
| `generate_backtrace_68k` | - | Generate 68k backtrace | 68k |
| `generate_backtrace_ppc` | - | Generate PPC backtrace | PPC |
| `BOOTLOADER_GET_BACKTRACE` | 9 | Get backtrace via TRAP #15 | Both |
| `debug_break` | - | Emergency debug with backtrace | Both |
| `debug_break_if_possible` | - | Conditional debug break | Both |

---

## 🎓 Notes

1. **68k Frame Pointer**: The frame pointer (`%a6`) is callee-saved, meaning each function preserves the caller's frame pointer before modifying it.

2. **PPC Back Chain**: PowerPC uses a "back chain" pointer at the start of each stack frame, which points to the previous frame.

3. **Leaf Functions**: Functions that don't call other functions (leaf functions) may not have a complete stack frame, which can result in incomplete backtraces.

4. **Optimization Levels**: Higher optimization levels (`-O2`, `-O3`) may affect backtrace accuracy. Use `-O1` or `-O0` for best results.

5. **Interworking**: The backtrace engine works with code compiled for different architectures (68k vs PPC) as long as the frame pointers are maintained correctly.

---

## 📚 See Also

- [BOOTLOADER-API-SPEC.md](BOOTLOADER-API-SPEC.md) - Complete API specification
- [QEMU-DETECTION.md](QEMU-DETECTION.md) - QEMU detection methods
- [ARCHITECTURE.md](ARCHITECTURE.md) - Overall bootloader architecture
- [BACKTRACE.md](BACKTRACE.md) - Backtrace implementation details

---

*Generated by Mistral Vibe - Dual-Architecture Backtrace Engine Specification*
*Date: 2026-08-09*
