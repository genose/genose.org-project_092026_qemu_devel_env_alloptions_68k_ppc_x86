/***************************************************************************
 * Custom Bootloader - Standardized Messages
 * 
 * This file contains all standardized message strings used throughout the
 * bootloader. These messages are displayed during the boot process to indicate
 * progress and status.
 * 
 * Standard Messages:
 * - "Loading ..." - Initial boot message
 * - "(CPU_NAME) running ..." - After CPU detection and initialization
 * - "Boot OS ..." - Before jumping to the operating system
 * - "Failure (code 0xXX)" - On unrecoverable error
 ***************************************************************************/

#include "config.h"

    .global display_string
    .global display_string_ppc
    .global display_cpu_name
    .global display_cpu_name_ppc

    .text

/***************************************************************************
 * Display String (68k)
 * 
 * Displays a null-terminated string to the console.
 * Uses the console_putc function for each character.
 * 
 * Input: A0 = pointer to string
 * Clobbers: A0, D0
 ***************************************************************************/

display_string:
    movem.l %d0/%a0, -(sp)
    move.l 8(%sp), %a0       /* Get string pointer from stack */
    
display_string_loop:
    move.b (%a0)+, %d0       /* Get next character */
    beq display_string_done  /* If null, we're done */
    
    /* Output character */
    move.l %d0, -(sp)
    jsr console_putc
    addq.l #4, %sp
    
    bra display_string_loop
    
display_string_done:
    movem.l (%sp)+, %d0/%a0
    rts

/***************************************************************************
 * Display String (PPC)
 * 
 * PowerPC version of display_string.
 * 
 * Input: R3 = pointer to string
 * Clobbers: R3, R4
 ***************************************************************************/

display_string_ppc:
    mflr 0                  /* Save LR */
    stwu 1, -16(1)         /* Allocate stack space */
    stw 31, 12(1)          /* Save R31 */
    mr 31, 3               /* Copy string pointer to R31 */
    
display_string_ppc_loop:
    lbz 3, 0(31)           /* Load byte */
    cmpwi 3, 0             /* Check for null */
    beq display_string_ppc_done
    
    /* Output character */
    mr 4, 3
    bl console_putc_ppc
    
    addi 31, 31, 1         /* Increment string pointer */
    bra display_string_ppc_loop
    
display_string_ppc_done:
    lwz 31, 12(1)          /* Restore R31 */
    addi 1, 1, 16         /* Deallocate stack space */
    mtlr 0                  /* Restore LR */
    blr

/***************************************************************************
 * Display CPU Name (68k)
 * 
 * Displays the CPU-specific "running" message.
 * 
 * Input: D0 = CPU ID
 * Clobbers: D0, A0
 ***************************************************************************/

display_cpu_name:
    cmp.l #CPU_ID_68000, %d0
    beq display_68000
    
    cmp.l #CPU_ID_68010, %d0
    beq display_68010
    
    cmp.l #CPU_ID_68020, %d0
    beq display_68020
    
    cmp.l #CPU_ID_68030, %d0
    beq display_68030
    
    cmp.l #CPU_ID_68040, %d0
    beq display_68040
    
    cmp.l #CPU_ID_68060, %d0
    beq display_68060
    
    cmp.l #CPU_ID_68LC040, %d0
    beq display_68lc040
    
    cmp.l #CPU_ID_68EC040, %d0
    beq display_68ec040
    
    cmp.l #CPU_ID_68070, %d0
    beq display_68070
    
    cmp.l #CPU_ID_APOLLOCORE, %d0
    beq display_apollocore
    
    /* Unknown CPU */
    pea msg_unknown_running(%pc)
    bra display_string_common

display_68000:
    pea msg_68000_running(%pc)
    bra display_string_common

display_68010:
    pea msg_68010_running(%pc)
    bra display_string_common

display_68020:
    pea msg_68020_running(%pc)
    bra display_string_common

display_68030:
    pea msg_68030_running(%pc)
    bra display_string_common

display_68040:
    pea msg_68040_running(%pc)
    bra display_string_common

display_68060:
    pea msg_68060_running(%pc)
    bra display_string_common

