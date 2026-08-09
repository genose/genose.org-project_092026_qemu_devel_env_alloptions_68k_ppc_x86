# Developer API Reference

## Overview

The Custom Bootloader provides a comprehensive API for developers to interact with the boot environment. This API is available at fixed addresses starting at **0x2000** and provides functions for memory management, debugging, CPU operations, and more.

## API Region Layout

```
Address Range     Size    Purpose                    Read/Write
─────────────────────────────────────────────────────────────────
0x2000           4       BootInfo pointer             Read-only
0x2004           4       AppVectors pointer           Read/Write
0x2008           4       APITable pointer             Read-only
0x200C           4       Status flags                 Read/Write
0x2010           4       Magic number (0xDEADBEEF)    Read-only
0x2014-0x20FF   240     Reserved                     -
0x2100-0x21FF   256     Application vectors          Read/Write
```

## Magic Number

The magic number **0xDEADBEEF** at address **0x2010** can be used to verify that the API is properly initialized:

```c
uint32_t *magic = (uint32_t *)0x2010;
if (*magic == 0xDEADBEEF) {
    // API is initialized
}
```

## Data Structures

### BootInfo

The `BootInfo` structure contains information about the boot environment:

```c
typedef struct BootInfo {
    // CPU Information
    uint32_t cpu_type;           // CPU_ID_68000, CPU_ID_68040, CPU_ID_PPC601, etc.
    uint32_t cpu_features;      // Bitmask of CPU features (see below)
    
    // Memory Information
    uint32_t memory_size;       // Total RAM in bytes
    uint32_t memory_start;      // Start of available RAM
    uint32_t memory_end;        // End of available RAM
    
    // Boot Device Information
    uint32_t boot_device;       // BOOT_DEVICE_FLOPPY, BOOT_DEVICE_HD, etc.
    uint32_t boot_partition;    // Partition number (if applicable)
    uint32_t boot_lba;          // Logical Block Address of boot sector
    
    // Boot Arguments
    uint32_t boot_args[4];      // Arguments passed to booted system
    char     command_line[256];// Boot command line
    
    // Version Information
    uint32_t bootloader_version;
    uint32_t bootloader_build_date;
    
    // Reserved for future use
    uint8_t  reserved[1024 - 256 - 32];
} BootInfo;
```

#### CPU Type Constants

```c
// 68k Family
#define CPU_ID_68000     1
#define CPU_ID_68010     2
#define CPU_ID_68020     3
#define CPU_ID_68030     4
#define CPU_ID_68040     5
#define CPU_ID_68060     6

// PPC Family
#define CPU_ID_PPC601    101
#define CPU_ID_PPC603    103
#define CPU_ID_PPC604    104
#define CPU_ID_PPC750    108
#define CPU_ID_PPC7410   112
#define CPU_ID_PPC7455   140
#define CPU_ID_PPC970    153

// Generic
#define CPU_ID_UNKNOWN   0
#define CPU_ID_GENERIC   255
```

#### CPU Feature Flags

```c
// 68k Features
#define CPU_FEATURE_68K_32BIT     (1 << 0)   // 32-bit addressing support
#define CPU_FEATURE_68K_VBR       (1 << 1)   // Vector Base Register
#define CPU_FEATURE_68K_MMU       (1 << 2)   // Memory Management Unit
#define CPU_FEATURE_68K_CACHE     (1 << 3)   // Cache support
#define CPU_FEATURE_68K_BURST     (1 << 4)   // Burst mode support
#define CPU_FEATURE_68K_TYPE7     (1 << 5)   // Type 7 stack frames

// PPC Features
#define CPU_FEATURE_PPC_64BIT     (1 << 16)  // 64-bit mode support
#define CPU_FEATURE_PPC_ALTIVEC   (1 << 17)  // AltiVec support
#define CPU_FEATURE_PPC_SMP       (1 << 18)  // Symmetric Multiprocessing
#define CPU_FEATURE_PPC_MMU       (1 << 19)  // Memory Management Unit
#define CPU_FEATURE_PPC_FPU       (1 << 20)  // Floating Point Unit

// Common Features
#define CPU_FEATURE_MMU          (CPU_FEATURE_68K_MMU | CPU_FEATURE_PPC_MMU)
```

