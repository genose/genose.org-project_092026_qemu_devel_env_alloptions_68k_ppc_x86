# Helper Functions Reference

## Overview

The Custom Bootloader provides a comprehensive set of helper functions for common operations such as string manipulation, memory operations, debugging, and I/O. These helpers are available both as standalone assembly functions and through the API table.

## Helper Categories

1. **String Helpers** - String manipulation functions
2. **Memory Helpers** - Memory operations and manipulation
3. **Debug Helpers** - Debugging output and memory examination
4. **Math Helpers** - Mathematical operations
5. **Conversion Helpers** - Data type conversions
6. **I/O Helpers** - Input/Output operations

## String Helpers

### Overview

The string helpers provide C-style string operations optimized for the target architectures. They are implemented in assembly for maximum performance.

### Function List

#### strcpy - Copy String

```assembly
; 68k implementation
; Input:  A0 = destination, A1 = source
; Output: A0 = destination
; Clobbers: D0, A0, A1

.global strcpy
strcpy:
    move.l %a0, %d0        ; Save destination
    
strcpy_loop:
    move.b (%a1)+, %d0     ; Get byte from source, increment source
    move.b %d0, (%a0)+     ; Store byte to destination, increment destination
    bne    strcpy_loop     ; Continue until null terminator
    
    move.l %a0, %d0        ; Return destination
    rts
```

```c
char* strcpy(char* dest, const char* src);
```

Copies the string pointed to by `src` (including the null terminator) to the buffer pointed to by `dest`.

**Parameters:**
- `dest`: Destination buffer (must be large enough)
- `src`: Source string

**Returns:**
- `dest`

**Example:**
```c
char buffer[100];
strcpy(buffer, "Hello, World!");
```

#### strncpy - Copy String with Length Limit

```c
char* strncpy(char* dest, const char* src, size_t n);
```

Copies at most `n` characters from `src` to `dest`. If `src` is shorter than `n`, the remainder of `dest` is filled with null bytes.

**Parameters:**
- `dest`: Destination buffer
- `src`: Source string
- `n`: Maximum number of characters to copy

**Returns:**
- `dest`

#### strlen - String Length

```assembly
; 68k implementation
; Input:  A0 = string
; Output: D0 = length
; Clobbers: D0, A0

.global strlen
strlen:
    moveq  #0, %d0        ; Initialize length to 0
    
strlen_loop:
    tst.b  (%a0)+         ; Test byte, increment pointer
    beq    strlen_done    ; If null, we're done
    addq.l #1, %d0        ; Increment length
    bra    strlen_loop    ; Continue
    
strlen_done:
    rts
```

```c
size_t strlen(const char* s);
```

Returns the length of the string `s` (excluding the null terminator).

**Parameters:**
- `s`: String to measure

**Returns:**
- Length of string in bytes

#### strcmp - String Compare

```assembly
; 68k implementation
; Input:  A0 = string1, A1 = string2
; Output: D0 = comparison result
; Clobbers: D0, D1, A0, A1

.global strcmp
strcmp:
    moveq  #0, %d0        ; Initialize result
    
strcmp_loop:
    move.b (%a0)+, %d0     ; Get byte from string1
    move.b (%a1)+, %d1     ; Get byte from string2
    
    cmp.b  %d0, %d1        ; Compare bytes
    bne    strcmp_done     ; If different, we're done
    
    tst.b  %d0            ; Check for null terminator
    bne    strcmp_loop     ; If not null, continue
    
    ; Both strings ended at the same time
    moveq  #0, %d0        ; Return 0 (equal)
    rts
    
strcmp_done:
    ; Subtract to get comparison result
    ext.w  %d0
    ext.w  %d1
    sub.w  %d1, %d0
    rts
```

```c
int strcmp(const char* s1, const char* s2);
```

Compares two strings lexicographically.

**Parameters:**
- `s1`: First string
- `s2`: Second string

**Returns:**
- < 0 if s1 < s2
- 0 if s1 == s2
- > 0 if s1 > s2

#### strcat - String Concatenate

```c
char* strcat(char* dest, const char* src);
```

Appends the string `src` to the end of the string `dest`.

**Parameters:**
- `dest`: Destination string (must be large enough)
- `src`: Source string to append

**Returns:**
- `dest`

#### strchr - Find Character in String

