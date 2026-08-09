# Boot Process Documentation

## Overview

This document describes the complete boot process of the Custom Bootloader from power-on/reset to handing off control to the operating system or application.

## Boot Stages

### Stage 0: Reset Vector Initialization

When the CPU comes out of reset, it begins execution at a predefined address:
- **68k**: Address 0x00000000 (reset vector contains initial SP and PC)
- **PPC**: Address 0x00000100 (reset vector)

The first 8 bytes at address 0 are:
- Bytes 0-3: Initial Stack Pointer (SP)
- Bytes 4-7: Initial Program Counter (PC)

```assembly
; Reset vector for 68k
.org 0x00000000
.long 0x00100000      ; Initial SP (1MB)
.long main_entry      ; Initial PC
```

### Stage 1: Architecture Detection

The bootloader must immediately determine which architecture it's running on.

#### FATBIN Entry Strategy

The entry code uses a clever trick: it executes an instruction that's valid on one architecture but not the other.

```assembly
; FATBIN Entry Point
.global _start
.text
.org 0x0000

_start:
    ; First instruction: 0x4E71
    ; On 68k: This is NOP (No Operation)
    ; On PPC: This is undefined/illegal
    .word 0x4E71
    
    ; If we get here without exception, we're on 68k
    bra determine_68k_cpu
    
    ; If we got an exception, the PPC exception handler
    ; will have already jumped to PPC code
```

The exception handlers are set up to catch illegal instruction exceptions and branch to the appropriate architecture code.

#### Alternative: Separate Entry Points

An alternative approach (used in some configurations):

```assembly
; 68k entry at 0x0000
.org 0x0000
_start_68k:
    move.w #0x2700, %sr    ; Mask interrupts
    bra   determine_68k_cpu

; PPC entry at 0x0100
.org 0x0100
_start_ppc:
    li    0, 0            ; Clear R0
    mfspr 3, 287          ; Read PVR
    bra   determine_ppc_cpu
```

The FATBIN links both together with a common header that branches appropriately.

### Stage 2: CPU-Specific Detection

Once the architecture is known, the bootloader performs detailed CPU detection.

#### 68k Detection Sequence

```
Step 1: Test for movec instruction (68000 vs 68010+)
    └─ If illegal instruction → 68000
    └─ If success → continue

Step 2: Test for cpusha instruction (68030 vs 68040+)
    └─ If illegal instruction → 68010/68020/68030
    └─ If success → 68040/68060

Step 3: For 68010/68020/68030, distinguish:
    - Check for VBR register (68010+)
    - Check for 32-bit addressing (68020+)
    - Check for MMU (68030+)
```

#### PPC Detection Sequence

```
Step 1: Read PVR (Processor Version Register) at SPR 287

Step 2: Extract version field (high 16 bits of PVR)

Step 3: Compare against known values:
    0x0001 → PPC601
    0x0003 → PPC603
    0x0004 → PPC604
    0x0008 → PPC750 (G3)
    0x000C → PPC7410 (G4)
    0x800C → PPC7455 (G4 Enhanced)
    0x0039 → PPC970 (G5)
    
Step 4: If unknown PVR, use generic PPC configuration
```

### Stage 3: CPU Initialization

After detection, each CPU requires specific initialization.

#### 68k Initialization

```assembly
; Common 68k initialization
init_68k:
    ; Set up stack pointer
    move.l #0x00100000, %sp
    
    ; Mask all interrupts (level 7)
    move.w #0x2700, %sr
    
    ; Initialize exception vectors
    jsr   init_exception_vectors
    
    ; CPU-specific initialization
    cmp.l #CPU_ID_68040, %d7
    beq   init_68040
    cmp.l #CPU_ID_68060, %d7
    beq   init_68060
    bra   init_68k_generic
```

##### 68040/68060 Specific Initialization