#### Boot Device Constants

```c
#define BOOT_DEVICE_NONE         0
#define BOOT_DEVICE_FLOPPY       1
#define BOOT_DEVICE_HD           2
#define BOOT_DEVICE_CD           3
#define BOOT_DEVICE_NETWORK      4
#define BOOT_DEVICE_USB          5
#define BOOT_DEVICE_DEFAULT      255
```

### AppVectors

The `AppVectors` structure contains application-specific entry points and callbacks:

```c
typedef struct AppVectors {
    // Entry points
    void     (*app_entry)(BootInfo *info);    // Main application entry
    void     (*app_init)(BootInfo *info);     // Initialization callback
    void     (*app_panic)(const char *msg);    // Panic/error handler
    void     (*app_exit)(int code);           // Exit handler
    
    // Memory layout
    uint32_t app_stack_ptr;                   // Application stack pointer
    uint32_t app_stack_size;                  // Stack size
    uint32_t app_heap_start;                   // Heap start address
    uint32_t app_heap_size;                    // Heap size
    
    // Application info
    char     app_name[64];                    // Application name
    uint32_t app_version;                      // Application version
    uint32_t app_flags;                        // Application flags
    
    // Reserved
    uint8_t  reserved[64];
} AppVectors;
```

### APITable

The `APITable` structure contains function pointers to all API functions:

```c
typedef struct APITable {
    // Memory operations
    void*    (*malloc)(size_t size);
    void     (*free)(void* ptr);
    void*    (*realloc)(void* ptr, size_t size);
    void*    (*memcpy)(void* dest, const void* src, size_t n);
    void*    (*memmove)(void* dest, const void* src, size_t n);
    void*    (*memset)(void* s, int c, size_t n);
    int      (*memcmp)(const void* s1, const void* s2, size_t n);
    
    // String operations
    int      (*strcmp)(const char* s1, const char* s2);
    char*    (*strcpy)(char* dest, const char* src);
    char*    (*strncpy)(char* dest, const char* src, size_t n);
    size_t   (*strlen)(const char* s);
    char*    (*strcat)(char* dest, const char* src);
    char*    (*strchr)(const char* s, int c);
    char*    (*strrchr)(const char* s, int c);
    
    // Debug operations
    void     (*printf)(const char* format, ...);
    void     (*sprintf)(char* str, const char* format, ...);
    void     (*hexdump)(void* addr, size_t len);
    void     (*backtrace)(void);
    void     (*dump_registers)(void);
    
    // CPU operations
    void     (*cpu_halt)(void);
    void     (*cpu_reboot)(void);
    void     (*cpu_idle)(void);
    uint32_t (*cpu_get_id)(void);
    uint32_t (*cpu_get_pvr)(void);
    void     (*cpu_set_irq)(int enable);
    
    // I/O operations
    void     (*console_putc)(char c);
    char     (*console_getc)(void);
    void     (*console_puts)(const char* s);
    void     (*console_write)(const void* buf, size_t len);
    int      (*console_read)(void* buf, size_t len);
    
    // Time operations
    uint32_t (*timer_get_ticks)(void);
    void     (*timer_delay)(uint32_t ms);
    
    // Disk operations
    int      (*disk_open)(uint32_t device);
    int      (*disk_read)(uint32_t device, uint64_t lba, void* buf, size_t count);
    int      (*disk_write)(uint32_t device, uint64_t lba, const void* buf, size_t count);
    
    // Reserved for future expansion
    uint8_t  reserved[256];
} APITable;
```

## API Function Reference

