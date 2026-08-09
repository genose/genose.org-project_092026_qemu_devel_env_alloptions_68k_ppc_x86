# Bootloader Architecture Documentation

## Overview

The Custom Bootloader is designed as a FATBIN executable that can run on both Motorola 68k and PowerPC architectures. It provides a unified interface for booting operating systems or applications with full CPU detection, exception handling, and debugging support.

## FATBIN Structure

The FATBIN format allows a single binary to contain code for multiple architectures. On entry, the bootloader:

1. **Determines the architecture** (68k vs PPC) through instruction testing
2. **Branches to architecture-specific code**
3. **Performs CPU-specific detection** within each family
4. **Initializes the appropriate environment**

```
FATBIN Layout:
+------------------+
| Common Entry     |  <- Both 68k and PPC start here
| (0x0000-0x00FF)  |
+------------------+
| 68k Code         |  <- 68000-68060 specific
| (0x0100-0x1FFF)  |
+------------------+
| PPC Code         |  <- PPC601-970 specific
| (0x2000-0x3FFF)  |
+------------------+
| Common Data      |  <- Shared between architectures
| (0x4000-0x5FFF)  |
+------------------+
| API Region       |  <- Developer API at 0x2000-0x21FF
| (0x2000-0x21FF)  |
+------------------+
```

## Architecture Detection

### 68k vs PPC Detection

The bootloader uses the fact that certain instructions are illegal on one architecture but valid on another:

```assembly
# On 68k, this is valid; on PPC, it's an illegal instruction
move.l %d0, %a0

# On PPC, this is valid; on 68k, it would crash
mfspr 3, 287  # Read PVR
```

The entry point contains code that will execute differently on each architecture, allowing the bootloader to determine which path to take.

### 68k CPU Detection Flow

```
┌─────────────────────┐
│   Entry Point        │
│   (Common Code)      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   Test: movec vbr,d0 │
│   (68000 will trap)  │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     ▼           ▼
┌─────────┐ ┌─────────────┐
│ 68000   │ │ 68010+/68020 │
│Detected │ │    +        │
└─────────┘ └──────┬──────┘
                   │
                   ▼
            ┌──────────────┐
            │ Test: cpusha  │
            │ (68030 will   │
            │    trap)      │
            └──────┬───────┘
                   │
             ┌─────┴─────┐
             ▼           ▼
        ┌────────┐ ┌────────┐
        │ 68030  │ │ 68040/  │
        │Detected│ │  68060  │
        └────────┘ └────────┘
```

### PPC CPU Detection Flow

PowerPC CPUs are identified by reading the Processor Version Register (PVR) at SPR 287:

```
┌─────────────────────┐
│   Entry Point        │
│   (PPC Code)         │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   mfspr r3, 287      │
│   (Read PVR)         │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   Extract high 16    │
│   bits (Version)     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   Switch (PVR):      │
│   0x0001 -> 601      │
│   0x0003 -> 603      │
│   0x0004 -> 604      │
│   0x0008 -> 750 (G3) │
│   0x000C -> 7410(G4) │
│   0x800C -> 7455     │
│   0x0039 -> 970 (G5) │
└─────────────────────┘
```

## Memory Layout

### 68k Memory Map

```
Address Range     Purpose
─────────────────────────────────
0x00000000-0x0000003F  Exception Vectors (Bus Error, Address Error, etc.)
0x00000040-0x000003FF  Reserved for future vectors
0x00000400-0x00000FFF  Early boot stack
0x00001000           GDB breakpoint (hardcoded)
0x00001004           Status code storage
0x00002000-0x000021FF  Developer API region
0x00010000-0x0001FFFF  Boot info structure
0x00100000           Stack pointer initial value
0x01000000-0x01FFFFFF  Kernel/OS loading area
```

### PPC Memory Map

```
Address Range     Purpose
─────────────────────────────────
0x00000000-0x000000FF  Exception vectors (reset, machine check, etc.)
0x00000100-0x00000FFF  Early boot code
0x00001000           GDB breakpoint
0x00001004           Status code storage
0x00002000-0x000021FF  Developer API region
0x00010000-0x0001FFFF  Boot info structure
0x00100000           Stack pointer initial value
0x01000000-0x01FFFFFF  Kernel/OS loading area
```

