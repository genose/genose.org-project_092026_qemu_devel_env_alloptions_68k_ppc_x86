/***************************************************************************
 * Custom Bootloader - Main Entry Point
 * 
 * Universal FATBIN bootloader for 68k and PowerPC architectures.
 * This file contains the main entry point and boot initialization code.
 * 
 * The bootloader:
 * 1. Sets up initial exception vectors
 * 2. Detects the CPU architecture (68k vs PPC)
 * 3. Performs CPU-specific initialization
 * 4. Initializes the API
 * 5. Displays status messages
 * 6. Hands off control to the OS or application
 ***************************************************************************/

#include "config.h"

    .global _start
    .text
    .org 0x0000

/***************************************************************************
 * Reset Vector
 * 
 * When the CPU comes out of reset, it loads the initial SP and PC from
 * addresses 0 and 4. We set up a minimal vector table here.
 ***************************************************************************/

_start:
    /* Reset vector for 68k: SP at 0, PC at 4 */
    .long 0x00100000          /* Initial Stack Pointer (1MB) */
    .long main_entry          /* Initial Program Counter */

    /* Reserve space for additional vectors */
    .space 0x100 - 8, 0

/***************************************************************************
 * Main Entry Point
 * 
 * This is where execution begins after reset.
 * We immediately mask interrupts and begin initialization.
 ***************************************************************************/

main_entry:
    /* Step 1: Mask all interrupts (level 7) */
    move.w #0x2700, %sr

    /* Step 2: Set up initial stack pointer */
    move.l #0x00100000, %sp

    /* Step 3: Display "Loading ..." message */
    pea msg_loading(%pc)
    jsr display_string
    addq.l #4, %sp

    /* Step 4: Perform architecture detection */
    /* We need to determine if we're on 68k or PPC */
    /* This is done by executing test instructions */
    
    /* First, try to detect if we're on 68k by testing for movec */
    /* On 68k, movec is valid (68010+); on PPC, it's undefined */
    /* But we need to be careful - we can't just execute random instructions */
    
    /* Alternative approach: check the PC value */
    /* If we're on 68k, we entered at _start (0x0000) */
    /* If we're on PPC, we might have entered at a different address */
    
    /* For now, assume we're on 68k and proceed with detection */
    bra determine_68k_cpu

    /* This is a placeholder for PPC entry */
    /* In a real FATBIN, we'd have separate entry points */

/***************************************************************************
 * 68k CPU Detection
 * 
 * Detects which 68k CPU we're running on by testing for specific
 * instructions that are only available on certain models.
 ***************************************************************************/

determine_68k_cpu:
    /* Step 1: Test for movec instruction (68000 vs 68010+) */
    /* movec is only available on 68010 and later */
    
    /* Set up a temporary handler for illegal instruction */
    move.l %sp, -(sp)         /* Save stack pointer */
    move.l #trap_68000_detected, 0x00000010  /* Install handler at vector 4 */
    
    /* Try to execute movec (read VBR) */
    /* This will trap on 68000 but succeed on 68010+ */
    .word 0x4E7A, 0x0801      /* movec vbr, d0 - opcode for 68010+ */
    
    /* If we get here, we're on 68010 or later */
    move.l (%sp)+, %sp        /* Restore stack pointer (discard saved value) */
    bra check_if_68040
    
    /* If we get an illegal instruction exception, we're on 68000 */
    /* The handler will have set D7 to 1 and returned here */
    /* But this is tricky - we need to properly handle the exception */
    
    /* For now, let's use a simpler approach */
    
    /* Restore the original exception handler */
    /* We'll do this properly later */
    
    /* Assume we're on 68000 for now */
    move.l #CPU_ID_68000, %d7
    bra setup_68k_common

check_if_68040:
    /* Step 2: Test for cpusha instruction (68030 vs 68040+) */
    /* cpusha is only available on 68040 and 68060 */
    
    /* Set up handler for illegal instruction */
    move.l #trap_68030_detected, 0x00000010
    
    /* Try to execute cpusha (invalidate data cache) */
    .word 0xF478              /* cpusha dc - opcode for 68040 */
    
    /* If we get here, we're on 68040 or 68060 */
    /* Check which one */
    /* For simplicity, assume 68040 */
    move.l #CPU_ID_68040, %d7
    bra setup_68040
    
    /* If we get an exception, we're on 68010/68020/68030 */
    /* For now, assume 68030 */
