# Backtrace Implementation Documentation

## Overview

The backtrace functionality provides stack walking capabilities for both 68k and PowerPC architectures, allowing developers to debug crashes and trace execution flow. This document describes the implementation details for both architectures.

## Backtrace Concepts

A backtrace (or stack trace) is a report of the call stack at a particular point in program execution. It shows the sequence of function calls that led to the current point, which is essential for debugging.

### Key Components

1. **Stack Frame**: A block of memory on the stack that contains:
   - Return address (where to go back after the function returns)
   - Saved registers
   - Local variables
   - Function parameters

2. **Frame Pointer**: A register that points to the current stack frame (usually A6 on 68k, R1 on PPC)

3. **Stack Walking**: The process of traversing the stack from the current frame to the outermost frame

## 68k Backtrace Implementation

### Stack Frame Types

The 68k architecture has different stack frame types depending on the CPU model:

#### Standard Frame (68000-68030)

```
Higher Addresses
+------------------+
|   Return PC     |  <- Address to return to
+------------------+
|   Saved A6/FP   |  <- Previous frame pointer
+------------------+
|   Saved A5      |  <- Saved registers
+------------------+
|   Saved A4      |
+------------------+
|   ...            |
+------------------+
|   Saved D7      |
+------------------+
|   Local vars    |  <- Local variables
+------------------+
|   Function args |  <- Function parameters
+------------------+
Lower Addresses
```

#### Type 7 Frame (68040/68060)

The 68040 and 68060 use an extended stack frame format (Type 7) for exceptions:

```
Higher Addresses
+------------------+
| Format Word      |  0x7000 + Vector Number
+------------------+
| Vector Offset    |  Offset within vector table
+------------------+
| Exception PC     |  Address where exception occurred
+------------------+
| Exception Format |  Format/version info
+------------------+
| CPU Version      |  For multi-CPU systems
+------------------+
| Data/Address     |  Fault-specific data
+------------------+
| ...              |  Additional CPU-specific info
+------------------+
Lower Addresses
```

For normal function calls, the 68040+ still uses a standard frame similar to earlier models.

### 68k Backtrace Algorithm

```assembly
; Backtrace function for 68k
; Input: None
; Output: Prints backtrace to console
; Clobbers: D0-D7, A0-A6

.global backtrace_68k
backtrace_68k:
    ; Save current frame pointer
    move.l %a6, %d7               ; Save current FP in D7
    
    ; Print header
    pea   msg_backtrace(%pc)
    jsr   display_string
    addq.l #4, %sp
    
    ; Start with frame count
    moveq  #0, %d6               ; Frame counter
    
backtrace_loop_68k:
    ; Check if we have a valid frame pointer
    cmp.l  #0x10000, %d7         ; Below 64KB is invalid
    bls    backtrace_done_68k
    
    ; Print frame number
    move.l %d6, -(sp)
    pea   msg_frame(%pc)
    jsr   printf
    addq.l #8, %sp
    
    ; Get return address (at FP + 0)
    move.l (%d7), %a0            ; Get return PC
    
    ; Print return address
    move.l %a0, -(sp)
    pea   msg_addr(%pc)
    jsr   printf
    addq.l #8, %sp
    
    ; Try to look up symbol (if symbol table is available)
    move.l %a0, -(sp)
    jsr   lookup_symbol
    addq.l #4, %sp
    tst.l  %d0
    beq    no_symbol_68k
    
    ; Print symbol name
    move.l %d0, %a0
    pea   msg_symbol(%pc)
    jsr   printf
    addq.l #4, %sp
    
o_symbol_68k:
    ; Move to previous frame
    move.l 4(%d7), %d7           ; Get previous FP (at FP + 4)
    
    ; Increment frame counter
    addq.l #1, %d6
    
    ; Check for reasonable frame count
    cmp.l  #100, %d6
    bls    backtrace_loop_68k
    
backtrace_done_68k:
    ; Print footer
    pea   msg_backtrace_end(%pc)
    jsr   display_string
    addq.l #4, %sp
    
    rts

msg_backtrace:
    .asciz "\r\nBacktrace:\r\n"
msg_frame:
    .asciz "  Frame %d: "
msg_addr:
    .asciz "return to 0x%08X"
msg_symbol:
    .asciz " (%s)"
msg_backtrace_end:
    .asciz "\r\nEnd of backtrace\r\n"
```

### Type 7 Frame Handling (68040+)

For handling Type 7 exception frames:

