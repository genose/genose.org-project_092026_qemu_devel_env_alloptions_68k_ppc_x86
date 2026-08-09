/***************************************************************************
 * Custom Bootloader - NMI (Non-Maskable Interrupt) Handler
 * 
 * Handler for vector 31 (0x0000007C) - Level 7 interrupt
 * This handler cannot be masked and will always execute, even if the system
 * is completely frozen. Used for emergency debugging and system recovery.
 * 
 * Architecture: 68k (Motorola 68000 family)
 * 
 * Features:
 * - Saves full CPU context to DEBUGGER_SHARED_SPACE (0x00F00000)
 * - Detects environment (QEMU vs real Mac)
 * - Triggers GDB break via UART on QEMU
 * - Falls back to MacsBug-style screen on real hardware
 * - Can resume execution after debugging
 ***************************************************************************/

#include "config.h"
#include "debug_shared.h"

    .global install_nmi_handler
    .global nmi_preempt_bridge
    .global nmi_handler_enabled

/***************************************************************************
 * Debugger Shared Space Configuration
 ***************************************************************************/

/* Base address for debugger shared memory */
#define DEBUGGER_BASE         0x00F00000
#define DEBUGGER_CTX_OFFSET   0x0000
#define DEBUGGER_STACK_OFFSET 0x0100
#define DEBUGGER_STACK_SIZE   0x1000  /* 4KB debug stack */

/* Debugger stack pointer (grows downward from DEBUGGER_BASE + offset) */
#define DEBUGGER_STACK_PTR    (DEBUGGER_BASE + DEBUGGER_STACK_OFFSET + DEBUGGER_STACK_SIZE)

/***************************************************************************
 * NMI Handler Enable Flag
 ***************************************************************************/

    .data
    .align 4

nmi_handler_enabled:
    .long 0x00000000   /* 0 = disabled, 1 = enabled */

    .text

/***************************************************************************
 * Install NMI Handler
 * 
 * Installs the NMI handler at vector 31 (0x0000007C).
 * This must be called during bootloader initialization.
 * 
 * Clobbers: A0, D0
 ***************************************************************************/

install_nmi_handler:
    /* Save link register if needed */
    movem.l %d0-%d1/%a0, -(sp)
    
    /* Check if already installed */
    move.l  0x0000007C, %d0
    cmp.l   #nmi_preempt_bridge, %d0
    beq     .already_installed
    
    /* Install NMI handler */
    lea     nmi_preempt_bridge(%pc), %a0
    move.l  %a0, 0x0000007C
    
    /* Mark as enabled */
    move.l  #1, nmi_handler_enabled
    
.already_installed:
    movem.l (%sp)+, %d0-%d1/%a0
    rts

/***************************************************************************
 * Uninstall NMI Handler
 * 
 * Removes the NMI handler and restores default behavior.
 * 
 * Clobbers: A0, D0
 ***************************************************************************/

    .global uninstall_nmi_handler

uninstall_nmi_handler:
    movem.l %d0/%a0, -(sp)
    
    /* Check if our handler is installed */
    move.l  0x0000007C, %d0
    cmp.l   #nmi_preempt_bridge, %d0
    bne     .not_ours
    
    /* Restore default NMI handler (usually ROM) */
    /* For now, just set to illegal instruction */
    lea     default_nmi_handler(%pc), %a0
    move.l  %a0, 0x0000007C
    
    /* Mark as disabled */
    clr.l   nmi_handler_enabled
    
.not_ours:
    movem.l (%sp)+, %d0/%a0
    rts

default_nmi_handler:
    illegal
    rte

/***************************************************************************
 * NMI Preempt Bridge
 * 
 * Main NMI handler entry point at vector 31 (0x7C).
 * This is the emergency handler that runs when system is frozen.
 * 
 * Execution flow:
 * 1. Save all CPU state to DEBUGGER_SHARED_SPACE
 * 2. Switch to dedicated debug stack
 * 3. Detect environment (QEMU vs real Mac)
 * 4. Trigger GDB on QEMU or MacsBug screen on real hardware
 * 5. Optionally resume execution
 * 
 * Note: On entry, hardware has pushed SR and PC onto the stack
 ***************************************************************************/

