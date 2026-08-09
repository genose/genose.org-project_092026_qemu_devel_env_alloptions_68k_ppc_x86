/***************************************************************************
 * PPC Backtrace Implementation
 ***************************************************************************/

#include "config.h"

    .global backtrace_ppc
    .text

backtrace_ppc:
    mflr 0
    stwu 1, -64(1)
    mr 10, 1          /* Save FP in R10 */
    li 9, 0           /* Frame counter in R9 */

    lis 3, msg_backtrace_ppc@h
    ori 3, 3, msg_backtrace_ppc@l
    bl display_string_ppc

.backtrace_loop_ppc:
    cmpwi 10, 0x1000
    blt .backtrace_done_ppc

    mr 3, 9
    lis 4, msg_frame_ppc@h
    ori 4, 4, msg_frame_ppc@l
    bl printf_ppc

    lwz 3, 4(10)      /* Get saved LR */
    mr 4, 3
    lis 5, msg_addr_ppc@h
    ori 5, 5, msg_addr_ppc@l
    bl printf_ppc

    lwz 10, 0(10)     /* Get back chain */
    cmpwi 10, 0
    beq .backtrace_done_ppc

    addi 9, 9, 1
    cmpwi 9, BACKTRACE_MAX_FRAMES
    blt .backtrace_loop_ppc

.backtrace_done_ppc:
    lis 3, msg_backtrace_end_ppc@h
    ori 3, 3, msg_backtrace_end_ppc@l
    bl display_string_ppc

    mtlr 0
    addi 1, 1, 64
    blr

    .data
msg_backtrace_ppc:
    .asciz "\r\nBacktrace:\r\n"
msg_frame_ppc:
    .asciz "  Frame %d: return to 0x%08X\r\n"
msg_addr_ppc:
    .asciz "0x%08X"
msg_backtrace_end_ppc:
    .asciz "\r\nEnd of backtrace\r\n"
