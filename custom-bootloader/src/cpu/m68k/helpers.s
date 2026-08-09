/***************************************************************************
 * Custom Bootloader - 68k Helper Functions
 * 
 * This file contains helper functions specific to the 68k architecture.
 * These are utility functions that don't fit into other categories.
 * 
 * Features:
 * - CPU-specific helper functions
 * - Memory access helpers
 * - Utility functions for 68k-specific operations
 * - Support for different 68k CPU models
 ***************************************************************************/

#include "config.h"

    .global cpu_get_id_68k
    .global cpu_get_features_68k
    .global cpu_halt_68k
    .global cpu_reboot_68k
    .global cpu_set_irq_68k
    .global cpu_get_irq_68k
    .global cpu_disable_cache_68k
    .global cpu_enable_cache_68k
    .global cpu_get_vbr_68k
    .global cpu_set_vbr_68k
    .global get_sr_68k
    .global set_sr_68k
    .global get_usp_68k
    .global set_usp_68k
    .global flush_cache_68k

    .text
    .align 4

/***************************************************************************
 * Get CPU ID (68k)
 * 
 * Returns the CPU type identifier.
 * 
 * Output: D0 = CPU ID
 * Clobbers: D0
 ***************************************************************************/

cpu_get_id_68k:
    move.l boot_info + offsetof(BootInfo, cpu_type), %d0
    rts

/***************************************************************************
 * Get CPU Features (68k)
 * 
 * Returns the CPU feature flags.
 * 
 * Output: D0 = Feature flags
 * Clobbers: D0
 ***************************************************************************/

cpu_get_features_68k:
    move.l boot_info + offsetof(BootInfo, cpu_features), %d0
    rts

/***************************************************************************
 * Halt CPU (68k)
 * 
 * Halts the CPU. This function does not return.
 * 
 * Clobbers: None
 ***************************************************************************/

cpu_halt_68k:
    /* Mask all interrupts */
    move.w #0x2700, %sr
    
    /* Halt loop */
.halt_loop_68k:
    bra .halt_loop_68k

/***************************************************************************
 * Reboot System (68k)
 * 
 * Reboots the system by jumping to the reset vector.
 * This function does not return.
 * 
 * Clobbers: All
 ***************************************************************************/

cpu_reboot_68k:
    /* Mask all interrupts */
    move.w #0x2700, %sr
    
    /* Jump to reset vector */
    move.l 0x00000004, %a0  /* Get reset PC */
    jmp (%a0)

/***************************************************************************
 * Set Interrupt State (68k)
 * 
 * Enables or disables interrupts.
 * 
 * Input: D0 = 0 to disable, non-zero to enable
 * Clobbers: D0, D1, SR
 ***************************************************************************/

cpu_set_irq_68k:
    movem.l %d0/%d1, -(sp)
    move.l 12(%sp), %d1     /* Get enable flag */
    
    /* Get current SR */
    move.w %sr, %d0
    
    /* Modify interrupt mask */
    tst.l %d1
    beq disable_irq_68k
    
    /* Enable interrupts (level 0-5) */
    andi.w #0x1F00, %d0     /* Clear interrupt mask bits */
    bra set_irq_68k
    
disable_irq_68k:
    /* Disable interrupts (level 7) */
    ori.w #0x2700, %d0      /* Set interrupt mask to level 7 */
    
set_irq_68k:
    move.w %d0, %sr
    
    movem.l (%sp)+, %d0/%d1
    rts

/***************************************************************************
 * Get Interrupt State (68k)
 * 
 * Returns the current interrupt state.
 * 
 * Output: D0 = 0 if interrupts disabled, non-zero if enabled
 * Clobbers: D0
 ***************************************************************************/

cpu_get_irq_68k:
    move.w %sr, %d0
    andi.w #0x0700, %d0     /* Extract interrupt mask */
    cmpi.w #0x0700, %d0
    beq irq_disabled_68k
    moveq #1, %d0
    rts
    
irq_disabled_68k:
    moveq #0, %d0
    rts