display_68lc040:
    pea msg_68lc040_running(%pc)
    bra display_string_common

display_68ec040:
    pea msg_68ec040_running(%pc)
    bra display_string_common

display_68070:
    pea msg_68070_running(%pc)
    bra display_string_common

display_apollocore:
    pea msg_apollocore_running(%pc)
    bra display_string_common
    
display_string_common:
    jsr display_string
    addq.l #4, %sp
    rts

/***************************************************************************
 * Display CPU Name (PPC)
 * 
 * PowerPC version of display_cpu_name.
 * 
 * Input: R3 = CPU ID
 * Clobbers: R3, R4
 ***************************************************************************/

display_cpu_name_ppc:
    mflr 0                  /* Save LR */
    stwu 1, -16(1)         /* Allocate stack space */
    stw 31, 12(1)          /* Save R31 */
    
    cmpwi 3, CPU_ID_PPC601
    beq display_ppc_601
    
    cmpwi 3, CPU_ID_PPC603
    beq display_ppc_603
    
    cmpwi 3, CPU_ID_PPC604
    beq display_ppc_604
    
    cmpwi 3, CPU_ID_PPC750
    beq display_ppc_750
    
    cmpwi 3, CPU_ID_PPC7410
    beq display_ppc_7410
    
    cmpwi 3, CPU_ID_PPC7455
    beq display_ppc_7455
    
    cmpwi 3, CPU_ID_PPC970
    beq display_ppc_970
    
    /* Unknown CPU */
    lis 3, msg_unknown_running@h
    ori 3, 3, msg_unknown_running@l
    bra display_string_ppc_common

display_ppc_601:
    lis 3, msg_ppc601_running@h
    ori 3, 3, msg_ppc601_running@l
    bra display_string_ppc_common

display_ppc_603:
    lis 3, msg_ppc603_running@h
    ori 3, 3, msg_ppc603_running@l
    bra display_string_ppc_common

display_ppc_604:
    lis 3, msg_ppc604_running@h
    ori 3, 3, msg_ppc604_running@l
    bra display_string_ppc_common

display_ppc_750:
    lis 3, msg_ppc750_running@h
    ori 3, 3, msg_ppc750_running@l
    bra display_string_ppc_common

display_ppc_7410:
    lis 3, msg_ppc7410_running@h
    ori 3, 3, msg_ppc7410_running@l
    bra display_string_ppc_common

display_ppc_7455:
    lis 3, msg_ppc7455_running@h
    ori 3, 3, msg_ppc7455_running@l
    bra display_string_ppc_common

display_ppc_970:
    lis 3, msg_ppc970_running@h
    ori 3, 3, msg_ppc970_running@l
    
display_string_ppc_common:
    bl display_string_ppc
    
    lwz 31, 12(1)          /* Restore R31 */
    addi 1, 1, 16         /* Deallocate stack space */
    mtlr 0                  /* Restore LR */
    blr

/***************************************************************************
 * Display Failure Message
 * 
 * Displays the failure message with error code.
 * 
 * Input: D0 = error code
 * Clobbers: D0, A0
 ***************************************************************************/

