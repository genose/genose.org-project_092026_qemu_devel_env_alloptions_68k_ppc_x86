/***************************************************************************
 * Custom Bootloader - QEMU Detection
 * 
 * Detects whether the code is running in QEMU emulator or on real Mac hardware.
 * Multiple detection methods for reliability.
 * 
 * Architecture: 68k and PPC
 * 
 * Detection Methods:
 *   1. SCSI Controller Signature (QEMU specific addresses)
 *   2. VIA Chip Registers (QEMU vs real Mac differences)
 *   3. Memory-Mapped Debug Port (QEMU specific)
 *   4. ROM Signature Check (QEMU ROM vs Apple ROM)
 *   5. CPU PVR Check (for PPC - QEMU reports specific values)
 *   6. Memory Write Test (QEMU allows writes to normally protected areas)
 * 
 * Returns: 1 in D0 if QEMU, 0 if real hardware
 ***************************************************************************/

#include "config.h"

    .global detect_qemu_environment
    .global detect_qemu_environment_ppc
    .global qemu_detected
    .global qemu_detect_method

/***************************************************************************
 * QEMU Detection Configuration
 ***************************************************************************/

/*** SCSI Controller (Quadra 800) ***/
#define SCSI_BASE_Q800       0x50F10000
#define SCSI_VENDOR_OFFSET    0x10
#define QEMU_SCSI_SIGNATURE   0x51454D55  /* "QEMU" */

/*** VIA Chip Addresses ***/
#define VIA1_BASE            0x50F00000
#define VIA2_BASE            0x50F04000
#define VIA_VERSION_REGISTER  0x03

/*** QEMU Debug Port ***/
#define QEMU_DEBUG_PORT       0xE0000000
#define QEMU_DEBUG_MAGIC      0x51454D55  /* "QEMU" */

/*** ROM Addresses ***/
#define ROM_BASE              0x40800000
#define ROM_SIGNATURE_OFFSET  0x0000
#define REAL_ROM_SIGNATURE    0x4150504C  /* "APPL" (Apple) */

/*** PPC Specific ***/
#define PPC_DECREMENTER        0x00000090  /* DEC register address */

/*** Memory Test Address ***/
#define PROTECTED_MEMORY_TEST 0x00000000  /* Null pointer write test */

/***************************************************************************
 * Global Variables
 ***************************************************************************/

    .data
    .align 4

qemu_detected:
    .long 0x00000000   /* 0 = not detected, 1 = QEMU, 2 = real Mac */

qemu_detect_method:
    .long 0x00000000   /* Method used for detection (0-6) */

qemu_cached_result:
    .long 0xFFFFFFFF   /* Cached result (-1 = not cached) */

    .text

/***************************************************************************
 * Detect QEMU Environment (68k)
 * 
 * Main detection function for 68k architecture.
 * Tries multiple methods until one succeeds.
 * 
 * Returns: 1 in D0 if QEMU, 0 if real Mac
 * Clobbers: D0-D2, A0-A1
 ***************************************************************************/

detect_qemu_environment:
    /* Check cache first */
    move.l  qemu_cached_result, %d0
    cmp.l   #0xFFFFFFFF, %d0
    bne     .return_cached
    
    /* Try Method 1: SCSI Controller Signature */
    jsr     detect_scsi_qemu
    tst.l   %d0
    bne     .detected_qemu
    
    /* Try Method 2: VIA Chip Detection */
    jsr     detect_via_qemu
    tst.l   %d0
    bne     .detected_qemu
    
    /* Try Method 3: Debug Port Check */
    jsr     detect_debug_port
    tst.l   %d0
    bne     .detected_qemu
    
    /* Try Method 4: ROM Signature Check */
    jsr     detect_rom_signature
    tst.l   %d0
    bne     .detected_qemu
    
    /* Try Method 5: Memory Write Test */
    jsr     detect_memory_write_test
    tst.l   %d0
    bne     .detected_qemu
    
    /* If all methods fail, assume real Mac */
    moveq   #0, %d0
    move.l  #5, qemu_detect_method    /* Method: default (real) */
    bra     .store_and_return
    
.detected_qemu:
    moveq   #1, %d0
    move.l  qemu_detect_method, %d1
    
.store_and_return:
    move.l  %d0, qemu_cached_result
    move.l  %d0, qemu_detected
    
.return_cached:
    rts

