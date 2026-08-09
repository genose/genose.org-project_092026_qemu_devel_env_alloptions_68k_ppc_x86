/***************************************************************************
 * PPC Helper Functions
 ***************************************************************************/

#include "config.h"

    .global cpu_get_id_ppc
    .global cpu_get_pvr_ppc
    .global cpu_halt_ppc
    .global cpu_reboot_ppc
    .global cpu_set_irq_ppc
    .text

cpu_get_id_ppc:
    lis 3, boot_info@h
    ori 3, 3, boot_info@l
    lwz 3, offsetof(BootInfo, cpu_type)(3)
    blr

cpu_get_pvr_ppc:
    mfspr 3, SPR_PVR
    blr

cpu_halt_ppc:
    mfmsr 4
    ori 4, 4, 0x8000
    mtmsr 4
.halt_loop_ppc:
    b .halt_loop_ppc

cpu_reboot_ppc:
    li 3, 0
    mtspr SPR_SRR0, 3
    mtspr SPR_SRR1, 3
    rfi

cpu_set_irq_ppc:
    mflr 0
    stwu 1, -16(1)
    stw 31, 12(1)
    mr 31, 3
    
    mfmsr 3
    cmpwi 31, 0
    beq disable_irq_ppc
    andi. 3, 3, ~0x8000
    bra set_irq_ppc

disable_irq_ppc:
    ori 3, 3, 0x8000

set_irq_ppc:
    mtmsr 3
    lwz 31, 12(1)
    addi 1, 1, 16
    mtlr 0
    blr
