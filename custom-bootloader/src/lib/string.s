/***************************************************************************
 * String Helper Functions (Assembly)
 * Optimized string operations for both 68k and PPC
 ***************************************************************************/

#include "config.h"

    .global memcpy
    .global memset
    .global strcpy
    .global strlen
    .global strcmp

    .text
    .align 4

/*** memcpy ***/
memcpy:
    movem.l %d0-%d2/%a0-%a1, -(sp)
    move.l 20(%sp), %a0    /* dest */
    move.l 24(%sp), %a1    /* src */
    move.l 28(%sp), %d0    /* n */
    beq memcpy_done
    
memcpy_loop:
    move.b (%a1)+, %d1
    move.b %d1, (%a0)+
    subq.l #1, %d0
    bne memcpy_loop
    
memcpy_done:
    move.l 20(%sp), %d0
    movem.l (%sp)+, %d0-%d2/%a0-%a1
    rts

/*** memset ***/
memset:
    movem.l %d0-%d2/%a0, -(sp)
    move.l 20(%sp), %a0    /* s */
    move.l 24(%sp), %d0    /* c */
    move.l 28(%sp), %d1    /* n */
    beq memset_done
    
memset_loop:
    move.b %d0, (%a0)+
    subq.l #1, %d1
    bne memset_loop
    
memset_done:
    move.l 20(%sp), %d0
    movem.l (%sp)+, %d0-%d2/%a0
    rts

/*** strcpy ***/
strcpy:
    movem.l %d0/%a0-%a1, -(sp)
    move.l 16(%sp), %a0    /* dest */
    move.l 20(%sp), %a1    /* src */
    
strcpy_loop:
    move.b (%a1)+, %d0
    move.b %d0, (%a0)+
    bne strcpy_loop
    
    move.l 16(%sp), %d0
    movem.l (%sp)+, %d0/%a0-%a1
    rts

/*** strlen ***/
strlen:
    movem.l %d0/%a0, -(sp)
    move.l 12(%sp), %a0    /* s */
    moveq #0, %d0
    
strlen_loop:
    tst.b (%a0)+
    beq strlen_done
    addq.l #1, %d0
    bra strlen_loop
    
strlen_done:
    movem.l (%sp)+, %d0/%a0
    rts

/*** strcmp ***/
strcmp:
    movem.l %d0-%d1/%a0-%a1, -(sp)
    move.l 20(%sp), %a0    /* s1 */
    move.l 24(%sp), %a1    /* s2 */
    
strcmp_loop:
    move.b (%a0)+, %d0
    move.b (%a1)+, %d1
    cmp.b %d0, %d1
    bne strcmp_done
    tst.b %d0
    bne strcmp_loop
    moveq #0, %d0
    bra strcmp_return
    
strcmp_done:
    ext.w %d0
    ext.w %d1
    sub.w %d1, %d0
    
strcmp_return:
    movem.l (%sp)+, %d0-%d1/%a0-%a1
    rts