```assembly
init_68040:
    ; Enable burst mode
    move.l #0x80800000, %d0
    movec  %d0, %CACR
    
    ; Initialize MMU if needed
    ; (Optional, depending on configuration)
    
    ; Set up Type 7 stack frames
    ; (Already handled by exception handlers)
    rts
```

#### PPC Initialization

```assembly
; Common PPC initialization
init_ppc:
    ; Set up stack pointer
    lis   1, 0x0010
    ori   1, 1, 0x0000
    
    ; Enable machine check exceptions
    mfmsr 3
    ori   3, 3, 0x0001  ; Set ME bit
    mtmsr 3
    
    ; Initialize exception vectors
    jsr   init_ppc_vectors
    
    ; CPU-specific initialization
    cmpwi 7, CPU_ID_PPC601
    beq    init_ppc601
    cmpwi 7, CPU_ID_PPC970
    beq    init_ppc970
    bra    init_ppc_generic
```

##### PPC970 (64-bit) Specific Initialization

```assembly
init_ppc970:
    ; Enable 64-bit mode if needed
    mfmsr 3
    ori   3, 3, 0x8000  ; Set SF bit (64-bit)
    mtmsr 3
    
    ; Additional 970-specific setup
    ; (AltiVec, enhanced features, etc.)
    rfi
```

### Stage 4: Exception Vector Setup

The bootloader installs its own exception handlers for debugging and error reporting.

#### 68k Exception Vectors

```assembly
init_exception_vectors:
    ; Install bus error handler
    move.l #bus_error_handler, 0x00000008
    
    ; Install address error handler
    move.l #addr_error_handler, 0x0000000C
    
    ; Install illegal instruction handler
    move.l #ill_inst_handler, 0x00000010
    
    ; Install zero divide handler
    move.l #zero_div_handler, 0x00000014
    
    ; Install CHK/TRAP handlers
    move.l #chk_handler, 0x00000018
    move.l #trap_handler, 0x0000001C
    
    ; Additional vectors as needed
    rts
```

#### PPC Exception Vectors

```assembly
init_ppc_vectors:
    ; PPC uses different mechanism - IVOR registers
    ; or direct memory mapping
    
    ; Set up machine check handler
    mtspr IVOR0, machine_check_handler
    
    ; Set up DSI handler
    mtspr IVOR1, dsi_handler
    
    ; Set up ISI handler
    mtspr IVOR2, isi_handler
    
    ; Set up external interrupt handler
    mtspr IVOR3, ext_int_handler
    
    blr
```

### Stage 5: Console/Display Initialization

The bootloader initializes basic output capabilities for status messages.

#### 68k Display Initialization

For 68k systems (especially Mac emulation):

```assembly
init_display_68k:
    ; On real hardware: initialize video chip
    ; On QEMU: use serial output or debug console
    
    ; Display "Loading..." message
    pea   msg_loading(%pc)
    jsr   display_string
    addq.l #4, %sp
    
    rts

msg_loading:
    .asciz "Loading ...\r\n"
```

#### PPC Display Initialization

For PPC systems:

```assembly
init_display_ppc:
    ; Initialize serial port or framebuffer
    ; Display "Loading..." message
    lis   3, msg_loading@h
    ori   3, 3, msg_loading@l
    bl    display_string_ppc
    
    blr

msg_loading:
    .asciz "Loading ...\r\n"
```

### Stage 6: Memory Initialization

The bootloader sets up memory regions and detects available RAM.

#### Memory Detection

```assembly
; 68k memory detection
detect_memory_68k:
    ; Try to detect RAM size
    ; This is emulator-specific
    
    ; For QEMU: assume configuration
    ; For Shoebill: query emulator
    ; For real hardware: probe
    
    move.l #128*1024*1024, %d0  ; Default 128MB
    rts
```

#### Memory Map Setup

```
Memory Regions:
────────────────────────────────────────────────────
Address Range      Size       Purpose
────────────────────────────────────────────────────
0x00000000-0x000FFFFF   1MB       Boot ROM / Vectors
0x00100000-0x001FFFFF   1MB       Bootloader code/data
0x00200000-0x002FFFFF   1MB       API region
0x01000000-0x0FFFFFFF  128MB      Available RAM
0x10000000-0x1FFFFFFF  256MB      Extended RAM (if present)
```

