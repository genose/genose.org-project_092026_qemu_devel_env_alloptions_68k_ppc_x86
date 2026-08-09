/***************************************************************************
 * Custom Bootloader - TRAP #15 Handler
 * 
 * API Dispatcher for TRAP #15 (vector 0x000000BC / 47)
 * This provides a software interrupt interface for applications to call
 * bootloader functions without direct linking.
 * 
 * Architecture: 68k (Motorola 68000 family)
 * 
 * API Functions (via D0 register):
 *   0: TRIGGER_GDB       - Force GDB break via UART
 *   1: CHECK_ENV         - Detect QEMU vs real Mac (returns 1 or 0 in D0)
 *   2: GET_BOOTLOADER_VERSION - Get bootloader version
 *   3: SET_DEBUG_LEVEL   - Set debug verbosity level
 *   4: DUMP_MEMORY       - Dump memory region (A0=start, D1=size)
 *   5: LOG_MESSAGE       - Log message to debug console (A0=ptr to string)
 *   6: GET_CPU_TYPE      - Get detected CPU type
 *   7: GET_API_MAGIC     - Verify bootloader API presence (returns 0xDEADBEEF)
 *   8: INSTALL_NMI_HANDLER - Install NMI handler (if not already installed)
 *   9: GET_BACKTRACE     - Generate and store backtrace (A0=buffer, D1=max_depth)
 *  10: CHECK_BOOTLOADER  - Check if custom bootloader is present (returns 1/0)
 * 
 * Return values:
 *   - D0: Function result (varies by function)
 *   - D1: Error code (0 = success, non-zero = error)
 *   - A0: Pointer result (if applicable)
 * 
 * Usage from application:
 *   move.l #function_id, %d0
 *   trap #15
 *   ; Result in %d0
 ***************************************************************************/

#include "config.h"
#include "bootloader_api.h"

    .global install_trap15_handler
    .global api_trap_handler
    .global trap15_installed

/***************************************************************************
 * TRAP #15 Configuration
 ***************************************************************************/

#define TRAP15_VECTOR     0x000000BC  /* Vector 47 */
#define MAX_API_FUNCTIONS 16

/***************************************************************************
 * Installation Flag
 ***************************************************************************/

    .data
    .align 4

trap15_installed:
    .long 0x00000000   /* 0 = not installed, 1 = installed */

    .text

/***************************************************************************
 * Install TRAP #15 Handler
 * 
 * Installs the API dispatcher at vector 47 (0x000000BC).
 * Must be called during bootloader initialization.
 * 
 * Clobbers: A0, D0
 ***************************************************************************/

install_trap15_handler:
    movem.l %d0-%d1/%a0, -(sp)
    
    /* Check if already installed */
    move.l  TRAP15_VECTOR, %d0
    cmp.l   #api_trap_handler, %d0
    beq     .already_installed
    
    /* Install TRAP #15 handler */
    lea     api_trap_handler(%pc), %a0
    move.l  %a0, TRAP15_VECTOR
    
    /* Mark as installed */
    move.l  #1, trap15_installed
    
    /* Also store the original handler (if any) for potential chain */
    move.l  %d0, original_trap15_handler
    
.already_installed:
    movem.l (%sp)+, %d0-%d1/%a0
    rts

    .data
    .align 4
original_trap15_handler:
    .long 0x00000000
    .text

/***************************************************************************
 * Uninstall TRAP #15 Handler
 * 
 * Removes the API dispatcher and restores original handler.
 * 
 * Clobbers: A0, D0
 ***************************************************************************/

    .global uninstall_trap15_handler

uninstall_trap15_handler:
    movem.l %d0/%a0, -(sp)
    
    /* Restore original handler */
    move.l  original_trap15_handler, %d0
    beq     .no_original
    
    move.l  %d0, TRAP15_VECTOR
    clr.l   trap15_installed
    
.no_original:
    movem.l (%sp)+, %d0/%a0
    rts

/***************************************************************************
 * API TRAP Handler
 * 
 * Main dispatcher for TRAP #15 calls.
 * Reads function ID from D0 and dispatches accordingly.
 * 
 * Input:
 *   D0 = Function ID (0-15)
 *   A0-D1 = Function parameters (varies by function)
 * 
 * Output:
 *   D0 = Function result
 *   D1 = Error code (0 = success)
 *   A0 = Pointer result (if applicable)
 * 
 * Stack on entry:
 *   - SSW (Special Status Word)
 *   - PC (Program Counter)
 *   - All registers as saved by caller
 * 
 * Note: Uses a temporary stack to avoid corrupting caller's stack
 ***************************************************************************/