/***************************************************************************
 * Method 1: SCSI Controller Signature
 * 
 * Checks for QEMU signature at SCSI controller address.
 * QEMU emulates SCSI at known addresses with identifiable signatures.
 * 
 * Returns: 1 in D0 if QEMU detected, 0 otherwise
 ***************************************************************************/

detect_scsi_qemu:
    movem.l %d1/%a0, -(sp)
    
    /* Read from SCSI vendor ID address */
    move.l  #SCSI_BASE_Q800, %a0
    add.l   #SCSI_VENDOR_OFFSET, %a0
    move.l  (%a0), %d1
    
    /* Check for "QEMU" signature */
    cmp.l   #QEMU_SCSI_SIGNATURE, %d1
    beq     .scsi_qemu_found
    
    /* Try alternative SCSI address */
    move.l  #0x50F10010, %a0
    move.l  (%a0), %d1
    cmp.l   #QEMU_SCSI_SIGNATURE, %d1
    bne     .scsi_not_qemu
    
.scsi_qemu_found:
    move.l  #1, %d0
    move.l  #1, qemu_detect_method
    bra     .scsi_done
    
.scsi_not_qemu:
    moveq   #0, %d0
    
.scsi_done:
    movem.l (%sp)+, %d1/%a0
    rts

/***************************************************************************
 * Method 2: VIA Chip Detection
 * 
 * QEMU's VIA emulation has subtle differences from real hardware.
 * We can detect these by reading version registers.
 * 
 * Returns: 1 in D0 if QEMU detected, 0 otherwise
 ***************************************************************************/

detect_via_qemu:
    movem.l %d1/%a0, -(sp)
    
    /* Read VIA1 version register */
    move.l  #VIA1_BASE, %a0
    add.l   #VIA_VERSION_REGISTER, %a0
    move.b  (%a0), %d1
    
    /* QEMU VIA reports 0x00, real hardware has different values */
    cmp.b   #0x00, %d1
    beq     .via_qemu_found
    
    /* Try VIA2 */
    move.l  #VIA2_BASE, %a0
    add.l   #VIA_VERSION_REGISTER, %a0
    move.b  (%a0), %d1
    cmp.b   #0x00, %d1
    bne     .via_not_qemu
    
.via_qemu_found:
    move.l  #1, %d0
    move.l  #2, qemu_detect_method
    bra     .via_done
    
.via_not_qemu:
    moveq   #0, %d0
    
.via_done:
    movem.l (%sp)+, %d1/%a0
    rts

/***************************************************************************
 * Method 3: Debug Port Check
 * 
 * QEMU provides a debug port at 0xE0000000 that responds to reads.
 * Real Mac hardware will not have this port.
 * 
 * Returns: 1 in D0 if QEMU detected, 0 otherwise
 ***************************************************************************/

detect_debug_port:
    movem.l %d1/%a0, -(sp)
    
    /* Try to read from debug port */
    move.l  #QEMU_DEBUG_PORT, %a0
    move.l  (%a0), %d1
    
    /* Check for magic value */
    cmp.l   #QEMU_DEBUG_MAGIC, %d1
    beq     .debug_qemu_found
    
    /* Also check if write succeeds without bus error */
    move.l  #0xDEADBEEF, %d1
    move.l  %d1, (%a0)
    move.l  (%a0), %d1
    cmp.l   #0xDEADBEEF, %d1
    beq     .debug_qemu_found
    
    moveq   #0, %d0
    bra     .debug_done
    
.debug_qemu_found:
    move.l  #1, %d0
    move.l  #3, qemu_detect_method
    
.debug_done:
    movem.l (%sp)+, %d1/%a0
    rts

/***************************************************************************
 * Method 4: ROM Signature Check
 * 
 * Apple ROMs have specific signatures at known offsets.
 * QEMU may use different ROM images or no ROM at all.
 * 
 * Returns: 1 in D0 if QEMU detected, 0 otherwise
 * Note: This might not be reliable if QEMU uses real ROM images
 ***************************************************************************/

detect_rom_signature:
    movem.l %d1/%a0, -(sp)
    
    /* Read from ROM base */
    move.l  #ROM_BASE, %a0
    move.l  (%a0), %d1
    
    /* Check for Apple signature "APPL" */
    cmp.l   #REAL_ROM_SIGNATURE, %d1
    bne     .rom_qemu_found
    
    /* Could still be real Mac, but also could be QEMU with real ROM */
    /* Try a secondary check */
    move.l  #0x0004, %a0
    add.l   #ROM_BASE, %a0
    move.l  (%a0), %d1
    
    /* Real Apple ROM has specific patterns */
    /* This is a simple heuristic */
    cmp.l   #0x00000000, %d1
    beq     .rom_qemu_found
    
    /* Assume real Mac */
    moveq   #0, %d0
    bra     .rom_done
    