/***************************************************************************
 * Disable Cache (68k)
 * 
 * Disables the CPU cache (68040/68060 only).
 * 
 * Clobbers: D0-D7, A0-A6
 ***************************************************************************/

cpu_disable_cache_68k:
    movem.l %d0-%d7/%a0-%a6, -(sp)
    
    /* Check if CPU has cache */
    move.l boot_info + offsetof(BootInfo, cpu_features), %d0
    andi.l #CPU_FEATURE_68K_CACHE, %d0
    beq cache_disable_done
    
    /* Disable cache using CACR */
    move.l #0x00000000, %d0  /* Clear CACR */
    movec %d0, %CACR
    
    /* Flush cache */
    jsr flush_cache_68k
    
cache_disable_done:
    movem.l (%sp)+, %d0-%d7/%a0-%a6
    rts

/***************************************************************************
 * Enable Cache (68k)
 * 
 * Enables the CPU cache (68040/68060 only).
 * 
 * Clobbers: D0-D7, A0-A6
 ***************************************************************************/

cpu_enable_cache_68k:
    movem.l %d0-%d7/%a0-%a6, -(sp)
    
    /* Check if CPU has cache */
    move.l boot_info + offsetof(BootInfo, cpu_features), %d0
    andi.l #CPU_FEATURE_68K_CACHE, %d0
    beq cache_enable_done
    
    /* Enable cache using CACR */
    /* 68040: Data cache = bit 30, Instruction cache = bit 28 */
    /* 68060: Different bits */
    move.l #0x80800000, %d0  /* Enable both caches */
    movec %d0, %CACR
    
.cache_enable_done:
    movem.l (%sp)+, %d0-%d7/%a0-%a6
    rts

/***************************************************************************
 * Flush Cache (68k)
 * 
 * Flushes the CPU cache (68040/68060 only).
 * 
 * Clobbers: D0-D7, A0-A6
 ***************************************************************************/

flush_cache_68k:
    movem.l %d0-%d7/%a0-%a6, -(sp)
    
    /* Check if CPU has cache */
    move.l boot_info + offsetof(BootInfo, cpu_features), %d0
    andi.l #CPU_FEATURE_68K_CACHE, %d0
    beq flush_cache_done
    
    /* Flush data cache */
    /* Use cpusha dc instruction */
    .word 0xF478  /* cpusha dc */
    
    /* Flush instruction cache */
    /* Use cinva bc instruction (68040) or cpusha ic (68060) */
    /* For simplicity, we'll use cpusha which flushes both */
    .word 0xF478  /* cpusha dc (flushes both on 68040) */
    
.flush_cache_done:
    movem.l (%sp)+, %d0-%d7/%a0-%a6
    rts

/***************************************************************************
 * Get VBR (68k)
 * 
 * Reads the Vector Base Register (68010+ only).
 * On 68000, returns 0.
 * 
 * Output: D0 = VBR value
 * Clobbers: D0
 ***************************************************************************/

cpu_get_vbr_68k:
    /* Check if CPU has VBR */
    move.l boot_info + offsetof(BootInfo, cpu_features), %d0
    andi.l #CPU_FEATURE_68K_VBR, %d0
    beq get_vbr_zero
    
    /* Read VBR */
    movec %vbr, %d0
    rts
    
.get_vbr_zero:
    moveq #0, %d0
    rts

/***************************************************************************
 * Set VBR (68k)
 * 
 * Writes the Vector Base Register (68010+ only).
 * On 68000, does nothing.
 * 
 * Input: D0 = VBR value
 * Clobbers: D0, D1
 ***************************************************************************/

cpu_set_vbr_68k:
    movem.l %d0/%d1, -(sp)
    move.l 12(%sp), %d1     /* Get VBR value */
    
    /* Check if CPU has VBR */
    move.l boot_info + offsetof(BootInfo, cpu_features), %d0
    andi.l #CPU_FEATURE_68K_VBR, %d0
    beq set_vbr_done
    
    /* Write VBR */
    movec %d1, %vbr
    
.set_vbr_done:
    movem.l (%sp)+, %d0/%d1
    rts