api_trap_handler:
    /* Phase 1: Save caller's context */
    movem.l %d0-%d7/%a0-%a6, -(sp)  /* Save all registers except D0 */
    
    /* Save D0 (function ID) separately */
    move.l  %d0, -(sp)
    
    /* Phase 2: Switch to temporary stack */
    /* Allocate space on stack for our work */
    sub.l   #32, %sp
    
    /* Phase 3: Dispatch based on function ID */
    move.l  28(%sp), %d0          /* Get function ID from saved D0 */
    
    cmp.l   #BOOTLOADER_TRIGGER_GDB, %d0
    beq     .api_trigger_gdb
    
    cmp.l   #BOOTLOADER_CHECK_ENV, %d0
    beq     .api_check_env
    
    cmp.l   #BOOTLOADER_GET_VERSION, %d0
    beq     .api_get_version
    
    cmp.l   #BOOTLOADER_SET_DEBUG, %d0
    beq     .api_set_debug
    
    cmp.l   #BOOTLOADER_DUMP_MEMORY, %d0
    beq     .api_dump_memory
    
    cmp.l   #BOOTLOADER_LOG_MESSAGE, %d0
    beq     .api_log_message
    
    cmp.l   #BOOTLOADER_GET_CPU_TYPE, %d0
    beq     .api_get_cpu_type
    
    cmp.l   #BOOTLOADER_GET_API_MAGIC, %d0
    beq     .api_get_api_magic
    
    cmp.l   #BOOTLOADER_INSTALL_NMI, %d0
    beq     .api_install_nmi
    
    cmp.l   #BOOTLOADER_GET_BACKTRACE, %d0
    beq     .api_get_backtrace
    
    cmp.l   #BOOTLOADER_CHECK_PRESENCE, %d0
    beq     .api_check_presence
    
    /* Unknown function */
    move.l  #API_ERROR_INVALID_FUNCTION, %d1
    bra     .api_exit
    
    /* ============================================ */
    /* Function Implementations */
    /* ============================================ */
    
    /* --- Function 0: TRIGGER_GDB --- */
.api_trigger_gdb:
    jsr     detect_qemu_environment
    tst.l   %d0
    beq     .trigger_fallback
    
    /* QEMU: Send BREAK via UART */
    move.b  #0x03, (0x50F0C000)    /* BREAK character */
    moveq   #0, %d0               /* Return success */
    moveq   #0, %d1               /* No error */
    bra     .api_exit
    
.trigger_fallback:
    /* Real Mac: Trigger illegal instruction */
    illegal
    
    /* --- Function 1: CHECK_ENV --- */
.api_check_env:
    jsr     detect_qemu_environment
    move.l  %d0, %d0             /* Return result in D0 */
    moveq   #0, %d1               /* No error */
    bra     .api_exit
    
    /* --- Function 2: GET_VERSION --- */
.api_get_version:
    move.l  #BOOTLOADER_VERSION, %d0
    moveq   #0, %d1
    bra     .api_exit
    
    /* --- Function 3: SET_DEBUG --- */
.api_set_debug:
    move.l  28(%sp), %d0         /* Get D0 from stack */
    move.l  %d0, debugger_verbosity
    moveq   #0, %d0
    moveq   #0, %d1
    bra     .api_exit
    
    /* --- Function 4: DUMP_MEMORY --- */
.api_dump_memory:
    /* A0 = start address, D1 = size (from caller's registers) */
    /* These are at specific offsets in the saved context */
    move.l  32(%sp), %a0         /* Caller's A0 */
    move.l  36(%sp), %d1         /* Caller's D1 */
    
    move.l  %a0, -(sp)
    move.l  %d1, -(sp)
    jsr     dump_memory_region
    addq.l  #8, %sp
    
    moveq   #0, %d0
    moveq   #0, %d1
    bra     .api_exit
    
    /* --- Function 5: LOG_MESSAGE --- */
.api_log_message:
    move.l  32(%sp), %a0         /* Caller's A0 (string pointer) */
    move.l  %a0, -(sp)
    jsr     log_message
    addq.l  #4, %sp
    
    moveq   #0, %d0
    moveq   #0, %d1
    bra     .api_exit
    
    /* --- Function 6: GET_CPU_TYPE --- */
.api_get_cpu_type:
    move.l  current_cpu_type, %d0
    moveq   #0, %d1
    bra     .api_exit
    
    /* --- Function 7: GET_API_MAGIC --- */