```assembly
; Handle Type 7 frame for exception backtrace
backtrace_type7_68k:
    ; Check if this is a Type 7 frame
    move.l (%a6), %d0            ; Get format word
    andi.l #0xF000, %d0          ; Mask to get type
    cmpi.l #0x7000, %d0          ; Type 7?
    bne    standard_frame_68k
    
    ; Extract vector offset
    move.l (%a6), %d0
    andi.l #0x0FFF, %d0          ; Get vector offset
    
    ; Print exception info
    pea   msg_exception(%pc)
    jsr   display_string
    addq.l #4, %sp
    
    ; Print vector number
    move.l %d0, -(sp)
    pea   msg_vector(%pc)
    jsr   printf
    addq.l #8, %sp
    
    ; Get exception PC (at FP + 4)
    move.l 4(%a6), %a0
    
    ; Continue with standard processing
    bra   process_return_addr_68k

msg_exception:
    .asciz "\r\nException "
msg_vector:
    .asciz "Vector 0x%X"
```

### Register-Based Backtrace (68000-68030)

For CPUs without frame pointers:

```assembly
; Alternative backtrace using saved registers
; This is less reliable but works when no frame pointer is used
backtrace_registers_68k:
    ; Start from current stack pointer
    move.l %sp, %a0
    
    ; Walk the stack looking for return addresses
    ; This is heuristic-based and may not be accurate
    
    ; Look for addresses that look like code
    ; (high addresses, aligned, within text segment)
    
    ; This approach is less reliable and should be used
    ; only when frame pointers are not available
    
    rts
```

## PowerPC Backtrace Implementation

### PPC Stack Frame

The PowerPC uses a simpler stack frame structure:

```
Higher Addresses
+------------------+
|   Back Chain    |  <- Points to previous frame (or 0)
+------------------+
|   Saved LR      |  <- Link Register (return address)
+------------------+
|   Saved CR      |  <- Condition Register (optional)
+------------------+
|   Saved R31     |  <- Saved general registers
+------------------+
|   ...            |  <- R30, R29, etc. (if saved)
+------------------+
|   Local vars    |  <- Local variables
+------------------+
|   Function args |  <- Function parameters (if passed on stack)
+------------------+
Lower Addresses
```

The frame pointer (R1) points to the back chain word.

### PPC Backtrace Algorithm

```assembly
; Backtrace function for PPC
; Input: None
; Output: Prints backtrace to console
; Clobbers: R0-R12

.global backtrace_ppc
backtrace_ppc:
    ; Save current frame pointer (R1)
    mfctr 0                  ; Save CTR
    mr    10, 1             ; Save FP in R10
    
    ; Print header
    lis   3, msg_backtrace@h
    ori   3, 3, msg_backtrace@l
    bl    display_string_ppc
    
    ; Start with frame count
    li    9, 0              ; Frame counter in R9
    
backtrace_loop_ppc:
    ; Check if we have a valid frame pointer
    cmpwi 10, 0x1000        ; Below 4KB is invalid
    blt   backtrace_done_ppc
    
    ; Print frame number
    mr    3, 9
    lis   4, msg_frame@h
    ori   4, 4, msg_frame@l
    bl    printf_ppc
    
    ; Get return address (LR saved at FP + 4)
    lwz   3, 4(10)         ; Get saved LR
    
    ; Print return address
    mr    4, 3
    lis   5, msg_addr@h
    ori   5, 5, msg_addr@l
    bl    printf_ppc
    
    ; Try to look up symbol
    mr    3, 4
    bl    lookup_symbol_ppc
    
    ; If symbol found, print it
    cmpwi 3, 0
    beq   no_symbol_ppc
    
    lis   4, msg_symbol@h
    ori   4, 4, msg_symbol@l
    bl    printf_ppc
    
no_symbol_ppc:
    ; Move to previous frame via back chain
    lwz   10, 0(10)        ; Get back chain pointer
    
    ; Check for back chain of 0 (end of chain)
    cmpwi 10, 0
    beq   backtrace_done_ppc
    
    ; Increment frame counter
    addi  9, 9, 1
    
    ; Check for reasonable frame count
    cmpwi 9, 100
    blt   backtrace_loop_ppc
    
backtrace_done_ppc:
    ; Print footer
    lis   3, msg_backtrace_end@h
    ori   3, 3, msg_backtrace_end@l
    bl    display_string_ppc
    
    mtctr 0                  ; Restore CTR
    blr                       ; Return

msg_backtrace:
    .asciz "\r\nBacktrace:\r\n"
msg_frame:
    .asciz "  Frame %d: "
msg_addr:
    .asciz "return to 0x%08X"
msg_symbol:
    .asciz " (%s)"
msg_backtrace_end:
    .asciz "\r\nEnd of backtrace\r\n"
```

### PPC Exception Frame Handling

For handling exception frames (which have a different format):