### Memory Operations

#### malloc

```c
void* malloc(size_t size);
```

Allocates memory from the heap.

**Parameters:**
- `size`: Number of bytes to allocate

**Returns:**
- Pointer to allocated memory, or NULL if allocation fails

**Example:**
```c
int *array = (int *)api->malloc(10 * sizeof(int));
if (array) {
    // Use array
    api->free(array);
}
```

#### free

```c
void free(void* ptr);
```

Freed previously allocated memory.

**Parameters:**
- `ptr`: Pointer to memory to free

**Example:**
```c
int *array = (int *)api->malloc(10 * sizeof(int));
api->free(array);
```

#### memcpy

```c
void* memcpy(void* dest, const void* src, size_t n);
```

Copies memory from one location to another.

**Parameters:**
- `dest`: Destination buffer
- `src`: Source buffer
- `n`: Number of bytes to copy

**Returns:**
- `dest`

**Example:**
```c
char buffer[100];
api->memcpy(buffer, "Hello", 5);
```

#### memset

```c
void* memset(void* s, int c, size_t n);
```

Fills memory with a constant byte.

**Parameters:**
- `s`: Memory to fill
- `c`: Byte value to fill with
- `n`: Number of bytes to fill

**Returns:**
- `s`

**Example:**
```c
char buffer[100];
api->memset(buffer, 0, sizeof(buffer));
```

#### memcmp

```c
int memcmp(const void* s1, const void* s2, size_t n);
```

Compares two blocks of memory.

**Parameters:**
- `s1`: First block
- `s2`: Second block
- `n`: Number of bytes to compare

**Returns:**
- < 0 if s1 < s2
- 0 if s1 == s2
- > 0 if s1 > s2

### String Operations

#### strcmp

```c
int strcmp(const char* s1, const char* s2);
```

Compares two strings.

**Parameters:**
- `s1`: First string
- `s2`: Second string

**Returns:**
- < 0 if s1 < s2
- 0 if s1 == s2
- > 0 if s1 > s2

#### strcpy

```c
char* strcpy(char* dest, const char* src);
```

Copies a string.

**Parameters:**
- `dest`: Destination buffer
- `src`: Source string

**Returns:**
- `dest`

#### strlen

```c
size_t strlen(const char* s);
```

Returns the length of a string.

**Parameters:**
- `s`: String to measure

**Returns:**
- Length of string (excluding null terminator)

### Debug Operations

#### printf

```c
void printf(const char* format, ...);
```

Formatted output to console.

**Parameters:**
- `format`: Format string
- `...`: Arguments

**Supported format specifiers:**
- `%d`, `%i`: Signed integer
- `%u`: Unsigned integer
- `%x`: Hexadecimal integer
- `%s`: String
- `%c`: Character
- `%p`: Pointer
- `%%`: Literal %

**Example:**
```c
api->printf("CPU Type: 0x%X\n", boot_info->cpu_type);
api->printf("Memory: %d MB\n", boot_info->memory_size / (1024*1024));
```

#### hexdump

```c
void hexdump(void* addr, size_t len);
```

Dumps memory in hexadecimal and ASCII format.

**Parameters:**
- `addr`: Address to dump
- `len`: Number of bytes to dump

**Example:**
```c
api->hexdump((void *)0x1000, 256);
```

#### backtrace

```c
void backtrace(void);
```

Prints a backtrace of the current call stack.

**Example:**
```c
api->printf("Error occurred!\n");
api->backtrace();
```

#### dump_registers

```c
void dump_registers(void);
```

Dumps all CPU registers to the console.

### CPU Operations

#### cpu_halt

```c
void cpu_halt(void);
```

Halts the CPU.

**Note:** This function does not return.

#### cpu_reboot

```c
void cpu_reboot(void);
```

Reboots the system.

**Note:** This function does not return.

#### cpu_get_id

```c
uint32_t cpu_get_id(void);
```