## Exception Handling

### 68k Exception Vectors

The 68k family has 256 exception vectors (0x00-0xFF). The bootloader initializes:

```
Vector  Address   Handler
─────────────────────────────────
0x00     0x00000000  Initial SP (reset)
0x01     0x00000004  Initial PC (start)
0x02     0x00000008  Bus Error
0x03     0x0000000C  Address Error
0x04     0x00000010  Illegal Instruction
0x05     0x00000014  Zero Divide
...     ...         ...
```

### 68040+ Type 7 Stack Frames

The 68040 and 68060 use extended stack frames (Type 7) for exceptions:

```
Stack Layout (growing downward):
+------------------+
| Format Word      |  <- Identifies frame type
+------------------+
| Vector Offset    |  <- Which vector was triggered
+------------------+
| Exception PC     |  <- Address where exception occurred
+------------------+
| Exception Format |  <- Additional info
+------------------+
| CPU Version      |  <- For multi-CPU systems
+------------------+
| Data/Address     |  <- Fault-specific data
+------------------+
| ...              |  <- Additional CPU-specific info
+------------------+
```

### PPC Exception Vectors

PowerPC uses a different exception model with SPR-based handling:

```
Exception Type     Vector Address  Handler
─────────────────────────────────────────
Reset             0x00000100      system_reset
Machine Check     0x00000200      machine_check
DSI (Data)        0x00000300      data_storage
ISI (Instruction) 0x00000400      instruction_storage
External          0x00000500      external_interrupt
Alignment         0x00000600      alignment
Program           0x00000700      program_exception
...               ...             ...
```

## API Region (0x2000-0x21FF)

The API region provides a standardized interface for developers to interact with the bootloader:

```
Address     Size    Purpose
─────────────────────────────────
0x2000      4       BootInfo pointer
0x2004      4       AppVectors pointer
0x2008      4       APITable pointer
0x200C      4       Status flags
0x2010      4       Magic number (0xDEADBEEF)
0x2014-0x20FF      Reserved
0x2100-0x21FF      Application-specific vectors
```

### BootInfo Structure

```c
typedef struct {
    uint32_t cpu_type;           // CPU_ID_68000, CPU_ID_PPC601, etc.
    uint32_t cpu_features;      // Feature flags
    uint32_t memory_size;       // Total RAM in bytes
    uint32_t memory_start;      // Start of available RAM
    uint32_t boot_device;       // Which device to boot from
    uint32_t boot_args[4];      // Arguments passed to booted system
    char     command_line[256];// Boot command line
    uint8_t  reserved[1024];   // Future expansion
} BootInfo;
```

### AppVectors Structure

```c
typedef struct {
    void     (*app_entry)(void);      // Application entry point
    void     (*app_init)(BootInfo*);   // Initialization callback
    void     (*app_panic)(const char*); // Panic/error handler
    uint32_t app_stack_ptr;           // Application stack pointer
    uint32_t app_heap_start;           // Heap start address
    uint32_t app_heap_size;            // Heap size
    uint8_t  reserved[64];            // Future expansion
} AppVectors;
```

### APITable Structure

```c
typedef struct {
    // Memory operations
    void*    (*malloc)(size_t size);
    void     (*free)(void* ptr);
    void*    (*memcpy)(void* dest, const void* src, size_t n);
    void*    (*memset)(void* s, int c, size_t n);
    
    // String operations
    int      (*strcmp)(const char* s1, const char* s2);
    char*    (*strcpy)(char* dest, const char* src);
    size_t   (*strlen)(const char* s);
    
    // Debug operations
    void     (*printf)(const char* format, ...);
    void     (*hexdump)(void* addr, size_t len);
    void     (*backtrace)(void);
    
    // CPU-specific
    void     (*cpu_halt)(void);
    void     (*cpu_reboot)(void);
    uint32_t (*cpu_get_pvr)(void);
    
    // I/O operations
    void     (*console_putc)(char c);
    char     (*console_getc)(void);
    void     (*console_puts)(const char* s);
    
    uint8_t  reserved[128];
} APITable;
```