nmi_preempt_bridge:
    /* Phase 1: Save CPU state to DEBUGGER_SHARED_SPACE */
    
    /* Save data registers D0-D7 */
    movem.l %d0-%d7, (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x00)
    
    /* Save address registers A0-A6 */
    movem.l %a0-%a6, (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x20)
    
    /* Save USP (User Stack Pointer) from current A7 */
    move.l  %a7, (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x38)
    
    /* Get SR and PC from stack (pushed by NMI) */
    /* Stack on NMI entry: [old_SR][old_PC][...] */
    move.w  (%sp), %d0               /* Get SR from stack */
    move.l  %d0, (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x3C)
    
    move.l  2(%sp), %a0              /* Get PC from stack */
    move.l  %a0, (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x40)
    
    /* Phase 2: Switch to dedicated debug stack */
    /* We need to be careful here - we're on the system stack */
    lea     DEBUGGER_STACK_PTR, %sp  /* Switch to debug stack */
    
    /* Phase 3: Detect environment */
    jsr     detect_qemu_environment
    tst.l   %d0
    beq     .real_mac_path
    
    /* ==== QEMU Environment ==== */
    
    /* Set QEMU flag in shared space */
    move.l  #1, (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x44)
    
    /* Trigger GDB break via UART */
    move.b  #0x03, (0x50F0C000)    /* Send BREAK character to QEMU UART */
    
    /* Wait a bit for GDB to attach */
    move.l  #0x1000, %d0            /* Delay counter */
.nmi_wait_gdb:
    dbra    %d0, .nmi_wait_gdb
    
    /* Optionally enter debug shell */
    jsr     enter_debug_shell
    
    bra     .nmi_resume_check
    
    /* ==== Real Mac Environment ==== */
.real_mac_path:
    /* Set real Mac flag */
    clr.l   (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x44)
    
    /* Display MacsBug-style screen */
    jsr     draw_macsbug_screen
    
    /* Enter debug shell */
    jsr     enter_debug_shell
    
    /* ==== Resume Check ==== */
.nmi_resume_check:
    /* Check if we should resume execution */
    /* This would be set by the debug shell */
    move.l  (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x48), %d0
    tst.l   %d0
    beq     .nmi_no_resume
    
    /* Resume execution - restore context */
    
    /* Restore USP */
    move.l  (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x38), %a7
    
    /* Restore A0-A6 */
    movem.l (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x20), %a0-%a6
    
    /* Restore D0-D7 */
    movem.l (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x00), %d0-%d7
    
    /* Clear resume flag */
    clr.l   (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x48)
    
    /* Return from exception - will resume at frozen PC */
    rte
    
.nmi_no_resume:
    /* Loop forever if not resuming */
    bra     .nmi_no_resume

/***************************************************************************
 * Enter Debug Shell
 * 
 * Simple debug shell for emergency operations.
 * Provides basic commands via serial console.
 * 
 * On QEMU: Uses UART at 0x50F0C000
 * On Real Mac: Would need VIA serial setup
 * 
 * Clobbers: All registers
 ***************************************************************************/

    .global enter_debug_shell

enter_debug_shell:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    
    /* Print debug shell banner */
    pea     msg_nmi_banner(%pc)
    jsr     display_string
    addq.l  #4, %sp
    
    /* Print commands */
    pea     msg_nmi_help(%pc)
    jsr     display_string
    addq.l  #4, %sp
    
.debug_shell_loop:
    /* Read command from serial */
    jsr     console_getc
    cmp.b   #'r', %d0
    beq     .cmd_resume
    cmp.b   #'R', %d0
    beq     .cmd_resume
    cmp.b   #'d', %d0
    beq     .cmd_dump
    cmp.b   #'D', %d0
    beq     .cmd_dump
    cmp.b   #'b', %d0
    beq     .cmd_backtrace
    cmp.b   #'B', %d0
    beq     .cmd_backtrace
    cmp.b   #'g', %d0
    beq     .cmd_gdb
    cmp.b   #'G', %d0
    beq     .cmd_gdb
    cmp.b   #'h', %d0
    beq     .cmd_help
    cmp.b   #'H', %d0
    beq     .cmd_help
    cmp.b   #0x0D, %d0       /* Enter */
    beq     .debug_shell_loop
    cmp.b   #0x0A, %d0       /* Newline */
    beq     .debug_shell_loop
    
    /* Unknown command */
    pea     msg_unknown_cmd(%pc)
    jsr     display_string
    addq.l  #4, %sp
    bra     .debug_shell_loop
    
.cmd_resume:
    /* Set resume flag */
    move.l  #1, (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x48)
    bra     .debug_shell_exit
    
.cmd_dump:
    /* Dump registers */
    jsr     dump_registers
    bra     .debug_shell_loop
    
.cmd_backtrace:
    /* Show backtrace */
    jsr     display_backtrace
    bra     .debug_shell_loop
    
.cmd_gdb:
    /* Force GDB break */
    move.b  #0x03, (0x50F0C000)
    bra     .debug_shell_loop
    