.api_get_api_magic:
    move.l  #API_MAGIC_NUMBER, %d0
    moveq   #0, %d1
    bra     .api_exit
    
    /* --- Function 8: INSTALL_NMI --- */
.api_install_nmi:
    jsr     install_nmi_handler
    moveq   #0, %d0
    moveq   #0, %d1
    bra     .api_exit
    
    /* --- Function 9: GET_BACKTRACE --- */
.api_get_backtrace:
    move.l  32(%sp), %a0         /* Buffer pointer */
    move.l  36(%sp), %d1         /* Max depth */
    
    /* Call backtrace function */
    move.l  %a0, -(sp)
    move.l  %d1, -(sp)
    jsr     generate_backtrace_68k
    addq.l  #8, %sp
    
    moveq   #0, %d0
    moveq   #0, %d1
    bra     .api_exit
    
    /* --- Function 10: CHECK_PRESENCE --- */
.api_check_presence:
    move.l  #API_MAGIC_NUMBER, %d0
    cmp.l   API_MAGIC_NUMBER_ADDRESS, %d0
    beq     .bootloader_present
    
    moveq   #0, %d0               /* Not present */
    bra     .api_exit_presence
    
.bootloader_present:
    moveq   #1, %d0               /* Bootloader present */
    
.api_exit_presence:
    moveq   #0, %d1
    bra     .api_exit
    
    /* ============================================ */
    /* Exit - Restore and Return */
    /* ============================================ */
.api_exit:
    /* Clean up temporary stack */
    add.l   #32, %sp
    
    /* Restore D0 (function result) */
    move.l  (%sp)+, %d0
    
    /* Restore all other registers */
    movem.l (%sp)+, %d1-%d7/%a0-%a6
    
    /* Return from trap */
    rte

/***************************************************************************
 * Helper Functions
 ***************************************************************************/

    .global dump_memory_region
    .global log_message
    .global generate_backtrace_68k

/* Dump memory region via serial */
dump_memory_region:
    movem.l %d0-%d3/%a0-%a2, -(sp)
    move.l  8(%sp), %a0          /* Start address */
    move.l  12(%sp), %d0         /* Size */
    
    /* Loop through memory */
    lsr.l   #2, %d0              /* Convert to longword count */
    beq     .dump_done
    
.dump_loop:
    move.l  (%a0)+, %d1
    move.l  %d1, -(sp)
    jsr     display_hex32
    addq.l  #4, %sp
    jsr     display_space
    
    dbra    %d0, .dump_loop
    
.dump_done:
    jsr     display_newline
    movem.l (%sp)+, %d0-%d3/%a0-%a2
    rts

/* Log message to debug console */
log_message:
    movem.l %d0/%a0, -(sp)
    move.l  8(%sp), %a0          /* String pointer */
    move.l  %a0, -(sp)
    jsr     display_string
    addq.l  #4, %sp
    jsr     display_newline
    movem.l (%sp)+, %d0/%a0
    rts

/* Generate backtrace for 68k */
generate_backtrace_68k:
    movem.l %d0-%d3/%a0-%a2, -(sp)
    move.l  8(%sp), %a0          /* Buffer */
    move.l  12(%sp), %d0         /* Max depth */
    
    /* Get current frame pointer (A6) */
    move.l  %a6, %a1
    moveq   #0, %d1               /* Depth counter */
    
.bt_loop:
    cmp.l   #0, %a1
    beq     .bt_done
    cmp.l   %d0, %d1
    bge     .bt_done
    
    /* Store return address */
    move.l  4(%a1), %d2
    move.l  %d2, (%a0)+
    
    /* Move to next frame */
    move.l  (%a1), %a1
    addq.l  #1, %d1
    bra     .bt_loop
    
.bt_done:
    /* Store count */
    move.l  %d1, (%a0)+
    movem.l (%sp)+, %d0-%d3/%a0-%a2
    rts

    .extern detect_qemu_environment
    .extern display_hex32
    .extern display_space
    .extern display_newline
    .extern display_string

/***************************************************************************
 * Data Section
 ***************************************************************************/

    .data
    .align 4

/* Debugger verbosity level */
debugger_verbosity:
    .long 0x00000001   /* 0=silent, 1=normal, 2=verbose */

/* Current CPU type (from detection) */
current_cpu_type:
    .long CPU_ID_UNKNOWN

/* Bootloader version */
BOOTLOADER_VERSION:
    .long 0x00010002   /* v1.0.2 */