```assembly
; Handle PPC exception frame
backtrace_exception_ppc:
    ; Check if this is an exception frame
    ; Exception frames have specific layout
    
    ; SRR0 contains the address where exception occurred
    mfspr 3, SRR0
    
    ; Print exception info
    lis   4, msg_exception@h
    ori   4, 4, msg_exception@l
    bl    printf_ppc
    
    ; Get exception type from DSISR or similar
    ; This is CPU-specific
    
    rblr

msg_exception:
    .asciz "\r\nException at 0x%08X"
```

## Common Backtrace Interface

To provide a unified interface across both architectures:

```assembly
; Common backtrace entry point
.global backtrace
backtrace:
    ; Check architecture
    ; For 68k: branch to backtrace_68k
    ; For PPC: branch to backtrace_ppc
    
    ; Architecture detection already done at boot
    ; CPU type is stored in D7/R7
    
    ; This is a simplified version
    ; The actual implementation checks the CPU type
    ; and branches accordingly
    
    ; For now, assume we know the architecture
    ; (set during boot)
    
    rts
```

## Symbol Lookup

The backtrace can optionally look up symbol names for addresses using a symbol table.

### Symbol Table Format

```c
typedef struct SymbolEntry {
    uint32_t address;
    char     name[64];
} SymbolEntry;
```

### Symbol Lookup Function

```assembly
; Look up symbol for an address
; Input: Address in D0/R3
; Output: Symbol name pointer in D0/R3, or 0 if not found

.global lookup_symbol
lookup_symbol:
    ; Save registers
    ; Binary search through symbol table
    ; Return symbol name or 0
    
    ; Implementation depends on symbol table format
    ; and where it's stored in memory
    
    rts
```

### Example Symbol Table

```c
SymbolEntry symbol_table[] = {
    {0x00010000, "main_entry"},
    {0x00010100, "init_cpu"},
    {0x00010200, "detect_cpu"},
    {0x00010300, "init_memory"},
    {0x00020000, "api_malloc"},
    {0x00020100, "api_free"},
    ; ... more symbols
    {0x00000000, ""}  ; End marker
};
```

## Backtrace Integration with Exception Handlers

The backtrace is automatically called by exception handlers:

### 68k Exception Handler with Backtrace

```assembly
bus_error_handler:
    ; Save all registers
    movem.l %d0-%d7/%a0-%a7, -(sp)
    
    ; Print error message
    pea   msg_bus_error(%pc)
    jsr   display_string
    addq.l #4, %sp
    
    ; Print backtrace
    jsr   backtrace_68k
    
    ; Dump registers
    jsr   dump_registers_68k
    
    ; Loop forever
bus_error_loop:
    bra   bus_error_loop

msg_bus_error:
    .asciz "\r\nBus Error!\r\n"
```

### PPC Exception Handler with Backtrace

```assembly
dsi_handler:
    ; Save registers
    mflr  0
    stw   0, 4(1)          ; Save LR
    stwu  1, -64(1)        ; Allocate stack space
    stw   3, 8(1)          ; Save R3
    ; ... save more registers
    
    ; Print error message
    lis   3, msg_dsi@h
    ori   3, 3, msg_dsi@l
    bl    display_string_ppc
    
    ; Print backtrace
    bl    backtrace_ppc
    
    ; Dump registers
    bl    dump_registers_ppc
    
    ; Restore and return (or halt)
    lwz   3, 8(1)
    lwz   0, 4(1)
    mtlr  0
    addi  1, 1, 64
    blr

msg_dsi:
    .asciz "\r\nData Storage Interrupt!\r\n"
```

## Backtrace API

The backtrace functionality is exposed through the API table:

```c
// In APITable structure
typedef struct APITable {
    ; ... other functions
    
    // Backtrace function
    void (*backtrace)(void);
    
    // ... other functions
} APITable;
```

### Usage from C Code

```c
void my_function(void) {
    APITable *api = *(APITable **)0x2008;
    
    // Trigger a backtrace
    api->printf("About to trace...\n");
    api->backtrace();
    
    // Or call directly in case of error
    if (error_occurred) {
        api->printf("Error! Tracing...\n");
        api->backtrace();
        api->cpu_halt();
    }
}
```

## Backtrace Configuration

The backtrace can be configured through compile-time options:

### Configuration Options

```c
// In config.h
#define BACKTRACE_MAX_FRAMES  100     // Maximum frames to trace
#define BACKTRACE_SHOW_SYMBOLS 1       // Enable symbol lookup
#define BACKTRACE_SHOW_REGS    1       // Show register values
```

### Frame Count Limitation

To prevent infinite loops:

```assembly
; In backtrace functions
    moveq  #0, %d6               ; Frame counter
    
backtrace_loop:
    ; ... process frame
    
    addq.l #1, %d6
    cmp.l  #BACKTRACE_MAX_FRAMES, %d6
    bge    backtrace_done
    
    ; ... continue loop
```

## Backtrace Output Examples

