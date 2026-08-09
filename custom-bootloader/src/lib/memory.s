/***************************************************************************
 * Memory Helper Functions (Assembly)
 * Optimized memory operations
 ***************************************************************************/

#include "config.h"

    .global memmove
    .global memcmp
    .global memchr

    .text
    .align 4

/*** memmove ***/
memmove:
    movem.l %d0-%d2/%a0-%a1, -(sp)
    move.l 20(%sp), %a0    /* dest */
    move.l 24(%sp), %a1    /* src */
    move.l 28(%sp), %d0    /* n */
    beq memmove_done
    
    /* Check for overlap */
    cmp.l %a0, %a1
    beq memmove_same
    blt memmove_forward
    
    /* Overlap: copy backwards */
    add.l %d0, %a0
    add.l %d0, %a1
    subq.l #1, %a0
    subq.l #1, %a1
    
memmove_backward:
    move.b (%a1), %d1
    move.b %d1, (%a0)
    subq.l #1, %a0
    subq.l #1, %a1
    subq.l #1, %d0
    bne memmove_backward
    bra memmove_done
    
memmove_forward:
    /* No overlap: copy forwards */
    bra memcpy
    
memmove_same:
    /* Same address: do nothing */
    
memmove_done:
    move.l 20(%sp), %d0
    movem.l (%sp)+, %d0-%d2/%a0-%a1
    rts

/*** memcmp ***/
memcmp:
    movem.l %d0-%d2/%a0-%a1, -(sp)
    move.l 20(%sp), %a0    /* s1 */
    move.l 24(%sp), %a1    /* s2 */
    move.l 28(%sp), %d0    /* n */
    beq memcmp_equal
    
memcmp_loop:
    move.b (%a0)+, %d1
    move.b (%a1)+, %d2
    cmp.b %d1, %d2
    bne memcmp_done
    subq.l #1, %d0
    bne memcmp_loop
    
memcmp_equal:
    moveq #0, %d0
    bra memcmp_return
    
memcmp_done:
    ext.w %d1
    ext.w %d2
    sub.w %d2, %d1
    move.l %d1, %d0
    
memcmp_return:
    movem.l (%sp)+, %d0-%d2/%a0-%a1
    rts

/*** memchr ***/
memchr:
    movem.l %d0-%d2/%a0-%a1, -(sp)
    move.l 20(%sp), %a0    /* s */
    move.l 24(%sp), %d0    /* c */
    move.l 28(%sp), %d1    /* n */
    andi.b #0xFF, %d0
    beq memchr_not_found
    
memchr_loop:
    move.b (%a0), %d2
    cmp.b %d0, %d2
    beq memchr_found
    addq.l #1, %a0
    subq.l #1, %d1
    bne memchr_loop
    
memchr_not_found:
    moveq #0, %a0
    bra memchr_return
    
memchr_found:
    
memchr_return:
    movem.l (%sp)+, %d0-%d2/%a0-%a1
    rts