display_failure:
    movem.l %d0/%a0, -(sp)
    
    /* Display prefix */
    pea msg_failure_prefix(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* Display error code */
    move.l 8(%sp), %d0      /* Get error code from stack */
    move.l %d0, -(sp)
    jsr display_hex_byte
    addq.l #4, %sp
    
    /* Display suffix */
    pea msg_failure_suffix(%pc)
    jsr display_string
    addq.l #4, %sp
    
    movem.l (%sp)+, %d0/%a0
    rts

/***************************************************************************
 * Display Hex Byte
 * 
 * Displays a byte value in hexadecimal format.
 * 
 * Input: D0 = byte value
 * Clobbers: D0, D1, A0
 ***************************************************************************/

display_hex_byte:
    movem.l %d0/%d1/%a0, -(sp)
    move.l 12(%sp), %d0     /* Get value from stack */
    
    /* Extract high nibble */
    move.l %d0, %d1
    lsr.l #4, %d1
    andi.l #0xF, %d1
    
    /* Convert to ASCII */
    cmp.b #9, %d1
    ble display_hex_digit1
    addi.b #7, %d1           /* A-F */
    
display_hex_digit1:
    addi.b #'0', %d1
    move.b %d1, -(sp)
    jsr console_putc
    addq.l #4, %sp
    
    /* Extract low nibble */
    andi.l #0xF, %d0
    
    /* Convert to ASCII */
    cmp.b #9, %d0
    ble display_hex_digit2
    addi.b #7, %d0           /* A-F */
    
display_hex_digit2:
    addi.b #'0', %d0
    move.b %d0, -(sp)
    jsr console_putc
    addq.l #4, %sp
    
    movem.l (%sp)+, %d0/%d1/%a0
    rts

/***************************************************************************
 * Console Output Functions
 * 
 * Low-level character output functions for both architectures.
 ***************************************************************************/

/* 68k console output */
console_putc:
    /* For now, just return (real implementation would output to serial/console) */
    rts

/* PPC console output */
console_putc_ppc:
    /* For now, just return */
    blr

/***************************************************************************
 * Data Section
 * 
 * All message strings are defined here.
 ***************************************************************************/

    .data
    .align 4

/*** Standard Messages ***/
msg_loading:
    .asciz "Loading ...\r\n"

msg_boot_os:
    .asciz "Boot OS ...\r\n"

msg_failure_prefix:
    .asciz "\r\nFailure (code 0x"

msg_failure_suffix:
    .asciz ")\r\n"

/*** 68k CPU Messages ***/
msg_68000_running:
    .asciz "Motorola 68000 running ...\r\n"

msg_68010_running:
    .asciz "Motorola 68010 running ...\r\n"

msg_68020_running:
    .asciz "Motorola 68020 running ...\r\n"

msg_68030_running:
    .asciz "Motorola 68030 running ...\r\n"

msg_68040_running:
    .asciz "Motorola 68040 running ...\r\n"

msg_68060_running:
    .asciz "Motorola 68060 running ...\r\n"

/*** PPC CPU Messages ***/
msg_ppc601_running:
    .asciz "PowerPC 601 running ...\r\n"

msg_ppc603_running:
    .asciz "PowerPC 603 running ...\r\n"

msg_ppc604_running:
    .asciz "PowerPC 604 running ...\r\n"

msg_ppc750_running:
    .asciz "PowerPC 750 (G3) running ...\r\n"

msg_ppc7410_running:
    .asciz "PowerPC 7410 (G4) running ...\r\n"

msg_ppc7455_running:
    .asciz "PowerPC 7455 (G4 Enhanced) running ...\r\n"

msg_ppc970_running:
    .asciz "PowerPC 970 (G5) running ...\r\n"

/*** Unknown/Generic Messages ***/
msg_unknown_running:
    .asciz "Unknown CPU running ...\r\n"

msg_unknown_cpu:
    .asciz "Unknown CPU"

/*** Boot Progress Messages ***/
msg_detecting_cpu:
    .asciz "Detecting CPU ...\r\n"

msg_initializing_memory:
    .asciz "Initializing memory ...\r\n"

msg_initializing_api:
    .asciz "Initializing API ...\r\n"

msg_selecting_boot_device:
    .asciz "Selecting boot device ...\r\n"

msg_loading_os:
    .asciz "Loading operating system ...\r\n"

msg_jumping_to_os:
    .asciz "Jumping to OS ...\r\n"

/*** Error Messages ***/
msg_error_generic:
    .asciz "\r\nError!\r\n"

msg_error_memory:
    .asciz "\r\nMemory initialization failed!\r\n"

msg_error_boot_device:
    .asciz "\r\nNo bootable device found!\r\n"

msg_error_load:
    .asciz "\r\nFailed to load operating system!\r\n"

/*** Debug Messages ***/
msg_debug_registers:
    .asciz "\r\nRegisters:\r\n"

msg_debug_backtrace:
    .asciz "\r\nBacktrace:\r\n"

msg_debug_hexdump:
    .asciz "\r\nHex Dump:\r\n"

/***************************************************************************
 * End of File
 ***************************************************************************/