### 68k Backtrace Example

```
Backtrace:
  Frame 0: return to 0x00010120 (main_entry)
  Frame 1: return to 0x000102A0 (init_system)
  Frame 2: return to 0x00010340 (setup_memory)
  Frame 3: return to 0x00010480 (detect_cpu)
  Frame 4: return to 0x00010050 (_start)
End of backtrace
```

### PPC Backtrace Example

```
Backtrace:
  Frame 0: return to 0x000201A0 (api_malloc)
  Frame 1: return to 0x00030120 (app_init)
  Frame 2: return to 0x00030000 (_start)
End of backtrace
```

### Exception Backtrace Example

```
Bus Error!
Exception Vector 0x2 at 0x00010500
Backtrace:
  Frame 0: return to 0x00010500 (faulty_function)
  Frame 1: return to 0x00010480 (caller_function)
  Frame 2: return to 0x00010050 (_start)
End of backtrace

Registers:
D0: 0xDEADBEEF  D1: 0x12345678  D2: 0x00000000  D3: 0xFFFFFFFF
D4: 0x00010500  D5: 0x00100000  D6: 0x00000001  D7: 0x00000000
A0: 0x00100000  A1: 0x00100020  A2: 0x00100040  A3: 0x00100060
A4: 0x00100080  A5: 0x001000A0  A6: 0x0010FF00  A7: 0x0010FFE0
USP: 0x0010FFE0
SR: 0x2700
PC: 0x00010500
```

## Implementation Notes

### 68k-Specific Considerations

1. **Frame Pointer Usage**: Not all 68k code uses frame pointers. The backtrace may be less reliable without them.

2. **Stack Direction**: The 68k stack grows downward (towards lower addresses).

3. **Register Saving**: The calling convention affects which registers are saved and where.

4. **Leaf Functions**: Functions that don't call other functions may not have a stack frame.

### PPC-Specific Considerations

1. **Link Register**: The PPC uses the LR (Link Register) for return addresses, which is saved on the stack.

2. **Back Chain**: The back chain (saved FP) points to the previous frame, forming a linked list.

3. **ABI Variations**: Different ABIs (SVR4, Darwin, etc.) may have different calling conventions.

4. **Optimizations**: Optimized code may not save the back chain, making backtrace less reliable.

### Common Issues

1. **Optimized Code**: High optimization levels may eliminate frame pointers, making backtrace unreliable.

2. **Stack Corruption**: If the stack is corrupted, backtrace may fail or produce incorrect results.

3. **Interruptions**: Backtrace should be called with interrupts disabled to prevent stack changes.

4. **Symbol Table**: Symbol lookup requires a symbol table, which may not always be available.

## Testing Backtrace

To test the backtrace functionality:

```c
void test_backtrace(void) {
    APITable *api = *(APITable **)0x2008;
    
    api->printf("Testing backtrace...\n");
    
    // Call a few nested functions
    function_a();
    
    api->printf("Backtrace test complete\n");
}

void function_a(void) {
    function_b();
}

void function_b(void) {
    function_c();
}

void function_c(void) {
    APITable *api = *(APITable **)0x2008;
    api->printf("In function_c\n");
    api->backtrace();
}
```

This should produce a backtrace showing the call chain: test_backtrace -> function_a -> function_b -> function_c.

## Performance Considerations

Backtrace has the following performance characteristics:

1. **Time Complexity**: O(n) where n is the number of frames
2. **Space Complexity**: O(1) - uses a fixed amount of stack space
3. **Execution Time**: Typically < 1ms for reasonable stack depths

For production use, consider:

1. **Limiting Frame Count**: Prevent infinite loops with a maximum frame limit.
2. **Lazy Symbol Lookup**: Only look up symbols when needed, not for every frame.
3. **Caching**: Cache symbol lookups if the same addresses are traced frequently.

## Future Enhancements

1. **Improved Symbol Lookup**: Support for ELF/DWARF symbol tables.
2. **Source File/Line Numbers**: Include file and line number information.
3. **Multiple Thread Support**: Backtrace for multi-threaded environments.
4. **Stack Usage Analysis**: Show stack usage in addition to backtrace.
5. **Call Graph**: Generate a call graph from backtrace data.
6. **Exception Context**: Show additional context for exception backtraces.
7. **Register Values**: Show register values for each frame.

## References

- [Motorola 68k Manuals](https://www.nxp.com/docs/en/reference-manual/MC68000UM.pdf)
- [PowerPC Architecture](https://www.ibm.com/docs/en/aix/7.2?topic=reference-powerpc-architecture)
- [Executable and Linking Format (ELF)](https://en.wikipedia.org/wiki/Executable_and_Linkable_Format)
- [DWARF Debugging Information Format](https://en.wikipedia.org/wiki/DWARF)