Returns the CPU type identifier.

**Returns:**
- CPU_ID_68000, CPU_ID_PPC601, etc.

#### cpu_get_pvr

```c
uint32_t cpu_get_pvr(void);
```

Returns the PPC Processor Version Register (for PPC CPUs).
On 68k CPUs, returns 0.

**Returns:**
- PVR value (high 16 bits = version)

#### cpu_set_irq

```c
void cpu_set_irq(int enable);
```

Enables or disables interrupts.

**Parameters:**
- `enable`: 1 to enable interrupts, 0 to disable

### I/O Operations

#### console_putc

```c
void console_putc(char c);
```

Outputs a single character to the console.

**Parameters:**
- `c`: Character to output

#### console_getc

```c
char console_getc(void);
```

Reads a single character from the console.

**Returns:**
- Character read, or -1 if no character available

#### console_puts

```c
void console_puts(const char* s);
```

Outputs a string to the console.

**Parameters:**
- `s`: String to output

#### console_write

```c
void console_write(const void* buf, size_t len);
```

Outputs multiple bytes to the console.

**Parameters:**
- `buf`: Buffer to output
- `len`: Number of bytes to output

#### console_read

```c
int console_read(void* buf, size_t len);
```

Reads multiple bytes from the console.

**Parameters:**
- `buf`: Buffer to read into
- `len`: Maximum number of bytes to read

**Returns:**
- Number of bytes read, or -1 on error

### Time Operations

#### timer_get_ticks

```c
uint32_t timer_get_ticks(void);
```

Returns the number of ticks since boot.

**Returns:**
- Tick count

**Note:** Tick frequency is CPU-dependent.

#### timer_delay

```c
void timer_delay(uint32_t ms);
```

Delays for a specified number of milliseconds.

**Parameters:**
- `ms`: Milliseconds to delay

### Disk Operations

#### disk_open

```c
int disk_open(uint32_t device);
```

Opens a disk device.

**Parameters:**
- `device`: Device identifier (0 = first floppy, 1 = first HD, etc.)

**Returns:**
- 0 on success, -1 on error

#### disk_read

```c
int disk_read(uint32_t device, uint64_t lba, void* buf, size_t count);
```

Reads sectors from a disk.

**Parameters:**
- `device`: Device identifier
- `lba`: Logical Block Address to read from
- `buf`: Buffer to read into
- `count`: Number of sectors to read

**Returns:**
- Number of sectors read, or -1 on error

**Note:** Sector size is typically 512 bytes.

#### disk_write

```c
int disk_write(uint32_t device, uint64_t lba, const void* buf, size_t count);
```

Writes sectors to a disk.

**Parameters:**
- `device`: Device identifier
- `lba`: Logical Block Address to write to
- `buf`: Buffer to write from
- `count`: Number of sectors to write

**Returns:**
- Number of sectors written, or -1 on error

## Usage Examples

### Example 1: Basic Application

```c
#include <stdint.h>

// API pointer at fixed address
#define API_TABLE_ADDR   0x2008
#define BOOTINFO_ADDR    0x2000

typedef struct APITable APITable;
typedef struct BootInfo BootInfo;

extern void main_app(BootInfo *info);

void _start(void) {
    // Get API table pointer
    APITable *api = *(APITable **)API_TABLE_ADDR;
    
    // Get boot info
    BootInfo *boot_info = *(BootInfo **)BOOTINFO_ADDR;
    
    // Display welcome message
    api->printf("Welcome to MyApp!\n");
    api->printf("CPU: %s\n", cpu_name(boot_info->cpu_type));
    api->printf("Memory: %d MB\n", boot_info->memory_size / (1024*1024));
    
    // Call main application
    main_app(boot_info);
    
    // Halt
    api->cpu_halt();
}

const char* cpu_name(uint32_t cpu_id) {
    switch (cpu_id) {
        case CPU_ID_68000: return "Motorola 68000";
        case CPU_ID_68040: return "Motorola 68040";
        case CPU_ID_PPC601: return "PowerPC 601";
        case CPU_ID_PPC750: return "PowerPC 750 (G3)";
        case CPU_ID_PPC7410: return "PowerPC 7410 (G4)";
        default: return "Unknown";
    }
}
```

