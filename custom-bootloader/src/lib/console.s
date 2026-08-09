/***************************************************************************
 * Custom Bootloader - Console I/O Implementation
 * 
 * Low-level console output functions for 68k and PowerPC.
 * 
 * For QEMU emulation, we use the serial port at standard addresses.
 * For 68k Mac: VIA chip at 0x50F00000 series (varies by model)
 * For PPC Mac: Open Firmware / CHRP serial
 * 
 * In QEMU, serial output can be directed to stdio with -serial stdio
 * and we can write directly to the emulated serial port.
 ***************************************************************************/

#include "config.h"

    .global console_putc
    .global console_putc_ppc
    .global console_init
    .global console_init_ppc
    .global serial_putc
    .global serial_putc_ppc

/***************************************************************************
 * Serial Port Addresses
 * 
 * These are typical addresses for Mac serial ports.
 * QEMU emulates these and redirects to the host.
 ***************************************************************************/

/*** 68k Mac Serial Port (VIA chip) ***/
#define VIA_BASE            0x50F00000
#define VIA_SHIFT_REG       (VIA_BASE + 0x00)
#define VIA_STATUS_REG      (VIA_BASE + 0x01)

/*** Alternative: Modem Port ***/
#define MODEM_VIA_BASE      0x50F04000

/*** PPC Serial (CHRP / Open Firmware) ***/
#define PPC_SERIAL_BASE      0x80000000
#define PPC_SERIAL_THR       (PPC_SERIAL_BASE + 0x00)  /* Transmit Holding Register */
#define PPC_SERIAL_LSR       (PPC_SERIAL_BASE + 0x05)  /* Line Status Register */

/*** QEMU Debug Port (if using -debugcon) ***/
#define DEBUG_PORT          0xE0000000

/***************************************************************************
 * 68k Console Initialization
 * 
 * Initializes the serial console for 68k architecture.
 * For now, just sets up VIA registers.
 ***************************************************************************/

console_init:
    /* For 68k Mac, initialize VIA serial port */
    /* VIA is memory-mapped at 0x50F00000 */
    
    /* Set baud rate divisor (example: 115200 baud) */
    /* For now, assume VIA is already initialized by firmware */
    
    /* Clear any pending interrupts */
    move.b #0x00, (VIA_STATUS_REG)
    
    rts

/***************************************************************************
 * 68k Serial Character Output
 * 
 * Outputs a single character to the serial port.
 * Uses memory-mapped VIA chip registers.
 * 
 * Input: D0 = character to output (byte in lower 8 bits)
 * Clobbers: D0, A0
 ***************************************************************************/

serial_putc:
    /* Wait for transmitter to be ready */
serial_putc_wait:
    /* Read status register, check TBE (Transmit Buffer Empty) bit */
    /* For now, we'll use a simple delay since we don't have the exact VIA layout */
    
    /* In QEMU with -serial stdio, we can write directly */
    /* But for simplicity, we'll use a memory-mapped approach */
    
    /* Use debug port if available (QEMU) */
    /* This is a placeholder - actual implementation depends on target hardware */
    
    /* For debugging in QEMU, we can use the debug port at 0xE0000000 */
    move.l %d0, -(sp)
    andi.l #0xFF, %d0      /* Mask to 8 bits */
    
    /* Check if we're in QEMU (simple heuristic: check for debug port) */
    /* For now, just write to memory-mapped location */
    
    /* Simple approach: use the debug console */
    /* QEMU redirects this to stderr if -debugcon is used */
    
    /* Alternative: use a simple memory location that QEMU monitors */
    /* This is a placeholder implementation */
    
    /* For true serial, we need to implement VIA access */
    /* For now, we'll use a simpler method */
    
    /* Store character at a known location */
    /* QEMU can be configured to watch this */
    move.l #0x00800000, %a0  /* Simple debug output address */
    move.b %d0, (%a0)
    
    /* Add a small delay */
    move.l #100, %d0
serial_putc_delay:
    dbra %d0, serial_putc_delay
    
    move.l (%sp)+, %d0
    rts

/***************************************************************************
 * 68k Console Character Output
 * 
 * Main console output function for 68k.
 * Calls the appropriate low-level output function.
 * 
 * Input: D0 = character (byte in lower 8 bits)
 * Clobbers: D0, A0
 ***************************************************************************/

console_putc:
    /* For now, use simple serial output */
    bra serial_putc

/***************************************************************************
 * PPC Console Initialization
 * 
 * Initializes the serial console for PowerPC architecture.
 ***************************************************************************/

console_init_ppc:
    /* For PPC, initialize serial port */
    /* CHRP uses memory-mapped serial at 0x80000000 */
    
    /* Set baud rate (example values) */
    /* For now, assume already initialized */
    
    blr

/***************************************************************************
 * PPC Serial Character Output
 * 
 * Outputs a single character to the serial port on PPC.
 * 
 * Input: R3 = character to output
 * Clobbers: R3, R4, R5
 ***************************************************************************/

serial_putc_ppc:
    /* Wait for transmitter to be ready */
    lis 5, PPC_SERIAL_LSR >> 16
    ori 5, 5, PPC_SERIAL_LSR & 0xFFFF
    
serial_putc_ppc_wait:
    lbz 4, 0(5)           /* Read LSR */
    andi. 4, 4, 0x20     /* Check THRE (Transmit Holding Register Empty) */
    beq serial_putc_ppc_wait
    
    /* Write character to THR */
    lis 5, PPC_SERIAL_THR >> 16
    ori 5, 5, PPC_SERIAL_THR & 0xFFFF
    stb 3, 0(5)
    
    blr

/***************************************************************************
 * PPC Console Character Output
 * 
 * Main console output function for PPC.
 * 
 * Input: R3 = character
 * Clobbers: R3
 ***************************************************************************/

console_putc_ppc:
    /* Use serial output */
    mr 31, 3             /* Save character in R31 (non-volatile) */
    bl serial_putc_ppc
    mr 3, 31            /* Restore and return */
    blr

/***************************************************************************
 * Console Write String (68k)
 * 
 * Writes a null-terminated string to the console.
 * 
 * Input: A0 = pointer to string
 * Clobbers: A0, D0
 ***************************************************************************/

console_puts:
    movem.l %d0/%a0, -(sp)
    move.l 8(%sp), %a0
    
console_puts_loop:
    move.b (%a0)+, %d0
    beq console_puts_done
    move.l %d0, -(sp)
    jsr console_putc
    addq.l #4, %sp
    bra console_puts_loop
    
console_puts_done:
    movem.l (%sp)+, %d0/%a0
    rts

/***************************************************************************
 * Console Write String (PPC)
 * 
 * Writes a null-terminated string to the console.
 * 
 * Input: R3 = pointer to string
 * Clobbers: R3, R4, R5
 ***************************************************************************/

console_puts_ppc:
    mflr 0
    stwu 1, -16(1)
    stw 31, 12(1)
    mr 31, 3
    
console_puts_ppc_loop:
    lbz 3, 0(31)
    cmpwi 3, 0
    beq console_puts_ppc_done
    mr 4, 3
    bl console_putc_ppc
    addi 31, 31, 1
    bra console_puts_ppc_loop
    
console_puts_ppc_done:
    lwz 31, 12(1)
    addi 1, 1, 16
    mtlr 0
    blr
