/***************************************************************************
 * Custom Bootloader - Exception Vectors
 * 
 * This file contains the complete exception vector table for 68k and PPC.
 * It provides MacsBug-style exception handling with comprehensive debugging.
 ***************************************************************************/

#include "config.h"

    .global init_exception_vectors
    .global init_ppc_vectors
    .global bus_error_handler
    .global addr_error_handler
    .global ill_inst_handler
    .global zero_div_handler
    .global chk_handler
    .global trap_handler

    .text

/***************************************************************************
 * 68k Exception Vector Table
 * 
 * The 68k family has 256 exception vectors (0x00-0xFF).
 * We set up handlers for the most common exceptions.
 ***************************************************************************/

init_exception_vectors:
    /* Install handlers for critical exceptions */
    
    /* Vector 0x00: Reset (handled by hardware) */
    /* Vector 0x01: Reset (PC) - handled by hardware */
    
    /* Vector 0x02: Bus Error */
    move.l #bus_error_handler, 0x00000008
    
    /* Vector 0x03: Address Error */
    move.l #addr_error_handler, 0x0000000C
    
    /* Vector 0x04: Illegal Instruction */
    move.l #ill_inst_handler, 0x00000010
    
    /* Vector 0x05: Zero Divide */
    move.l #zero_div_handler, 0x00000014
    
    /* Vector 0x06: CHK/CHK2 Instruction */
    move.l #chk_handler, 0x00000018
    
    /* Vector 0x07: TRAPcc Instruction */
    move.l #trap_handler, 0x0000001C
    
    /* Vector 0x08: Privilege Violation */
    move.l #privilege_violation_handler, 0x00000020
    
    /* Vector 0x09: Trace */
    move.l #trace_handler, 0x00000024
    
    /* Vector 0x0A: Line A Emulator */
    move.l #linea_emulator_handler, 0x00000028
    
    /* Vector 0x0B: Line F Emulator */
    move.l #linef_emulator_handler, 0x0000002C
    
    /* Vector 0x0D: Coprocessor Protocol Violation */
    move.l #coprocessor_violation_handler, 0x00000034
    
    /* Vector 0x0F: Format Error */
    move.l #format_error_handler, 0x0000003C
    
    /* Vector 0x10: Uninitialized Interrupt */
    move.l #uninitialized_int_handler, 0x00000040
    
    /* Vector 0x11-0x17: Reserved */
    
    /* Vector 0x18-0x1E: Level 1-7 Interrupts */
    move.l #int_handler_1, 0x00000060
    move.l #int_handler_2, 0x00000064
    move.l #int_handler_3, 0x00000068
    move.l #int_handler_4, 0x0000006C
    move.l #int_handler_5, 0x00000070
    move.l #int_handler_6, 0x00000074
    move.l #int_handler_7, 0x00000078
    
    /* Vector 0x1F: Spurious Interrupt */
    move.l #spurious_int_handler, 0x0000007C
    
    /* Vector 0x20-0x3F: TRAP #0 - TRAP #15 */
    move.l #trap_0_handler, 0x00000080
    move.l #trap_1_handler, 0x00000084
    move.l #trap_2_handler, 0x00000088
    move.l #trap_3_handler, 0x0000008C
    move.l #trap_4_handler, 0x00000090
    move.l #trap_5_handler, 0x00000094
    move.l #trap_6_handler, 0x00000098
    move.l #trap_7_handler, 0x0000009C
    move.l #trap_8_handler, 0x000000A0
    move.l #trap_9_handler, 0x000000A4
    move.l #trap_10_handler, 0x000000A8
    move.l #trap_11_handler, 0x000000AC
    move.l #trap_12_handler, 0x000000B0
    move.l #trap_13_handler, 0x000000B4
    move.l #trap_14_handler, 0x000000B8
    move.l #trap_15_handler, 0x000000BC
    
    rts

/***************************************************************************
 * PPC Exception Vector Initialization
 * 
 * Sets up PowerPC exception vectors.
 * PPC uses a different mechanism (IVOR registers or memory-mapped vectors).
 ***************************************************************************/