```c
char* strchr(const char* s, int c);
```

Finds the first occurrence of character `c` in string `s`.

**Parameters:**
- `s`: String to search
- `c`: Character to find

**Returns:**
- Pointer to the first occurrence of `c` in `s`, or NULL if not found

#### strrchr - Find Last Character in String

```c
char* strrchr(const char* s, int c);
```

Finds the last occurrence of character `c` in string `s`.

**Parameters:**
- `s`: String to search
- `c`: Character to find

**Returns:**
- Pointer to the last occurrence of `c` in `s`, or NULL if not found

#### strstr - Find Substring

```c
char* strstr(const char* haystack, const char* needle);
```

Finds the first occurrence of substring `needle` in string `haystack`.

**Parameters:**
- `haystack`: String to search
- `needle`: Substring to find

**Returns:**
- Pointer to the first occurrence of `needle` in `haystack`, or NULL if not found

## Memory Helpers

### Overview

The memory helpers provide optimized functions for memory operations such as copying, filling, and comparing memory blocks.

### Function List

#### memcpy - Copy Memory

```assembly
; 68k implementation
; Input:  A0 = destination, A1 = source, D0 = size (in bytes)
; Output: A0 = destination
; Clobbers: D0-D2, A0, A1

.global memcpy
memcpy:
    moveq  #0, %d2        ; Initialize counter
    
memcpy_loop:
    move.b (%a1)+, %d1     ; Get byte from source
    move.b %d1, (%a0)+     ; Store byte to destination
    addq.l #1, %d2        ; Increment counter
    cmp.l  %d0, %d2        ; Compare with size
    bne    memcpy_loop     ; Continue if not done
    
    move.l %a0, %d0        ; Return destination
    rts
```

```c
void* memcpy(void* dest, const void* src, size_t n);
```

Copies `n` bytes from the memory block pointed to by `src` to the memory block pointed to by `dest`.

**Parameters:**
- `dest`: Destination buffer
- `src`: Source buffer
- `n`: Number of bytes to copy

**Returns:**
- `dest`

**Note:** If the source and destination overlap, the behavior is undefined. Use `memmove` for overlapping regions.

#### memmove - Move Memory (Handles Overlap)

```c
void* memmove(void* dest, const void* src, size_t n);
```

Copies `n` bytes from `src` to `dest`. Handles overlapping regions correctly by copying from the appropriate direction.

**Parameters:**
- `dest`: Destination buffer
- `src`: Source buffer
- `n`: Number of bytes to copy

**Returns:**
- `dest`

#### memset - Fill Memory

```assembly
; 68k implementation
; Input:  A0 = memory, D0 = byte value, D1 = size
; Output: A0 = memory
; Clobbers: D0-D2, A0

.global memset
memset:
    moveq  #0, %d2        ; Initialize counter
    
memset_loop:
    move.b %d0, (%a0)+     ; Store byte
    addq.l #1, %d2        ; Increment counter
    cmp.l  %d1, %d2        ; Compare with size
    bne    memset_loop     ; Continue if not done
    
    move.l %a0, %d0        ; Return memory
    rts
```

```c
void* memset(void* s, int c, size_t n);
```

Fills the first `n` bytes of the memory block pointed to by `s` with the byte value `c`.

**Parameters:**
- `s`: Memory block to fill
- `c`: Byte value to fill with (converted to unsigned char)
- `n`: Number of bytes to fill

**Returns:**
- `s`

#### memcmp - Compare Memory

```c
int memcmp(const void* s1, const void* s2, size_t n);
```

Compares the first `n` bytes of the memory blocks pointed to by `s1` and `s2`.

**Parameters:**
- `s1`: First memory block
- `s2`: Second memory block
- `n`: Number of bytes to compare

**Returns:**
- < 0 if s1 < s2
- 0 if s1 == s2
- > 0 if s1 > s2

#### memchr - Find Character in Memory

```c
void* memchr(const void* s, int c, size_t n);
```

Finds the first occurrence of byte `c` in the first `n` bytes of the memory block pointed to by `s`.

**Parameters:**
- `s`: Memory block to search
- `c`: Byte to find (converted to unsigned char)
- `n`: Number of bytes to search

**Returns:**
- Pointer to the first occurrence of `c`, or NULL if not found

#### Zero Memory