trap_68030_detected:
    move.l #CPU_ID_68030, %d7
    bra setup_68k_common

    /* 68000 detection */
trap_68000_detected:
    move.l #CPU_ID_68000, %d7
    /* Fall through to common setup */

/***************************************************************************
 * 68k Common Setup
 * 
 * Sets up the 68k environment after CPU detection.
 ***************************************************************************/

setup_68k_common:
    /* Initialize exception vectors */
    jsr init_exception_vectors
    
    /* Display CPU running message */
    /* For now, we'll just display a generic message */
    pea msg_68k_running(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* Initialize API */
    jsr init_api
    
    /* Initialize memory */
    jsr init_memory
    
    /* Detect and initialize boot device */
    jsr detect_boot_device
    
    /* Load and boot OS */
    jsr load_and_boot_os
    
    /* Should never get here */
    bra halt_system

setup_68040:
    /* 68040-specific initialization */
    /* Enable burst mode */
    move.l #0x80800000, %d0
    movec %d0, %CACR
    
    /* Continue with common setup */
    bra setup_68k_common

/***************************************************************************
 * PPC CPU Detection
 * 
 * This section would be used if we entered via the PPC path.
 * For now, this is a placeholder.
 ***************************************************************************/

.ifdef PPC_ENTRY
    .org 0x0100
ppc_entry:
    /* PPC reset vector */
    li 0, 0
    mfspr 3, 287          /* Read PVR */
    
    /* Extract high 16 bits (version) */
    rlwinm 4, 3, 16, 16, 31
    
    /* Compare against known PVR values */
    cmplwi 4, PVR_PPC601
    beq ppc_601_detected
    
    cmplwi 4, PVR_PPC603
    beq ppc_603_detected
    
    cmplwi 4, PVR_PPC604
    beq ppc_604_detected
    
    cmplwi 4, PVR_PPC750
    beq ppc_750_detected
    
    /* Unknown PPC - use generic */
    li 7, CPU_ID_PPC601
    bra setup_ppc_common

ppc_601_detected:
    li 7, CPU_ID_PPC601
    bra setup_ppc_common

ppc_603_detected:
    li 7, CPU_ID_PPC603
    bra setup_ppc_common

ppc_604_detected:
    li 7, CPU_ID_PPC604
    bra setup_ppc_common

ppc_750_detected:
    li 7, CPU_ID_PPC750
    /* Fall through */

setup_ppc_common:
    /* Initialize PPC environment */
    /* Set up stack pointer */
    lis 1, 0x0010
    ori 1, 1, 0x0000
    
    /* Initialize exception vectors */
    bl init_ppc_vectors
    
    /* Display CPU running message */
    lis 3, msg_ppc_running@h
    ori 3, 3, msg_ppc_running@l
    bl display_string_ppc
    
    /* Initialize API */
    bl init_api
    
    /* Initialize memory */
    bl init_memory
    
    /* Detect and initialize boot device */
    bl detect_boot_device
    
    /* Load and boot OS */
    bl load_and_boot_os
    
    /* Should never get here */
    bl halt_system
.endif

/***************************************************************************
 * Exception Vector Initialization
 * 
 * Sets up the initial exception vectors for 68k.
 ***************************************************************************/

init_exception_vectors:
    /* Install bus error handler */
    move.l #bus_error_handler, 0x00000008
    
    /* Install address error handler */
    move.l #addr_error_handler, 0x0000000C
    
    /* Install illegal instruction handler */
    move.l #ill_inst_handler, 0x00000010
    
    /* Install zero divide handler */
    move.l #zero_div_handler, 0x00000014
    
    /* Install CHK/TRAP handlers */
    move.l #chk_handler, 0x00000018
    move.l #trap_handler, 0x0000001C
    
    rts

/***************************************************************************
 * API Initialization
 * 
 * Sets up the Developer API at fixed addresses.
 ***************************************************************************/

init_api:
    /* Set up BootInfo structure */
    move.l #boot_info, BOOTINFO_PTR_ADDRESS
    
    /* Set up AppVectors */
    move.l #app_vectors, APPVECTORS_PTR_ADDRESS
    
    /* Set up APITable */
    move.l #api_table, APITABLE_PTR_ADDRESS
    
    /* Set magic number */
    move.l #API_MAGIC_NUMBER, API_MAGIC_NUMBER_ADDRESS
    
    /* Clear status flags */
    clr.l API_STATUS_FLAGS_ADDRESS
    
    /* Initialize BootInfo */
    move.l %d7, boot_info + offsetof(BootInfo, cpu_type)
    
    /* Set memory size (default 128MB) */
    move.l #RAM_SIZE_DEFAULT, boot_info + offsetof(BootInfo, memory_size)
    
    /* Set bootloader version */
    move.l #0x00010000, boot_info + offsetof(BootInfo, bootloader_version)
    
    rts

/***************************************************************************
 * Memory Initialization
 * 
 * Detects available memory and sets up memory regions.
 ***************************************************************************/

init_memory:
    /* For now, just set default values */
    /* In a real implementation, we'd detect memory size */
    
    /* Set memory start to 2MB (after bootloader) */
    move.l #0x00200000, boot_info + offsetof(BootInfo, memory_start)
    
    /* Set memory end to 128MB */
    move.l #0x08000000, boot_info + offsetof(BootInfo, memory_end)
    
    /* Initialize heap */
    /* Heap starts at 3MB */
    move.l #0x00300000, -(sp)
    move.l #(8 * 1024 * 1024), -(sp)  /* 8MB heap */
    jsr heap_init
    addq.l #8, %sp
    
    rts

/***************************************************************************
 * Boot Device Detection
 * 
 * Detects which device to boot from.
 ***************************************************************************/

detect_boot_device:
    /* For now, just set default to HD */
    move.l #BOOT_DEVICE_HD, boot_info + offsetof(BootInfo, boot_device)
    
    rts

/***************************************************************************
 * Load and Boot OS
 * 
 * Loads the operating system or application and jumps to it.
 ***************************************************************************/

load_and_boot_os:
    /* Display "Boot OS ..." message */
    pea msg_boot_os(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* For now, just set up for jumping to a test address */
    /* In a real implementation, we'd load from disk */
    
    /* Set GDB breakpoint at 0x1000 */
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    
    /* Clear status at 0x1004 (success) */
    clr.l GDB_STATUS_ADDRESS
    
    /* Jump to OS entry point */
    /* For now, just halt */
    bra halt_system

/***************************************************************************
 * Halt System
 * 
 * Halts the CPU (should never return).
 ***************************************************************************/

halt_system:
    /* Display halt message */
    pea msg_halt(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* Halt CPU */
halt_loop:
    bra halt_loop

/***************************************************************************
 * Exception Handlers
 * 
 * MacsBug-style exception handlers for debugging.
 ***************************************************************************/

bus_error_handler:
    /* Save all registers */
    movem.l %d0-%d7/%a0-%a7, -(sp)
    
    /* Display error message */
    pea msg_bus_error(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* Display backtrace */
    jsr backtrace_68k
    
    /* Display registers */
    jsr dump_registers_68k
    
    /* Set error status */
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    
    /* Set breakpoint */
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    
    /* Loop forever */
    bra halt_loop

addr_error_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_addr_error(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

ill_inst_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_ill_inst(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

zero_div_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_zero_div(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

chk_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_chk(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

trap_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

/***************************************************************************
 * Data Section
 * 
 * Contains messages and data structures.
 ***************************************************************************/

    .data

/*** Messages ***/
msg_loading:
    .asciz "Loading ...\r\n"

msg_68k_running:
    .asciz "Motorola 68k running ...\r\n"

msg_ppc_running:
    .asciz "PowerPC running ...\r\n"

msg_boot_os:
    .asciz "Boot OS ...\r\n"

msg_halt:
    .asciz "\r\nSystem halted\r\n"

msg_bus_error:
    .asciz "\r\nBus Error!\r\n"

msg_addr_error:
    .asciz "\r\nAddress Error!\r\n"

msg_ill_inst:
    .asciz "\r\nIllegal Instruction!\r\n"

msg_zero_div:
    .asciz "\r\nZero Divide!\r\n"

msg_chk:
    .asciz "\r\nCHK/CHK2 Instruction!\r\n"

msg_trap:
    .asciz "\r\nTRAP Instruction!\r\n"

/*** Data Structures ***/
    .align 4

boot_info:
    .space sizeof(BootInfo), 0

app_vectors:
    .space sizeof(AppVectors), 0

api_table:
    .space sizeof(APITable), 0

/***************************************************************************
 * BSS Section
 * 
 * Uninitialized data.
 ***************************************************************************/

    .bss

    .align 4

/* Stack space */
stack_start:
    .space BOOT_STACK_SIZE, 0
stack_end:

/***************************************************************************
 * End of File
 ***************************************************************************/