### Stage 7: API Initialization

The bootloader sets up the Developer API at fixed addresses.

```assembly
init_api:
    ; Set up BootInfo structure
    move.l #boot_info, 0x2000
    
    ; Set up AppVectors
    move.l #app_vectors, 0x2004
    
    ; Set up APITable
    move.l #api_table, 0x2008
    
    ; Set magic number
    move.l #0xDEADBEEF, 0x2010
    
    ; Clear status flags
    clr.l 0x200C
    
    rts
```

### Stage 8: Boot Device Selection

The bootloader determines which device to boot from.

#### Boot Priority

1. **Floppy Disk** (if present)
2. **Hard Disk** (primary IDE/SCSI)
3. **CD-ROM** (if available)
4. **Network** (if configured)
5. **Default/ROM** (fallback)

```assembly
select_boot_device:
    ; Check for bootable floppy
    bsr   check_floppy
    tst.l %d0
    bne   boot_floppy
    
    ; Check for bootable HD
    bsr   check_harddisk
    tst.l %d0
    bne   boot_harddisk
    
    ; Check for bootable CD
    bsr   check_cdrom
    tst.l %d0
    bne   boot_cdrom
    
    ; Fallback to default
    bra   boot_default
```

### Stage 9: Loading Operating System or Application

The bootloader loads the OS or application from the selected device.

#### Loading Process

```assembly
load_os:
    ; Display loading message
    pea   msg_booting(%pc)
    jsr   display_string
    addq.l #4, %sp
    
    ; Open boot device
    ; Read boot sector/loader
    ; Verify signature
    ; Load into memory at 0x01000000
    ; Verify checksum
    ; Jump to entry point
    
    ; If error, display failure message
    ; Set error code at 0x1004
    ; Halt or wait for debug
```

#### Progress Reporting

The bootloader displays standardized messages:

```
Message                 When Displayed
─────────────────────────────────────────────────
"Loading ..."          Stage 1: Initial detection
"(CPU_NAME) running " Stage 3: After CPU init
"Boot OS ..."         Stage 8: Before jumping to OS
"Failure (code 0xXX)" On unrecoverable error
```

### Stage 10: Jump to OS/Application

The final stage: handing off control.

```assembly
jump_to_os:
    ; Set up parameters for OS
    ; - BootInfo pointer in register
    ; - Command line address
    ; - Memory map
    
    ; Set GDB breakpoint at 0x1000
    ; This allows debugging the OS boot
    move.l #0x1000, %d0
    
    ; Clear status at 0x1004 (success)
    clr.l 0x1004
    
    ; Display final message
    pea   msg_booting_cpu(%pc)
    jsr   display_string
    addq.l #4, %sp
    
    ; Jump to OS entry point
    ; (Stored in BootInfo)
    move.l boot_info+boot_entry_offset, %a0
    jmp   (%a0)
    
    ; Should never get here
    bra   halt_system
```

## Error Handling

If an error occurs during boot, the bootloader:

1. Saves error code to 0x1004
2. Displays "Failure (code 0xXX)" message
3. Sets breakpoint at 0x1000
4. Halts or enters debug loop

```assembly
handle_boot_error:
    ; Save error code
    move.l %d0, 0x1004
    
    ; Display failure message
    pea   msg_failure(%pc)
    jsr   display_string
    addq.l #4, %sp
    
    ; Display error code
    move.l %d0, -(sp)
    jsr   display_hex
    addq.l #4, sp
    
    ; Set breakpoint
    move.l #0x1000, %d0
    
    ; Halt or loop
    bra   halt_loop

msg_failure:
    .asciz "\r\nFailure (code 0x"
```

## Debugging Support

The bootloader includes several debugging features:

### GDB Breakpoints