.rom_qemu_found:
    move.l  #1, %d0
    move.l  #4, qemu_detect_method
    
.rom_done:
    movem.l (%sp)+, %d1/%a0
    rts

/***************************************************************************
 * Method 5: Memory Write Test
 * 
 * QEMU allows writes to certain protected memory areas that real
 * hardware would reject with a bus error. We test this.
 * 
 * Returns: 1 in D0 if QEMU detected (write succeeds), 0 otherwise
 * Note: This is risky and may crash on real hardware!
 *       Use only as last resort.
 ***************************************************************************/

detect_memory_write_test:
    movem.l %d1/%a0, -(sp)
    
    /* Save current bus error handler */
    move.l  0x00000008, %d1
    move.l  %d1, saved_bus_error_handler
    
    /* Install our test bus error handler */
    lea     test_bus_error_handler(%pc), %a0
    move.l  %a0, 0x00000008
    
    /* Set up a flag */
    clr.l   bus_error_occurred
    
    /* Try to write to null pointer */
    move.l  #0xDEADBEEF, %d1
    move.l  %d1, (0x00000000)
    
    /* Check if bus error occurred */
    move.l  bus_error_occurred, %d0
    tst.l   %d0
    bne     .write_test_real
    
    /* No bus error = QEMU */
    move.l  #1, %d0
    move.l  #5, qemu_detect_method
    bra     .write_test_done
    
.write_test_real:
    /* Bus error occurred = real hardware */
    moveq   #0, %d0
    
.write_test_done:
    /* Restore bus error handler */
    move.l  saved_bus_error_handler, %d1
    move.l  %d1, 0x00000008
    
    movem.l (%sp)+, %d1/%a0
    rts

    .data
    .align 4

saved_bus_error_handler:
    .long 0x00000000

bus_error_occurred:
    .long 0x00000000

    .text

test_bus_error_handler:
    move.l  #1, bus_error_occurred
    addq.l  #4, %sp           /* Clean up pushed PC */
    rte

/***************************************************************************
 * PPC Detection (for completeness)
 * 
 * PPC-specific QEMU detection using PVR and other registers.
 * 
 * Returns: 1 in R3 if QEMU, 0 otherwise
 ***************************************************************************/

    .p2align 2

detect_qemu_environment_ppc:
    /* PPC version - uses different methods */
    
    /* Method 1: Check DEC (Decrementer) behavior */
    mfspr   3, 22              /* Read DEC (SPR 22) */
    cmpwi   0, 3
    bne     .ppc_not_qemu
    
    /* DEC is 0 in QEMU initially */
    li      3, 1
    li      4, 1              /* Method 1 */
    stw     4, qemu_detect_method
    bra     .ppc_done
    
.ppc_not_qemu:
    /* Method 2: Check for QEMU in device tree */
    /* This would require Open Firmware access */
    
    /* Method 3: Memory test */
    li      3, 0xDEADBEEF
    stw     3, 0x0000(0)       /* Try write to null */
    lwz     3, 0x0000(0)
    cmpwi   0, 3
    beq     .ppc_qemu_detected
    
    li      3, 0
    bra     .ppc_done
    
.ppc_qemu_detected:
    li      3, 1
    li      4, 3
    stw     4, qemu_detect_method
    
.ppc_done:
    blr

/***************************************************************************
 * Force QEMU Detection Refresh
 * 
 * Clears the cached result and forces a new detection.
 * Useful if environment changes.
 ***************************************************************************/

    .global refresh_qemu_detection

refresh_qemu_detection:
    move.l  #0xFFFFFFFF, qemu_cached_result
    move.l  #0, qemu_detected
    move.l  #0, qemu_detect_method
    rts

/***************************************************************************
 * Invalidate QEMU Cache
 * 
 * Marks the detection cache as invalid without forcing immediate refresh.
 ***************************************************************************/

    .global invalidate_qemu_cache

invalidate_qemu_cache:
    move.l  #0xFFFFFFFF, qemu_cached_result
    rts