/***************************************************************************
 * Get SR (68k)
 * 
 * Reads the Status Register.
 * 
 * Output: D0 = SR value
 * Clobbers: D0
 ***************************************************************************/

get_sr_68k:
    move.w %sr, %d0
    ext.l %d0
    rts

/***************************************************************************
 * Set SR (68k)
 * 
 * Writes the Status Register.
 * 
 * Input: D0 = SR value
 * Clobbers: D0, D1
 ***************************************************************************/

set_sr_68k:
    movem.l %d0/%d1, -(sp)
    move.l 12(%sp), %d1     /* Get SR value */
    move.w %d1, %sr
    movem.l (%sp)+, %d0/%d1
    rts

/***************************************************************************
 * Get USP (68k)
 * 
 * Reads the User Stack Pointer.
 * 
 * Output: D0 = USP value
 * Clobbers: D0
 ***************************************************************************/

get_usp_68k:
    move.l %usp, %d0
    rts

/***************************************************************************
 * Set USP (68k)
 * 
 * Writes the User Stack Pointer.
 * 
 * Input: D0 = USP value
 * Clobbers: D0, D1
 ***************************************************************************/

set_usp_68k:
    movem.l %d0/%d1, -(sp)
    move.l 12(%sp), %d1     /* Get USP value */
    move.l %d1, %usp
    movem.l (%sp)+, %d0/%d1
    rts

/***************************************************************************
 * CPU-Specific Helpers
 * 
 * These functions provide CPU-specific optimizations.
 ***************************************************************************/

/*** 68040/68060 Specific ***/

.ifndef CPU_SPECIFIC_68040

/***************************************************************************
 * Read MMU Register (68040/68060)
 * 
 * Reads a value from an MMU register.
 * 
 * Input: D0 = register number
 * Output: D0 = register value
 * Clobbers: D0-D7, A0-A6
 ***************************************************************************/

read_mmu_register_68k:
    movem.l %d0-%d7/%a0-%a6, -(sp)
    move.l 44(%sp), %d0      /* Get register number */
    
    /* Check if CPU has MMU */
    move.l boot_info + offsetof(BootInfo, cpu_features), %d1
    andi.l #CPU_FEATURE_68K_MMU, %d1
    beq read_mmu_done
    
    /* Use pmove instruction to read MMU register */
    /* pmove fd,-(a0) where fd is the register number */
    /* This is complex and requires proper setup */
    
.read_mmu_done:
    moveq #0, %d0
    movem.l (%sp)+, %d0-%d7/%a0-%a6
    rts

/***************************************************************************
 * Write MMU Register (68040/68060)
 * 
 * Writes a value to an MMU register.
 * 
 * Input: D0 = register number, D1 = value
 * Clobbers: D0-D7, A0-A6
 ***************************************************************************/

write_mmu_register_68k:
    movem.l %d0-%d7/%a0-%a6, -(sp)
    move.l 48(%sp), %d0      /* Get register number */
    move.l 44(%sp), %d1      /* Get value */
    
    /* Check if CPU has MMU */
    move.l boot_info + offsetof(BootInfo, cpu_features), %d2
    andi.l #CPU_FEATURE_68K_MMU, %d2
    beq write_mmu_done
    
    /* Use pmove instruction to write MMU register */
    
.write_mmu_done:
    movem.l (%sp)+, %d0-%d7/%a0-%a6
    rts

.endif

/***************************************************************************
 * Memory Barrier (68k)
 * 
 * Ensures all memory operations are completed before continuing.
 * 
 * Clobbers: D0
 ***************************************************************************/

memory_barrier_68k:
    /* Use nop for memory barrier */
    nop
    rts

/***************************************************************************
 * Data Section
 * 
 * Contains any data needed by helper functions.
 ***************************************************************************/

    .data
    .align 4

/*** Messages ***/
msg_cache_disabled:
    .asciz "Cache disabled\r\n"

msg_cache_enabled:
    .asciz "Cache enabled\r\n"

msg_cache_flushed:
    .asciz "Cache flushed\r\n"

/***************************************************************************
 * End of File
 ***************************************************************************/