init_ppc_vectors:
    /* Save LR */
    mflr 0
    
    /* Set up critical exception handlers */
    /* Using memory-mapped approach for simplicity */
    
    /* Machine Check (0x200) */
    lis 3, machine_check_handler@h
    ori 3, 3, machine_check_handler@l
    mtspr IVOR0, 3
    
    /* DSI (Data Storage Interrupt) (0x300) */
    lis 3, dsi_handler@h
    ori 3, 3, dsi_handler@l
    mtspr IVOR1, 3
    
    /* ISI (Instruction Storage Interrupt) (0x400) */
    lis 3, isi_handler@h
    ori 3, 3, isi_handler@l
    mtspr IVOR2, 3
    
    /* External Interrupt (0x500) */
    lis 3, ext_int_handler@h
    ori 3, 3, ext_int_handler@l
    mtspr IVOR3, 3
    
    /* Alignment (0x600) */
    lis 3, alignment_handler@h
    ori 3, 3, alignment_handler@l
    mtspr IVOR4, 4
    
    /* Program Exception (0x700) */
    lis 3, program_handler@h
    ori 3, 3, program_handler@l
    mtspr IVOR5, 3
    
    /* FP Unavailable (0x800) */
    lis 3, fpu_handler@h
    ori 3, 3, fpu_handler@l
    mtspr IVOR6, 3
    
    /* Decrementer (0x900) */
    lis 3, decrementer_handler@h
    ori 3, 3, decrementer_handler@l
    mtspr IVOR7, 3
    
    /* System Call (0xC00) */
    lis 3, syscall_handler@h
    ori 3, 3, syscall_handler@l
    mtspr IVOR8, 3
    
    /* Restore LR and return */
    mtlr 0
    blr

/***************************************************************************
 * 68k Exception Handlers
 * 
 * MacsBug-style exception handlers with full debugging support.
 * Each handler:
 * 1. Saves all registers
 * 2. Displays error message
 * 3. Shows backtrace
 * 4. Dumps registers
 * 5. Sets error status
 * 6. Loops forever (or returns for non-fatal)
 ***************************************************************************/