```c
void bzero(void* s, size_t n);
```

Sets the first `n` bytes of the memory block pointed to by `s` to zero. Equivalent to `memset(s, 0, n)`.

**Parameters:**
- `s`: Memory block to zero
- `n`: Number of bytes to zero

## Debug Helpers

### Overview

The debug helpers provide functions for outputting debug information, examining memory, and formatting data for display.

### Function List

#### printf - Formatted Output

```c
void printf(const char* format, ...);
```

Formats and prints text to the console.

**Parameters:**
- `format`: Format string
- `...`: Arguments

**Supported format specifiers:**
- `%d`, `%i`: Signed integer (16-bit or 32-bit)
- `%u`: Unsigned integer
- `%x`: Hexadecimal integer (lowercase)
- `%X`: Hexadecimal integer (uppercase)
- `%s`: String
- `%c`: Character
- `%p`: Pointer (32-bit hex)
- `%%`: Literal %

**Example:**
```c
printf("Value: %d (0x%X), String: %s\n", value, value, "Hello");
```

#### sprintf - Formatted Output to String

```c
void sprintf(char* str, const char* format, ...);
```

Formats text and stores it in the buffer pointed to by `str`.

**Parameters:**
- `str`: Destination buffer
- `format`: Format string
- `...`: Arguments

**Warning:** Does not check buffer size. Ensure the buffer is large enough.

#### hexdump - Hexadecimal Memory Dump

```c
void hexdump(void* addr, size_t len);
```

Dumps memory in hexadecimal and ASCII format.

**Parameters:**
- `addr`: Address to start dump
- `len`: Number of bytes to dump

**Output Format:**
```
00010000: 48 65 6C 6C 6F 20 57 6F 72 6C 64 21 00 00 00 00  Hello World!....
00010010: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
```

#### dump_memory - Dump Memory with Formatting

```c
void dump_memory(void* addr, size_t len, int width);
```

Dumps memory with customizable formatting.

**Parameters:**
- `addr`: Address to start dump
- `len`: Number of bytes to dump
- `width`: Number of bytes per line (typically 16)

#### dump_registers - Dump CPU Registers

```c
void dump_registers(void);
```

Dumps all CPU registers to the console. The output format is CPU-specific.

**68k Output:**
```
Registers:
D0: 0x00000000  D1: 0x00000000  D2: 0x00000000  D3: 0x00000000
D4: 0x00000000  D5: 0x00000000  D6: 0x00000000  D7: 0x00000000
A0: 0x00000000  A1: 0x00000000  A2: 0x00000000  A3: 0x00000000
A4: 0x00000000  A5: 0x00000000  A6: 0x00000000  A7: 0x00000000
USP: 0x00000000
SR:  0x2700
PC:  0x00000000
```

**PPC Output:**
```
Registers:
R0:  0x00000000  R1:  0x00000000  R2:  0x00000000  R3:  0x00000000
R4:  0x00000000  R5:  0x00000000  R6:  0x00000000  R7:  0x00000000
R8:  0x00000000  R9:  0x00000000  R10: 0x00000000  R11: 0x00000000
R12: 0x00000000  R13: 0x00000000  R14: 0x00000000  R15: 0x00000000
R16: 0x00000000  R17: 0x00000000  R18: 0x00000000  R19: 0x00000000
R20: 0x00000000  R21: 0x00000000  R22: 0x00000000  R23: 0x00000000
R24: 0x00000000  R25: 0x00000000  R26: 0x00000000  R27: 0x00000000
R28: 0x00000000  R29: 0x00000000  R30: 0x00000000  R31: 0x00000000
LR:  0x00000000
CTR: 0x00000000
PCR: 0x00000000
MSR: 0x00000000
```

## Math Helpers

### Overview

The math helpers provide common mathematical operations.

### Function List

#### abs - Absolute Value

```c
int abs(int n);
```

Returns the absolute value of `n`.

#### labs - Long Absolute Value

```c
long labs(long n);
```

Returns the absolute value of `n` (32-bit).

#### min - Minimum Value

```c
int min(int a, int b);
```

Returns the smaller of `a` or `b`.

#### max - Maximum Value

```c
int max(int a, int b);
```

Returns the larger of `a` or `b`.

#### swap16 - Swap 16-bit Endianness

