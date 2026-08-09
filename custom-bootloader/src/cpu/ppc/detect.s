/***************************************************************************
 * Custom Bootloader - PowerPC CPU Detection
 * 
 * This file contains the PPC CPU detection logic that identifies which
 * member of the PowerPC family (601, 603, 604, 750, 7410, 7455, 970)
 * the code is running on.
 * 
 * Detection Method:
 * 1. Read the Processor Version Register (PVR) at SPR 287
 * 2. Extract the version field (high 16 bits)
 * 3. Compare against known PVR values
 * 
 * PPC Processor Version Register (PVR) Values:
 * - PPC601: 0x0001
 * - PPC603: 0x0003
 * - PPC604: 0x0004
 * - PPC750: 0x0008
 * - PPC7410: 0x000C
 * - PPC7455: 0x800C
 * - PPC970: 0x0039
 * 
 * Additional detection:
 * - Check for 64-bit support (PPC970)
 * - Check for AltiVec (PPC7410+)
 * - Check for SMP support
 * - Check for other features
 ***************************************************************************/

#include "config.h"

    .global determine_ppc_cpu
    .global detect_ppc_cpu
    .global setup_ppc_common
    .global setup_ppc970

    .text
    .align 4

/***************************************************************************
 * Main PPC CPU Detection Entry Point
 * 
 * This is the main entry point for PPC CPU detection.
 * It reads the PVR and determines the exact CPU model.
 * 
 * Output: R7 = CPU ID (CPU_ID_PPC601, CPU_ID_PPC603, etc.)
 *         R6 = Feature flags
 * Clobbers: R0-R12
 ***************************************************************************/

.determine_ppc_cpu:
.detect_ppc_cpu:
    /* Step 0: Save LR */
    mflr 0
    
    /* Step 1: Read Processor Version Register (PVR) */
    mfspr 3, SPR_PVR
    
    /* Step 2: Extract high 16 bits (version field) */
    rlwinm 4, 3, 16, 16, 31
    
    /* Step 3: Compare against known PVR values */
    
    /* PPC601 */
    cmplwi 4, PVR_PPC601
    beq ppc_601_detected
    
    /* PPC603 */
    cmplwi 4, PVR_PPC603
    beq ppc_603_detected
    
    /* PPC604 */
    cmplwi 4, PVR_PPC604
    beq ppc_604_detected
    
    /* PPC750 (G3) */
    cmplwi 4, PVR_PPC750
    beq ppc_750_detected
    
    /* PPC7410 (G4) */
    cmplwi 4, PVR_PPC7410
    beq ppc_7410_detected
    
    /* PPC7455 (G4 Enhanced) */
    cmplwi 4, 0x800C  /* Note: PPC7455 PVR is 0x800C */
    beq ppc_7455_detected
    
    /* PPC970 (G5) */
    cmplwi 4, PVR_PPC970
    beq ppc_970_detected
    
    /* Unknown PPC */
    li 7, CPU_ID_UNKNOWN
    li 6, 0
    bra setup_ppc_common
    
/***************************************************************************
 * CPU-Specific Detection
 * 
 * Each section sets up the CPU ID and feature flags for a specific PPC model.
 ***************************************************************************/

ppc_601_detected:
    li 7, CPU_ID_PPC601
    li 6, CPU_FEATURE_PPC_MMU|CPU_FEATURE_PPC_FPU
    bra setup_ppc_common

ppc_603_detected:
    li 7, CPU_ID_PPC603
    li 6, CPU_FEATURE_PPC_MMU|CPU_FEATURE_PPC_FPU
    bra setup_ppc_common

ppc_604_detected:
    li 7, CPU_ID_PPC604
    li 6, CPU_FEATURE_PPC_MMU|CPU_FEATURE_PPC_FPU
    bra setup_ppc_common

ppc_750_detected:
    li 7, CPU_ID_PPC750
    li 6, CPU_FEATURE_PPC_MMU|CPU_FEATURE_PPC_FPU|CPU_FEATURE_PPC_SMP
    bra setup_ppc_common

ppc_7410_detected:
    li 7, CPU_ID_PPC7410
    li 6, CPU_FEATURE_PPC_MMU|CPU_FEATURE_PPC_FPU|CPU_FEATURE_PPC_SMP|CPU_FEATURE_PPC_ALTIVEC
    bra setup_ppc_common

ppc_7455_detected:
    li 7, CPU_ID_PPC7455
    li 6, CPU_FEATURE_PPC_MMU|CPU_FEATURE_PPC_FPU|CPU_FEATURE_PPC_SMP|CPU_FEATURE_PPC_ALTIVEC
    bra setup_ppc_common

ppc_970_detected:
    li 7, CPU_ID_PPC970
    li 6, CPU_FEATURE_PPC_MMU|CPU_FEATURE_PPC_FPU|CPU_FEATURE_PPC_SMP|CPU_FEATURE_PPC_ALTIVEC|CPU_FEATURE_PPC_64BIT
    bra setup_ppc970

/***************************************************************************
 * PPC970 Specific Initialization
 * 
 * The PPC970 (G5) is a 64-bit processor, so we need special initialization.
 * 
 * Input: R7 = CPU ID
 *        R6 = Feature flags
 * Clobbers: R0-R12
 ***************************************************************************/

setup_ppc970:
    /* Enable 64-bit mode if needed */
    /* The bootloader can run in 32-bit mode, but we should */
    /* set up the CPU for 64-bit operation if requested */
    
    /* For now, just continue with common setup */
    bra setup_ppc_common