## Boot Process

See [BOOT_PROCESS.md](BOOT_PROCESS.md) for detailed boot sequence documentation.

## CPU-Specific Features

### 68k Features by Model

| Feature               | 68000 | 68010 | 68020 | 68030 | 68040 | 68060 |
|-----------------------|-------|-------|-------|-------|-------|-------|
| 32-bit addressing    |   No  |  Yes  |  Yes  |  Yes  |  Yes  |  Yes  |
| VBR (Vector Base)    |   No  |  Yes  |  Yes  |  Yes  |  Yes  |  Yes  |
| MMU                  |   No  |   No  |  Yes  |  Yes  |  Yes  |  Yes  |
| Cache                |   No  |   No  |  Yes  |  Yes  |  Yes  |  Yes  |
| CPUSHA instruction   |   No  |   No  |   No  |   No  |  Yes  |  Yes  |
| Type 7 stack frames  |   No  |   No  |   No  |   No  |  Yes  |  Yes  |
| Burst mode           |   No  |   No  |   No  |  Yes  |  Yes  |  Yes  |

### PPC Features by Model

| Feature               | 601   | 603   | 604   | 750   | 7410  | 7455  | 970   |
|-----------------------|-------|-------|-------|-------|-------|-------|-------|
| 32-bit mode          |  Yes  |  Yes  |  Yes  |  Yes  |  Yes  |  Yes  |  Yes  |
| 64-bit mode          |   No  |   No  |   No  |   No  |   No  |   No  |  Yes  |
| AltiVec             |   No  |   No  |   No  |   No  |  Yes  |  Yes  |  Yes  |
| MMU                  |  Yes  |  Yes  |  Yes  |  Yes  |  Yes  |  Yes  |  Yes  |
| L1 Cache             | 32KB  | 32KB  | 32KB  | 32KB  | 32KB  | 32KB  | 64KB  |
| L2 Cache             |   No  | 256KB| 256KB| 256KB| 256KB| 256KB| 512KB |
| SMP support          |   No  |   No  |  Yes  |   No  |  Yes  |  Yes  |  Yes  |

## Implementation Details

### Fatbin Entry Point

The entry point is carefully crafted to work on both architectures:

```assembly
# FATBIN Entry (works on both 68k and PPC)
.global _start
.text
.org 0x0000

_start:
    # This instruction is valid on 68k (NOP-like) but will
    # cause an illegal instruction exception on PPC
    .word 0x4E71  # 68k: NOP, PPC: undefined
    
    # If we get here, we're on 68k
    bra determine_68k
    
    # PPC code would have jumped to its handler
    .org 0x100
    
ppc_entry:
    mfspr 3, 287  # Read PVR
    # ... PPC detection continues
```

### Build System

The Makefile supports multiple build configurations:

- **Pure 68k**: For 68k-only systems
- **Pure PPC**: For PPC-only systems  
- **FATBIN**: Combined binary for both architectures
- **Debug builds**: With additional symbols and checks
- **Release builds**: Optimized for size

See [Makefile](../Makefile) for build options.

## Portability

The bootloader is designed to be portable across:

- **Emulators**: QEMU, Shoebill, Basilisk II, SheepShaver
- **Real Hardware**: With appropriate adaptations
- **Operating Systems**: Can boot various OSes or serve as a standalone environment

### QEMU Compatibility

The bootloader works with QEMU's emulation of:
- `qemu-system-m68k` for 68k emulation
- `qemu-system-ppc` for PPC emulation
- Custom machine types (mac99, mac99_via, etc.)

### Shoebill Compatibility

Shoebill-specific features:
- MMU initialization similar to Shoebill's approach
- Exception vector setup matching Shoebill's expectations
- Memory layout compatible with Shoebill's Mac OS emulation

## Future Enhancements

- [ ] Support for additional CPU models (ColdFire, 68080, etc.)
- [ ] Graphical boot menu
- [ ] Filesystem support for loading from disk
- [ ] Network boot capabilities
- [ ] SMP (symmetric multiprocessing) support
- [ ] Power management features
- [ ] Additional debugging protocols (KGDB, etc.)