### Example 2: Memory Allocation

```c
void memory_demo(APITable *api) {
    int *array;
    int i;
    
    // Allocate array
    array = (int *)api->malloc(100 * sizeof(int));
    if (!array) {
        api->printf("Allocation failed!\n");
        return;
    }
    
    // Initialize array
    for (i = 0; i < 100; i++) {
        array[i] = i * 2;
    }
    
    // Display some values
    for (i = 0; i < 10; i++) {
        api->printf("array[%d] = %d\n", i, array[i]);
    }
    
    // Free memory
    api->free(array);
}
```

### Example 3: Disk Access

```c
void load_file(APITable *api, const char* filename) {
    uint8_t buffer[512];
    int result;
    
    // Open first hard disk
    result = api->disk_open(1);
    if (result < 0) {
        api->printf("Failed to open disk\n");
        return;
    }
    
    // Read first sector
    result = api->disk_read(1, 0, buffer, 1);
    if (result < 0) {
        api->printf("Failed to read sector\n");
        return;
    }
    
    // Display hex dump
    api->printf("First sector:\n");
    api->hexdump(buffer, 512);
}
```

### Example 4: Setting Up AppVectors

```c
void panic_handler(const char *msg) {
    APITable *api = *(APITable **)0x2008;
    api->printf("PANIC: %s\n", msg);
    api->backtrace();
    api->cpu_halt();
}

void init_app_vectors(void) {
    AppVectors *app_vec = *(AppVectors **)0x2004;
    
    app_vec->app_entry = main_app;
    app_vec->app_init = app_init;
    app_vec->app_panic = panic_handler;
    app_vec->app_stack_ptr = 0x00200000;  // 2MB stack
    app_vec->app_stack_size = 1024 * 1024;  // 1MB stack
    app_vec->app_heap_start = 0x00300000;  // Heap starts at 3MB
    app_vec->app_heap_size = 8 * 1024 * 1024;  // 8MB heap
}
```

## Application-Specific Vectors (0x2100-0x21FF)

The address range **0x2100-0x21FF** is reserved for application-specific vectors. Developers can use this space to store their own function pointers, configuration, or data.

### Example: Custom Vectors

```c
#define APP_VECTOR_BASE   0x2100

typedef struct MyAppVectors {
    void (*init)(void);
    void (*update)(void);
    void (*render)(void);
    void (*shutdown)(void);
    uint32_t config_flags;
    char name[32];
} MyAppVectors;

// Set up custom vectors
MyAppVectors *my_vectors = (MyAppVectors *)APP_VECTOR_BASE;
my_vectors->init = my_init;
my_vectors->update = my_update;
my_vectors->render = my_render;
my_vectors->shutdown = my_shutdown;
```

## Error Handling

The API provides several mechanisms for error handling:

### Status Flags (0x200C)

```c
#define STATUS_OK               0x00000000
#define STATUS_ERROR            0xFFFFFFFF
#define STATUS_BOOT_FAILED      0x00000001
#define STATUS_OUT_OF_MEMORY    0x00000002
#define STATUS_DISK_ERROR       0x00000003
```

### Panic Handler

The `app_panic` callback in `AppVectors` is called when a unrecoverable error occurs:

```c
void my_panic_handler(const char *msg) {
    APITable *api = *(APITable **)0x2008;
    
    // Display panic message
    api->printf("\n*** PANIC ***\n");
    api->printf("%s\n", msg);
    
    // Dump registers
    api->dump_registers();
    
    // Show backtrace
    api->backtrace();
    
    // Halt
    api->cpu_halt();
}
```