/***************************************************************************
 * Common PPC Setup
 * 
 * Final setup after CPU detection.
 * Stores the CPU ID and feature flags in the BootInfo structure.
 * 
 * Input: R7 = CPU ID
 *        R6 = Feature flags
 * Clobbers: R0-R12
 ***************************************************************************/

setup_ppc_common:
    /* Save LR if not already saved */
    mflr 0
    stwu 1, -16(1)
    stw 0, 20(1)
    
    /* Store CPU ID in BootInfo */
    lis 3, boot_info@h
    ori 3, 3, boot_info@l
    li 4, offsetof(BootInfo, cpu_type)
    stw 7, 0(3, 4)
    
    /* Store feature flags */
    li 4, offsetof(BootInfo, cpu_features)
    stw 6, 0(3, 4)
    
    /* Initialize CPU-specific display */
    bl init_display_ppc
    
    /* Display CPU-specific message */
    mr 3, 7
    bl display_cpu_name_ppc
    
    /* Restore LR */
    lwz 0, 20(1)
    mtlr 0
    addi 1, 1, 16
    
    blr

/***************************************************************************
 * Additional Feature Detection
 * 
 * Detects additional CPU features beyond the basic model identification.
 * 
 * Input: R3 = CPU ID
 * Output: R3 = Feature flags
 * Clobbers: R0-R12
 ***************************************************************************/

detect_ppc_features:
    /* Save LR */
    mflr 0
    stwu 1, -16(1)
    stw 31, 12(1)
    mr 31, 3               /* Save CPU ID */
    
    /* Start with base features */
    li 3, CPU_FEATURE_PPC_MMU|CPU_FEATURE_PPC_FPU
    
    /* Check for 64-bit support */
    cmpwi 31, CPU_ID_PPC970
    bne check_altivec
    oris 3, 3, CPU_FEATURE_PPC_64BIT >> 16
    
.check_altivec:
    /* Check for AltiVec */
    cmpwi 31, CPU_ID_PPC7410
    beq has_altivec
    cmpwi 31, CPU_ID_PPC7455
    beq has_altivec
    cmpwi 31, CPU_ID_PPC970
    beq has_altivec
    bra check_smp
    
.has_altivec:
    oris 3, 3, CPU_FEATURE_PPC_ALTIVEC >> 16
    
.check_smp:
    /* Check for SMP support */
    cmpwi 31, CPU_ID_PPC604
    beq has_smp
    cmpwi 31, CPU_ID_PPC750
    beq has_smp
    cmpwi 31, CPU_ID_PPC7410
    beq has_smp
    cmpwi 31, CPU_ID_PPC7455
    beq has_smp
    cmpwi 31, CPU_ID_PPC970
    beq has_smp
    bra features_done
    
.has_smp:
    oris 3, 3, CPU_FEATURE_PPC_SMP >> 16
    
.features_done:
    /* Restore R31 */
    lwz 31, 12(1)
    
    /* Restore LR */
    lwz 0, 20(1)
    mtlr 0
    addi 1, 1, 16
    
    blr

/***************************************************************************
 * Get PVR (PPC)
 * 
 * Reads the Processor Version Register.
 * 
 * Output: R3 = PVR value
 * Clobbers: R3
 ***************************************************************************/

get_pvr_ppc:
    mfspr 3, SPR_PVR
    blr

/***************************************************************************
 * Get PIR (PPC)
 * 
 * Reads the Processor Identification Register (for SMP).
 * 
 * Output: R3 = PIR value
 * Clobbers: R3
 ***************************************************************************/

get_pir_ppc:
    mfspr 3, SPR_PIR
    blr

/***************************************************************************
 * Get CPU ID (PPC)
 * 
 * Returns the CPU type identifier.
 * 
 * Output: R3 = CPU ID
 * Clobbers: R3
 ***************************************************************************/

cpu_get_id_ppc:
    lis 3, boot_info@h
    ori 3, 3, boot_info@l
    lwz 3, offsetof(BootInfo, cpu_type)(3)
    blr

/***************************************************************************
 * Get CPU Features (PPC)
 * 
 * Returns the CPU feature flags.
 * 
 * Output: R3 = Feature flags
 * Clobbers: R3
 ***************************************************************************/

cpu_get_features_ppc:
    lis 3, boot_info@h
    ori 3, 3, boot_info@l
    lwz 3, offsetof(BootInfo, cpu_features)(3)
    blr

/***************************************************************************
 * Data Section
 * 
 * Contains any data needed by CPU detection.
 ***************************************************************************/

    .data
    .align 4

/*** CPU Name Table ***/
ppc_cpu_name_table:
    .long CPU_ID_PPC601
    .long msg_ppc601_running
    .long CPU_ID_PPC603
    .long msg_ppc603_running
    .long CPU_ID_PPC604
    .long msg_ppc604_running
    .long CPU_ID_PPC750
    .long msg_ppc750_running
    .long CPU_ID_PPC7410
    .long msg_ppc7410_running
    .long CPU_ID_PPC7455
    .long msg_ppc7455_running
    .long CPU_ID_PPC970
    .long msg_ppc970_running
    .long 0
    .long 0

/*** Messages ***/
msg_detecting_ppc_cpu:
    .asciz "Detecting PowerPC CPU ...\r\n"

msg_unknown_ppc:
    .asciz "Unknown PowerPC"

/***************************************************************************
 * End of File
 ***************************************************************************/