/* Bus Error Handler */
bus_error_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_bus_error(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

/* Address Error Handler */
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

/* Illegal Instruction Handler */
ill_inst_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_ill_inst(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* Extract fault information */
    move.l 60(%sp), %a0        /* Get PC from stack frame */
    move.l %a0, -(sp)
    pea msg_fault_pc(%pc)
    jsr printf
    addq.l #8, %sp
    
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

/* Zero Divide Handler */
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

/* CHK/TRAP Handler */
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

/* TRAP Instruction Handler */
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

/* Privilege Violation Handler */
privilege_violation_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_privilege(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

/* Trace Handler */
trace_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trace(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

/* Line A Emulator Handler */
linea_emulator_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_linea(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

/* Line F Emulator Handler */
linef_emulator_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_linef(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

/* Coprocessor Protocol Violation Handler */
coprocessor_violation_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_coproc(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

/* Format Error Handler */
format_error_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_format(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

/* Uninitialized Interrupt Handler */
uninitialized_int_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_uninit_int(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

/* Spurious Interrupt Handler */
spurious_int_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_spurious(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    move.l #STATUS_EXCEPTION, GDB_STATUS_ADDRESS
    move.l #0x1000, GDB_BREAKPOINT_ADDRESS
    bra halt_loop

/* Generic Interrupt Handlers (Level 1-7) */
int_handler_1:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_int1(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    /* For interrupts, we might want to return */
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

int_handler_2:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_int2(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

int_handler_3:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_int3(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

int_handler_4:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_int4(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

int_handler_5:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_int5(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

int_handler_6:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_int6(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

int_handler_7:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_int7(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

/* TRAP Handlers */
trap_0_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap0(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_1_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap1(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_2_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap2(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_3_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap3(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_4_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap4(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_5_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap5(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_6_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap6(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_7_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap7(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_8_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap8(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_9_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap9(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_10_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap10(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_11_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap11(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_12_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap12(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_13_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap13(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_14_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap14(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

trap_15_handler:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    pea msg_trap15(%pc)
    jsr display_string
    addq.l #4, %sp
    jsr backtrace_68k
    jsr dump_registers_68k
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    rte

/***************************************************************************
 * PPC Exception Handlers
 * 
 * PowerPC exception handlers with full debugging support.
 ***************************************************************************/

machine_check_handler:
    /* Save registers */
    mfspr 3, SRR0
    mfspr 4, SRR1
    stw 3, 4(1)
    stw 4, 8(1)
    stwu 1, -64(1)
    
    /* Display error message */
    lis 3, msg_machine_check@h
    ori 3, 3, msg_machine_check@l
    bl display_string_ppc
    
    /* Display backtrace */
    bl backtrace_ppc
    
    /* Display registers */
    bl dump_registers_ppc
    
    /* Set error status */
    lis 3, GDB_STATUS_ADDRESS@h
    ori 3, 3, GDB_STATUS_ADDRESS@l
    li 4, STATUS_EXCEPTION
    stw 4, 0(3)
    
    /* Set breakpoint */
    lis 3, GDB_BREAKPOINT_ADDRESS@h
    ori 3, 3, GDB_BREAKPOINT_ADDRESS@l
    li 4, 0x1000
    stw 4, 0(3)
    
    /* Loop forever */
    bl halt_loop_ppc

dsi_handler:
    mflr 0
    stw 0, 4(1)
    stwu 1, -64(1)
    
    lis 3, msg_dsi@h
    ori 3, 3, msg_dsi@l
    bl display_string_ppc
    
    bl backtrace_ppc
    bl dump_registers_ppc
    
    lis 3, GDB_STATUS_ADDRESS@h
    ori 3, 3, GDB_STATUS_ADDRESS@l
    li 4, STATUS_EXCEPTION
    stw 4, 0(3)
    
    lis 3, GDB_BREAKPOINT_ADDRESS@h
    ori 3, 3, GDB_BREAKPOINT_ADDRESS@l
    li 4, 0x1000
    stw 4, 0(3)
    
    bl halt_loop_ppc

isi_handler:
    mflr 0
    stw 0, 4(1)
    stwu 1, -64(1)
    
    lis 3, msg_isi@h
    ori 3, 3, msg_isi@l
    bl display_string_ppc
    
    bl backtrace_ppc
    bl dump_registers_ppc
    
    lis 3, GDB_STATUS_ADDRESS@h
    ori 3, 3, GDB_STATUS_ADDRESS@l
    li 4, STATUS_EXCEPTION
    stw 4, 0(3)
    
    lis 3, GDB_BREAKPOINT_ADDRESS@h
    ori 3, 3, GDB_BREAKPOINT_ADDRESS@l
    li 4, 0x1000
    stw 4, 0(3)
    
    bl halt_loop_ppc

ext_int_handler:
    mfspr 3, SRR0
    mfspr 4, SRR1
    stw 3, 4(1)
    stw 4, 8(1)
    stwu 1, -64(1)
    
    lis 3, msg_ext_int@h
    ori 3, 3, msg_ext_int@l
    bl display_string_ppc
    
    bl backtrace_ppc
    
    /* For interrupts, we might want to return */
    lwz 3, 4(1)
    lwz 4, 8(1)
    mtlr 3
    mtmsr 4
    addi 1, 1, 64
    rfi

alignment_handler:
    mflr 0
    stw 0, 4(1)
    stwu 1, -64(1)
    
    lis 3, msg_alignment@h
    ori 3, 3, msg_alignment@l
    bl display_string_ppc
    
    bl backtrace_ppc
    bl dump_registers_ppc
    
    lis 3, GDB_STATUS_ADDRESS@h
    ori 3, 3, GDB_STATUS_ADDRESS@l
    li 4, STATUS_EXCEPTION
    stw 4, 0(3)
    
    bl halt_loop_ppc

program_handler:
    mflr 0
    stw 0, 4(1)
    stwu 1, -64(1)
    
    lis 3, msg_program@h
    ori 3, 3, msg_program@l
    bl display_string_ppc
    
    bl backtrace_ppc
    bl dump_registers_ppc
    
    lis 3, GDB_STATUS_ADDRESS@h
    ori 3, 3, GDB_STATUS_ADDRESS@l
    li 4, STATUS_EXCEPTION
    stw 4, 0(3)
    
    bl halt_loop_ppc

fpu_handler:
    mflr 0
    stw 0, 4(1)
    stwu 1, -64(1)
    
    lis 3, msg_fpu@h
    ori 3, 3, msg_fpu@l
    bl display_string_ppc
    
    bl backtrace_ppc
    bl dump_registers_ppc
    
    lis 3, GDB_STATUS_ADDRESS@h
    ori 3, 3, GDB_STATUS_ADDRESS@l
    li 4, STATUS_EXCEPTION
    stw 4, 0(3)
    
    bl halt_loop_ppc

decrementer_handler:
    mflr 0
    stw 0, 4(1)
    stwu 1, -64(1)
    
    lis 3, msg_decrementer@h
    ori 3, 3, msg_decrementer@l
    bl display_string_ppc
    
    bl backtrace_ppc
    
    /* For decrementer, we might want to return */
    lwz 0, 4(1)
    mtlr 0
    addi 1, 1, 64
    rfi

syscall_handler:
    mflr 0
    stw 0, 4(1)
    stwu 1, -64(1)
    
    lis 3, msg_syscall@h
    ori 3, 3, msg_syscall@l
    bl display_string_ppc
    
    bl backtrace_ppc
    bl dump_registers_ppc
    
    /* For system calls, we might want to handle them */
    lwz 0, 4(1)
    mtlr 0
    addi 1, 1, 64
    rfi

/***************************************************************************
 * PPC Halt Loop
 ***************************************************************************/

halt_loop_ppc:
    bl halt_loop_ppc

/***************************************************************************
 * Data Section
 * 
 * Contains error messages and data.
 ***************************************************************************/

    .data

/*** 68k Messages ***/
msg_bus_error:
    .asciz "\r\nBus Error!\r\n"

msg_addr_error:
    .asciz "\r\nAddress Error!\r\n"

msg_ill_inst:
    .asciz "\r\nIllegal Instruction!\r\n"

msg_fault_pc:
    .asciz " Fault PC: 0x%08X\r\n"

msg_zero_div:
    .asciz "\r\nZero Divide!\r\n"

msg_chk:
    .asciz "\r\nCHK/CHK2 Instruction!\r\n"

msg_trap:
    .asciz "\r\nTRAP Instruction!\r\n"

msg_privilege:
    .asciz "\r\nPrivilege Violation!\r\n"

msg_trace:
    .asciz "\r\nTrace Exception!\r\n"

msg_linea:
    .asciz "\r\nLine A Emulator!\r\n"

msg_linef:
    .asciz "\r\nLine F Emulator!\r\n"

msg_coproc:
    .asciz "\r\nCoprocessor Protocol Violation!\r\n"

msg_format:
    .asciz "\r\nFormat Error!\r\n"

msg_uninit_int:
    .asciz "\r\nUninitialized Interrupt!\r\n"

msg_spurious:
    .asciz "\r\nSpurious Interrupt!\r\n"

msg_int1:
    .asciz "\r\nLevel 1 Interrupt\r\n"

msg_int2:
    .asciz "\r\nLevel 2 Interrupt\r\n"

msg_int3:
    .asciz "\r\nLevel 3 Interrupt\r\n"

msg_int4:
    .asciz "\r\nLevel 4 Interrupt\r\n"

msg_int5:
    .asciz "\r\nLevel 5 Interrupt\r\n"

msg_int6:
    .asciz "\r\nLevel 6 Interrupt\r\n"

msg_int7:
    .asciz "\r\nLevel 7 Interrupt\r\n"

msg_trap0:
    .asciz "\r\nTRAP #0\r\n"

msg_trap1:
    .asciz "\r\nTRAP #1\r\n"

msg_trap2:
    .asciz "\r\nTRAP #2\r\n"

msg_trap3:
    .asciz "\r\nTRAP #3\r\n"

msg_trap4:
    .asciz "\r\nTRAP #4\r\n"

msg_trap5:
    .asciz "\r\nTRAP #5\r\n"

msg_trap6:
    .asciz "\r\nTRAP #6\r\n"

msg_trap7:
    .asciz "\r\nTRAP #7\r\n"

msg_trap8:
    .asciz "\r\nTRAP #8\r\n"

msg_trap9:
    .asciz "\r\nTRAP #9\r\n"

msg_trap10:
    .asciz "\r\nTRAP #10\r\n"

msg_trap11:
    .asciz "\r\nTRAP #11\r\n"

msg_trap12:
    .asciz "\r\nTRAP #12\r\n"

msg_trap13:
    .asciz "\r\nTRAP #13\r\n"

msg_trap14:
    .asciz "\r\nTRAP #14\r\n"

msg_trap15:
    .asciz "\r\nTRAP #15\r\n"

/*** PPC Messages ***/
msg_machine_check:
    .asciz "\r\nMachine Check Exception!\r\n"

msg_dsi:
    .asciz "\r\nData Storage Interrupt!\r\n"

msg_isi:
    .asciz "\r\nInstruction Storage Interrupt!\r\n"

msg_ext_int:
    .asciz "\r\nExternal Interrupt!\r\n"

msg_alignment:
    .asciz "\r\nAlignment Exception!\r\n"

msg_program:
    .asciz "\r\nProgram Exception!\r\n"

msg_fpu:
    .asciz "\r\nFPU Unavailable!\r\n"

msg_decrementer:
    .asciz "\r\nDecrementer Exception!\r\n"

msg_syscall:
    .asciz "\r\nSystem Call Exception!\r\n"

/***************************************************************************
 * End of File
 ***************************************************************************/