- **0x1000**: Main breakpoint (entry/exit)
- **0x1004**: Status code (0 = success)
- Individual exception handlers can also set breakpoints

### Serial Debug Output

All messages are also sent to serial port (if available) at 115200 baud.

### Memory Dump

The debug helpers include functions to dump memory:

```assembly
dump_memory:
    ; Parameters: address in %a0, length in %d0
    ; Dumps memory in hex/ascii format
    ; Uses serial output
    rts
```

### Register Dump

Exception handlers automatically dump registers:

```assembly
bus_error_handler:
    ; Save all registers
    movem.l %d0-%d7/%a0-%a7, -(sp)
    
    ; Extract fault information
    ; (PC, address, etc.)
    
    ; Call register dump
    jsr   dump_registers
    
    ; Loop forever
    bra   .
```

## Complete Boot Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        POWER ON / RESET                        │
└─────────────────────────────────────────┬───────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Stage 0: Reset Vector                        │
│              CPU starts at address 0x0000 (68k) or 0x100 (PPC)  │
│                   Initial SP and PC loaded                     │
└─────────────────────────────────────────┬───────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Stage 1: Architecture Detection              │
│              Execute test instruction to identify 68k vs PPC    │
│                          Branch to appropriate code             │
└─────────────────────────────────────────┬───────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Stage 2: CPU-Specific Detection               │
│  68k: movec test → cpusha test → determine exact model         │
│  PPC: Read PVR → extract version → determine exact model       │
│                         Store CPU ID in %d7/r7                  │
└─────────────────────────────────────────┬───────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Stage 3: CPU Initialization                  │
│  Set up SP, mask interrupts, enable features, initialize MMU   │
│                     Display "(CPU_NAME) running ..."            │
└─────────────────────────────────────────┬───────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Stage 4: Exception Vector Setup              │
│  Install bus error, address error, illegal instruction, etc.  │
│                          handlers                               │
└─────────────────────────────────────────┬───────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Stage 5: Display Initialization              │
│              Initialize console/serial output                  │
│                     Display "Loading ..."                      │
└─────────────────────────────────────────┬───────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Stage 6: Memory Initialization               │
│              Detect RAM size, set up memory regions             │
└─────────────────────────────────────────┬───────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Stage 7: API Initialization                  │
│  Set up BootInfo, AppVectors, APITable at fixed addresses        │
└─────────────────────────────────────────┬───────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Stage 8: Boot Device Selection               │
│  Check floppy → HD → CD → network → default                      │
└─────────────────────────────────────────┬───────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Stage 9: Load OS/Application                  │
│  Load from boot device into memory, verify checksum             │
│                     Display "Boot OS ..."                       │
└─────────────────────────────────────────┬───────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Stage 10: Jump to OS/Application             │
│  Set parameters, clear status, set breakpoint, jump to entry    │
└─────────────────────────────────────────────────────────────┘
```

## Configuration Options

The bootloader can be configured through compile-time options:

- **DEBUG**: Enable verbose output and additional checks
- **BOOT_DEVICE**: Default boot device (floppy, hd, cd, net)
- **MEMORY_SIZE**: Default memory size (auto-detect if not specified)
- **SERIAL_OUTPUT**: Enable serial debug output
- **GDB_BREAKPOINT**: Enable GDB breakpoint at 0x1000

## Testing

The bootloader includes a test mode that can be activated:

```bash
# Build with tests
make debug

# Run in QEMU with serial output
qemu-system-ppc -kernel bootloader_fatbin -serial stdio -nographic
```

Test output includes:
- CPU detection results
- Memory detection
- Exception handling verification
- API function tests
- Backtrace tests

## Performance Considerations

The bootloader is optimized for:

1. **Speed**: Minimal CPU-specific code paths
2. **Size**: Compact code for small boot ROMs
3. **Reliability**: Extensive error checking
4. **Debuggability**: Comprehensive debug output

For production use, build with `make release` to disable debug features and optimize for size.