## Version Compatibility

The bootloader API is designed to be backward compatible. When new functions are added to the `APITable`, they are placed at the end of the structure to avoid breaking existing code.

### Checking API Version

```c
#define API_VERSION 1

void check_api_version(void) {
    BootInfo *boot_info = *(BootInfo **)0x2000;
    
    if (boot_info->bootloader_version >= API_VERSION) {
        // API is compatible
    } else {
        // Older API version - may need compatibility layer
    }
}
```

## Best Practices

1. **Always check for NULL**: Many API functions return NULL or -1 on error.
2. **Don't assume memory layout**: Use the provided memory functions.
3. **Handle errors gracefully**: Provide meaningful error messages.
4. **Use the provided debug functions**: They're optimized for the platform.
5. **Test on multiple CPU types**: Ensure your code works on all target CPUs.
6. **Keep the stack small**: The bootloader has limited stack space.
7. **Use the console functions**: They're more reliable than direct hardware access.
8. **Set up your AppVectors early**: This ensures proper error handling.

## Common Pitfalls

1. **Not checking API initialization**: Always verify the magic number at 0x2010.
2. **Assuming 64-bit support**: Not all CPUs support 64-bit operations.
3. **Ignoring alignment requirements**: Some CPUs require aligned memory access.
4. **Using floating point without checking**: Not all CPUs have FPU support.
5. **Hardcoding addresses**: Use the provided pointers instead.
6. **Not handling interrupts properly**: Disable interrupts during critical sections.

## Advanced Topics

### Direct Hardware Access

While the API provides abstractions for most operations, sometimes direct hardware access is necessary. Be aware of CPU-specific differences.

### Custom Exception Handlers

You can override the default exception handlers:

```c
void my_bus_error_handler(void) {
    APITable *api = *(APITable **)0x2008;
    api->printf("Bus Error!\n");
    api->dump_registers();
    api->cpu_halt();
}

// Install custom handler (68k example)
*(void **)0x00000008 = my_bus_error_handler;
```

### Early Boot Hooks

To execute code very early in the boot process, you can set up a hook in the reset vector:

```assembly
; 68k example
.org 0x00000000
.long 0x00100000      ; SP
.long early_boot_hook   ; PC (instead of main_entry)

early_boot_hook:
    ; Do early initialization
    bsr   my_early_init
    
    ; Chain to normal entry
    bra   main_entry
```

## API Index

### Memory Functions
- `malloc` - Allocate memory
- `free` - Free memory
- `realloc` - Reallocate memory
- `memcpy` - Copy memory
- `memmove` - Move memory
- `memset` - Fill memory
- `memcmp` - Compare memory

### String Functions
- `strcmp` - Compare strings
- `strcpy` - Copy string
- `strncpy` - Copy string (with length)
- `strlen` - Get string length
- `strcat` - Concatenate strings
- `strchr` - Find character in string
- `strrchr` - Find last character in string

### Debug Functions
- `printf` - Formatted output
- `sprintf` - Formatted output to string
- `hexdump` - Hexadecimal memory dump
- `backtrace` - Show call stack
- `dump_registers` - Show CPU registers

### CPU Functions
- `cpu_halt` - Halt CPU
- `cpu_reboot` - Reboot system
- `cpu_idle` - Enter idle state
- `cpu_get_id` - Get CPU type
- `cpu_get_pvr` - Get PPC PVR
- `cpu_set_irq` - Enable/disable interrupts

### I/O Functions
- `console_putc` - Output character
- `console_getc` - Input character
- `console_puts` - Output string
- `console_write` - Output bytes
- `console_read` - Input bytes

### Time Functions
- `timer_get_ticks` - Get tick count
- `timer_delay` - Delay execution

### Disk Functions
- `disk_open` - Open disk device
- `disk_read` - Read from disk
- `disk_write` - Write to disk