```c
uint16_t swap16(uint16_t value);
```

Swaps the byte order of a 16-bit value (endianness conversion).

**Example:**
```c
uint16_t le_value = swap16(be_value);  // Convert big-endian to little-endian
```

#### swap32 - Swap 32-bit Endianness

```c
uint32_t swap32(uint32_t value);
```

Swaps the byte order of a 32-bit value (endianness conversion).

## Conversion Helpers

### Overview

The conversion helpers provide functions for converting between different data representations.

### Function List

#### itoa - Integer to ASCII

```c
char* itoa(int value, char* str, int base);
```

Converts an integer to a null-terminated ASCII string.

**Parameters:**
- `value`: Integer to convert
- `str`: Destination buffer
- `base`: Base for conversion (2-36)

**Returns:**
- Pointer to the resulting string

**Example:**
```c
char buffer[32];
itoa(12345, buffer, 10);  // buffer = "12345"
itoa(12345, buffer, 16);  // buffer = "3039"
```

#### utoa - Unsigned Integer to ASCII

```c
char* utoa(unsigned int value, char* str, int base);
```

Converts an unsigned integer to a null-terminated ASCII string.

#### atoi - ASCII to Integer

```c
int atoi(const char* str);
```

Converts a string to an integer (base 10).

**Parameters:**
- `str`: String to convert

**Returns:**
- Converted integer value

#### strtoul - String to Unsigned Long

```c
unsigned long strtoul(const char* str, char** endptr, int base);
```

Converts a string to an unsigned long integer.

**Parameters:**
- `str`: String to convert
- `endptr`: Pointer to store the end of the parsed string (optional)
- `base`: Base for conversion (0 = auto-detect, 2-36)

**Returns:**
- Converted unsigned long value

## I/O Helpers

### Overview

The I/O helpers provide functions for input and output operations.

### Function List

#### putchar - Output Character

```c
int putchar(int c);
```

Outputs a single character to the console.

**Parameters:**
- `c`: Character to output

**Returns:**
- The character output, or EOF on error

#### getchar - Input Character

```c
int getchar(void);
```

Reads a single character from the console.

**Returns:**
- The character read, or EOF if no character is available

#### puts - Output String

```c
int puts(const char* s);
```

Outputs a string to the console, followed by a newline.

**Parameters:**
- `s`: String to output

**Returns:**
- Non-negative on success, EOF on error

#### gets - Input String

```c
char* gets(char* s);
```

Reads a line of input from the console.

**Parameters:**
- `s`: Buffer to store the string

**Returns:**
- `s` on success, NULL on error

**Warning:** Does not check buffer size. Use with caution.

#### puthex - Output Hexadecimal Value

```c
void puthex(uint32_t value, int width);
```

Outputs a value in hexadecimal format.

**Parameters:**
- `value`: Value to output
- `width`: Minimum number of digits (pads with leading zeros)

**Example:**
```c
puthex(0x123, 8);  // Output: "00000123"
puthex(0x123, 4);  // Output: "0123"
```

## Assembly Helpers

### Overview

The assembly helpers provide low-level functions that are difficult or impossible to implement in C.

### Function List

#### inb - Input Byte from Port

```c
uint8_t inb(uint16_t port);
```

Reads a byte from an I/O port (x86 specific).

#### outb - Output Byte to Port

```c
void outb(uint16_t port, uint8_t value);
```

Writes a byte to an I/O port (x86 specific).

#### inw - Input Word from Port

```c
uint16_t inw(uint16_t port);
```

Reads a word from an I/O port (x86 specific).

#### outw - Output Word to Port

```c
void outw(uint16_t port, uint16_t value);
```

Writes a word to an I/O port (x86 specific).

#### cli - Clear Interrupts

```c
void cli(void);
```

Disables interrupts.

#### sti - Set Interrupts

```c
void sti(void);
```

Enables interrupts.

#### save_flags - Save Interrupt Flags

```c
unsigned long save_flags(void);
```

Saves the current interrupt flags and disables interrupts.

**Returns:**
- Previous interrupt flags

#### restore_flags - Restore Interrupt Flags

```c
void restore_flags(unsigned long flags);
```

Restores previously saved interrupt flags.

**Parameters:**
- `flags`: Flags to restore (from save_flags)

## Usage Examples