.cmd_help:
    pea     msg_nmi_help(%pc)
    jsr     display_string
    addq.l  #4, %sp
    bra     .debug_shell_loop
    
.debug_shell_exit:
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rts

/***************************************************************************
 * Dump Registers
 * 
 * Displays all CPU registers from saved context.
 * 
 * Clobbers: D0, A0
 ***************************************************************************/

    .global dump_registers

dump_registers:
    movem.l %d0-%d1/%a0-%a1, -(sp)
    
    /* Display D0-D7 */
    pea     msg_reg_d0(%pc)
    jsr     display_string
    addq.l  #4, %sp
    move.l  (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x00), %d0
    move.l  %d0, -(sp)
    jsr     display_hex32
    addq.l  #4, %sp
    jsr     display_newline
    
    /* Display A0-A6 */
    pea     msg_reg_a0(%pc)
    jsr     display_string
    addq.l  #4, %sp
    move.l  (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x20), %d0
    move.l  %d0, -(sp)
    jsr     display_hex32
    addq.l  #4, %sp
    jsr     display_newline
    
    /* Display USP */
    pea     msg_reg_usp(%pc)
    jsr     display_string
    addq.l  #4, %sp
    move.l  (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x38), %d0
    move.l  %d0, -(sp)
    jsr     display_hex32
    addq.l  #4, %sp
    jsr     display_newline
    
    /* Display SR */
    pea     msg_reg_sr(%pc)
    jsr     display_string
    addq.l  #4, %sp
    move.w  (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x3C), %d0
    move.l  %d0, -(sp)
    jsr     display_hex16
    addq.l  #4, %sp
    jsr     display_newline
    
    /* Display PC */
    pea     msg_reg_pc(%pc)
    jsr     display_string
    addq.l  #4, %sp
    move.l  (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x40), %d0
    move.l  %d0, -(sp)
    jsr     display_hex32
    addq.l  #4, %sp
    jsr     display_newline
    
    movem.l (%sp)+, %d0-%d1/%a0-%a1
    rts

/***************************************************************************
 * Display Backtrace
 * 
 * Displays the backtrace from saved context.
 * Walks the stack frame chain.
 * 
 * Clobbers: D0-D3, A0-A2
 ***************************************************************************/

    .global display_backtrace

display_backtrace:
    movem.l %d0-%d3/%a0-%a2, -(sp)
    
    pea     msg_backtrace(%pc)
    jsr     display_string
    addq.l  #4, %sp
    
    /* Get initial frame pointer (A6 from context) */
    move.l  (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET + 0x20 + 0x18), %a0  /* A6 */
    move.l  %a0, %a1              /* Frame pointer in A1 */
    moveq   #0, %d0               /* Depth counter */
    
.bt_loop:
    cmp.l   #0, %a1
    beq     .bt_done
    cmp.l   #10, %d0             /* Max depth */
    bge     .bt_done
    
    /* Display depth */
    move.l  %d0, -(sp)
    jsr     display_hex8
    addq.l  #4, %sp
    pea     msg_bt_colon(%pc)
    jsr     display_string
    addq.l  #4, %sp
    
    /* Get return address (frame+4) */
    move.l  4(%a1), %d1
    move.l  %d1, -(sp)
    jsr     display_hex32
    addq.l  #4, %sp
    jsr     display_newline
    
    /* Move to next frame */
    move.l  (%a1), %a1           /* Previous frame pointer */
    addq.l  #1, %d0
    bra     .bt_loop
    
.bt_done:
    movem.l (%sp)+, %d0-%d3/%a0-%a2
    rts

/***************************************************************************
 * Messages
 ***************************************************************************/

    .data
    .align 4

msg_nmi_banner:
    .asciz "\r\n=== NMI DEBUG SHELL ===\r\n"

msg_nmi_help:
    .asciz "Commands: R=Resume, D=Dump regs, B=Backtrace, G=GDB, H=Help\r\n"

msg_unknown_cmd:
    .asciz "\r\nUnknown command. Type H for help.\r\n"

msg_reg_d0:
    .asciz "D0="

msg_reg_a0:
    .asciz "A0="

msg_reg_usp:
    .asciz "USP="

msg_reg_sr:
    .asciz "SR="

msg_reg_pc:
    .asciz "PC="

msg_backtrace:
    .asciz "\r\nBacktrace:\r\n"

msg_bt_colon:
    .asciz ": "

/***************************************************************************
 * Helper functions (extern)
 ***************************************************************************/

    .extern display_string
    .extern display_hex32
    .extern display_hex16
    .extern display_hex8
    .extern display_newline
    .extern console_getc
    .extern detect_qemu_environment