### Example 1: Using String Helpers

```c
void string_example(void) {
    char buffer[100];
    char *ptr;
    
    // Copy a string
    strcpy(buffer, "Hello, World!");
    
    // Get length
    int len = strlen(buffer);
    
    // Compare strings
    if (strcmp(buffer, "Hello, World!") == 0) {
        printf("Strings are equal\n");
    }
    
    // Find a character
    ptr = strchr(buffer, 'W');
    if (ptr) {
        printf("Found 'W' at position %d\n", (int)(ptr - buffer));
    }
}
```

### Example 2: Using Memory Helpers

```c
void memory_example(void) {
    char src[100] = "Source data";
    char dst[100];
    
    // Copy memory
    memcpy(dst, src, sizeof(src));
    
    // Set memory
    memset(dst, 0, sizeof(dst));
    
    // Compare memory
    if (memcmp(src, dst, sizeof(src)) == 0) {
        printf("Memory blocks are equal\n");
    }
}
```

### Example 3: Using Debug Helpers

```c
void debug_example(void) {
    uint32_t value = 0xDEADBEEF;
    char buffer[100];
    
    // Format output
    printf("Value in hex: 0x%X\n", value);
    printf("Value in decimal: %d\n", value);
    
    // Hex dump
    hexdump(&value, sizeof(value));
    
    // Dump registers
    printf("Current registers:\n");
    dump_registers();
    
    // Formatted string
    sprintf(buffer, "Value: 0x%X", value);
    printf("Buffer: %s\n", buffer);
}
```

### Example 4: Using Conversion Helpers

```c
void conversion_example(void) {
    char buffer[32];
    int value;
    
    // Integer to string
    itoa(12345, buffer, 10);
    printf("Decimal: %s\n", buffer);
    
    itoa(12345, buffer, 16);
    printf("Hex: %s\n", buffer);
    
    // String to integer
    value = atoi("12345");
    printf("Value: %d\n", value);
    
    // Hex string to integer
    value = strtoul("0x123", NULL, 16);
    printf("Hex value: %d\n", value);
}
```

## Implementation Notes

### 68k-Specific Optimizations

The 68k implementations take advantage of the architecture's features:

1. **Auto-increment addressing**: `(%a0)+` increments the address register after each access.
2. **Database and Data Registers**: Use appropriate registers for data operations.
3. **Conditional Branches**: Use branches that don't affect condition codes unnecessarily.

### PPC-Specific Optimizations

The PPC implementations use PowerPC-specific features:

1. **Load/Store instructions**: Use `lwz` (load word zero) and `stw` (store word).
2. **Register usage**: Follow PPC calling conventions (R3-R10 for parameters, R3 for return value).
3. **Branch instructions**: Use `bl` (branch and link) for function calls.

### Common Patterns

1. **Null-terminated strings**: All string functions assume null-terminated strings.
2. **Return values**: Functions return values in D0 (68k) or R3 (PPC).
3. **Stack usage**: Functions that call other functions must preserve registers as needed.

## Performance Considerations

1. **Inline functions**: For maximum performance, consider inlining small helper functions.
2. **Unrolled loops**: For memory operations, loop unrolling can improve performance.
3. **Alignment**: Ensure memory access is properly aligned for the target architecture.
4. **Cache usage**: For PPC, consider cache effects when working with large memory blocks.

## Testing Helpers

The helper functions include test cases to verify their correctness:

```c
void test_helpers(void) {
    // Test string functions
    assert(strlen("Hello") == 5);
    assert(strcmp("Hello", "Hello") == 0);
    assert(strcmp("Hello", "World") < 0);
    
    // Test memory functions
    char src[10] = "Test";
    char dst[10];
    memcpy(dst, src, sizeof(src));
    assert(memcmp(src, dst, sizeof(src)) == 0);
    
    // Test conversion functions
    assert(atoi("123") == 123);
    assert(strtoul("0xFF", NULL, 16) == 255);
    
    printf("All helper tests passed!\n");
}
```

## References

- [Motorola 68k Manuals](https://www.nxp.com/docs/en/reference-manual/MC68000UM.pdf)
- [PowerPC Architecture](https://www.ibm.com/docs/en/aix/7.2?topic=reference-powerpc-architecture)
- [C Standard Library](https://en.cppreference.com/w/c)
