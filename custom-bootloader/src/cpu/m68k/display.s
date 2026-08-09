/***************************************************************************
 * Custom Bootloader - 68k Display Functions
 * 
 * This file contains display and output functions specific to the 68k
 * architecture. It provides console output capabilities for the bootloader.
 * 
 * Features:
 * - Character output to serial console
 * - String output
 * - Hexadecimal dump
 * - Register dump in 68k format
 * 
 * Note: The actual output mechanism depends on the platform:
 * - QEMU: Use debug console or serial port
 * - Shoebill: Use Mac OS-style console
 * - Real hardware: Use hardware-specific output
 ***************************************************************************/

#include "config.h"

    .global init_display_68k
    .global display_string_68k
    .global display_char_68k
    .global display_hex_68k
    .global display_hex_byte_68k
    .global display_hex_word_68k
    .global display_hex_long_68k
    .global display_registers_68k
    .global display_newline_68k
    .global hexdump_68k

    .text
    .align 4

/***************************************************************************
 * Initialize Display (68k)
 * 
 * Sets up the display subsystem for 68k.
 * This may involve initializing serial ports, setting up memory-mapped I/O,
 * or configuring the console.
 * 
 * Clobbers: D0-D7, A0-A6
 ***************************************************************************/

init_display_68k:
    /* For now, just return */
    /* In a real implementation, we would: */
    /* 1. Detect the platform (QEMU, Shoebill, real hardware) */
    /* 2. Initialize the appropriate output mechanism */
    /* 3. Set up baud rate for serial */
    /* 4. Configure display memory if available */
    
    rts

/***************************************************************************
 * Display Character (68k)
 * 
 * Outputs a single character to the console.
 * 
 * Input: D0 = character to display
 * Clobbers: D0, A0
 ***************************************************************************/

display_char_68k:
    /* Save registers */
    movem.l %d0/%a0, -(sp)
    move.l 12(%sp), %d0     /* Get character from stack */
    
    /* For now, just call console_putc */
    move.l %d0, -(sp)
    jsr console_putc
    addq.l #4, %sp
    
    /* In a real implementation: */
    /* - Check if we're on QEMU (use debug output) */
    /* - Check if we're on Shoebill (use Mac OS console) */
    /* - Check if serial is available (output to serial port) */
    
    movem.l (%sp)+, %d0/%a0
    rts

/***************************************************************************
 * Display String (68k)
 * 
 * Outputs a null-terminated string to the console.
 * 
 * Input: A0 = pointer to string
 * Clobbers: D0, A0
 ***************************************************************************/

display_string_68k:
    movem.l %d0/%a0, -(sp)
    move.l 8(%sp), %a0       /* Get string pointer from stack */
    
.display_string_68k_loop:
    move.b (%a0)+, %d0       /* Get next character */
    beq display_string_68k_done  /* If null, we're done */
    
    /* Output character */
    move.l %d0, -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    
    bra display_string_68k_loop
    
.display_string_68k_done:
    movem.l (%sp)+, %d0/%a0
    rts

/***************************************************************************
 * Display Newline (68k)
 * 
 * Outputs a newline (CR+LF) to the console.
 * 
 * Clobbers: D0
 ***************************************************************************/

display_newline_68k:
    move.l #'\r', -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    
    move.l #'\n', -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    
    rts

/***************************************************************************
 * Display Hexadecimal Byte (68k)
 * 
 * Displays a byte value in hexadecimal format (2 digits).
 * 
 * Input: D0 = byte value
 * Clobbers: D0, D1
 ***************************************************************************/

display_hex_byte_68k:
    movem.l %d0/%d1, -(sp)
    move.l 12(%sp), %d0     /* Get value from stack */
    
    /* Extract high nibble */
    move.l %d0, %d1
    lsr.l #4, %d1
    andi.l #0xF, %d1
    
    /* Convert to ASCII */
    cmp.b #9, %d1
    ble display_hex_byte_high
    addi.b #7, %d1           /* A-F */
    
.display_hex_byte_high:
    addi.b #'0', %d1
    move.l %d1, -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    
    /* Extract low nibble */
    andi.l #0xF, %d0
    
    /* Convert to ASCII */
    cmp.b #9, %d0
    ble display_hex_byte_low
    addi.b #7, %d0           /* A-F */
    
.display_hex_byte_low:
    addi.b #'0', %d0
    move.l %d0, -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    
    movem.l (%sp)+, %d0/%d1
    rts

/***************************************************************************
 * Display Hexadecimal Word (68k)
 * 
 * Displays a word value in hexadecimal format (4 digits).
 * 
 * Input: D0 = word value
 * Clobbers: D0, D1, D2
 ***************************************************************************/

display_hex_word_68k:
    movem.l %d0/%d1/%d2, -(sp)
    move.l 16(%sp), %d2     /* Get value from stack */
    
    /* Display high byte */
    move.l %d2, %d0
    lsr.l #8, %d0
    move.l %d0, -(sp)
    jsr display_hex_byte_68k
    addq.l #4, %sp
    
    /* Display low byte */
    move.l %d2, -(sp)
    jsr display_hex_byte_68k
    addq.l #4, %sp
    
    movem.l (%sp)+, %d0/%d1/%d2
    rts

/***************************************************************************
 * Display Hexadecimal Long (68k)
 * 
 * Displays a long word value in hexadecimal format (8 digits).
 * 
 * Input: D0 = long value
 * Clobbers: D0, D1, D2
 ***************************************************************************/

display_hex_long_68k:
    movem.l %d0/%d1/%d2, -(sp)
    move.l 16(%sp), %d2     /* Get value from stack */
    
    /* Display high word */
    move.l %d2, %d0
    swap %d0
    move.l %d0, -(sp)
    jsr display_hex_word_68k
    addq.l #4, %sp
    
    /* Display low word */
    move.l %d2, -(sp)
    jsr display_hex_word_68k
    addq.l #4, %sp
    
    movem.l (%sp)+, %d0/%d1/%d2
    rts

/***************************************************************************
 * Display Hexadecimal (68k)
 * 
 * Displays a value in hexadecimal format with optional width.
 * 
 * Input: D0 = value, D1 = width (number of digits)
 * Clobbers: D0, D1, D2, D3
 ***************************************************************************/

display_hex_68k:
    movem.l %d0/%d1/%d2/%d3, -(sp)
    move.l 20(%sp), %d3     /* Get width from stack */
    move.l 16(%sp), %d2     /* Get value from stack */
    
    /* Check width */
    cmp.l #8, %d3
    bge display_hex_long
    cmp.l #4, %d3
    bge display_hex_word
    
    /* Default to byte */
    move.l %d2, -(sp)
    jsr display_hex_byte_68k
    addq.l #4, %sp
    bra display_hex_done
    
.display_hex_long:
    move.l %d2, -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    bra display_hex_done
    
.display_hex_word:
    move.l %d2, -(sp)
    jsr display_hex_word_68k
    addq.l #4, %sp
    
.display_hex_done:
    movem.l (%sp)+, %d0/%d1/%d2/%d3
    rts

/***************************************************************************
 * Display Registers (68k)
 * 
 * Dumps all 68k CPU registers in a readable format.
 * This is useful for debugging exceptions and crashes.
 * 
 * Registers displayed:
 * - Data Registers (D0-D7)
 * - Address Registers (A0-A7)
 * - User Stack Pointer (USP)
 * - Supervisor Stack Pointer (SSP)
 * - Status Register (SR)
 * - Program Counter (PC)
 * 
 * Clobbers: All
 ***************************************************************************/

display_registers_68k:
    movem.l %d0-%d7/%a0-%a7, -(sp)
    
    /* Display header */
    pea msg_registers(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* Display Data Registers */
    pea msg_d_registers(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* D0-D7 are on the stack at this point */
    /* Stack layout: D0-D7 (32 bytes), A0-A7 (32 bytes) */
    
    /* Display D0 */
    pea msg_d0(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 60(%sp), -(sp)     /* D0 is at offset 60 (after A0-A7) */
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display D1 */
    pea msg_d1(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 56(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display D2 */
    pea msg_d2(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 52(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display D3 */
    pea msg_d3(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 48(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display D4 */
    pea msg_d4(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 44(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display D5 */
    pea msg_d5(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 40(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display D6 */
    pea msg_d6(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 36(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display D7 */
    pea msg_d7(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 32(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display Address Registers */
    pea msg_a_registers(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* Display A0 */
    pea msg_a0(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 28(%sp), -(sp)     /* A0 */
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display A1 */
    pea msg_a1(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 24(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display A2 */
    pea msg_a2(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 20(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display A3 */
    pea msg_a3(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 16(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display A4 */
    pea msg_a4(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 12(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display A5 */
    pea msg_a5(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 8(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display A6 */
    pea msg_a6(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 4(%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display A7 */
    pea msg_a7(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l (%sp), -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display USP */
    pea msg_usp(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l %usp, -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display SR */
    pea msg_sr(%pc)
    jsr display_string
    addq.l #4, %sp
    move.w %sr, -(sp)
    jsr display_hex_word_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Display PC */
    pea msg_pc(%pc)
    jsr display_string
    addq.l #4, %sp
    move.l 4(%sp), %a0        /* Return address is on stack */
    move.l %a0, -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    jsr display_newline_68k
    
    /* Restore registers */
    movem.l (%sp)+, %d0-%d7/%a0-%a7
    
    rts

/***************************************************************************
 * Hex Dump (68k)
 * 
 * Displays a block of memory in hexadecimal and ASCII format.
 * 
 * Input: A0 = address, D0 = length
 * Clobbers: D0-D7, A0-A6
 ***************************************************************************/

hexdump_68k:
    movem.l %d0-%d7/%a0-%a6, -(sp)
    move.l 44(%sp), %a0      /* Address */
    move.l 40(%sp), %d7      /* Length */
    
    /* Display header */
    pea msg_hexdump(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* Calculate number of lines */
    move.l %d7, %d6
    add.l #15, %d6           /* Round up */
    lsr.l #4, %d6            /* Divide by 16 */
    
    /* Loop through lines */
    moveq #0, %d5            /* Line counter */
    
.hexdump_loop:
    /* Display address */
    move.l %a0, -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    
    pea msg_hexdump_colon(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* Display 16 bytes */
    moveq #0, %d4            /* Byte counter */
    
.hexdump_line_loop:
    /* Load byte */
    move.b (%a0), %d0
    
    /* Display as hex */
    move.l %d0, -(sp)
    jsr display_hex_byte_68k
    addq.l #4, %sp
    
    /* Space between bytes */
    move.l #' ', -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    
    /* Move to next byte */
    addq.l #1, %a0
    addq.l #1, %d4
    
    /* Check if we've displayed 8 bytes (add extra space) */
    cmp.l #8, %d4
    bne hexdump_no_extra_space
    
    move.l #' ', -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    
.hexdump_no_extra_space:
    /* Check if we've displayed 16 bytes */
    cmp.l #16, %d4
    blt hexdump_line_loop
    
    /* Display ASCII representation */
    pea msg_hexdump_ascii(%pc)
    jsr display_string
    addq.l #4, %sp
    
    /* Go back to start of line */
    sub.l #16, %a0
    
    moveq #0, %d4
    
.hexdump_ascii_loop:
    move.b (%a0)+, %d0
    
    /* Check if printable */
    cmp.b #32, %d0
    blt hexdump_dot
    cmp.b #127, %d0
    bge hexdump_dot
    
    /* Display character */
    move.l %d0, -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    bra hexdump_ascii_next
    
.hexdump_dot:
    move.l #'.', -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    
.hexdump_ascii_next:
    addq.l #1, %d4
    cmp.l #16, %d4
    blt hexdump_ascii_loop
    
    /* Newline */
    jsr display_newline_68k
    
    /* Check if we've displayed all lines */
    addq.l #1, %d5
    cmp.l %d6, %d5
    bge hexdump_done
    
    /* Check if we've displayed all bytes */
    move.l %d7, %d0
    sub.l %d5, %d0
    cmp.l #16, %d0
    bgt hexdump_loop
    
    /* Display remaining bytes */
    move.l %d0, %d4            /* Remaining bytes */
    
    /* Display address */
    move.l %a0, -(sp)
    jsr display_hex_long_68k
    addq.l #4, %sp
    
    pea msg_hexdump_colon(%pc)
    jsr display_string
    addq.l #4, %sp
    
    moveq #0, %d0
    
.hexdump_remaining_loop:
    /* Load byte */
    move.b (%a0)+, %d1
    
    /* Display as hex */
    move.l %d1, -(sp)
    jsr display_hex_byte_68k
    addq.l #4, %sp
    
    /* Space */
    move.l #' ', -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    
    addq.l #1, %d0
    cmp.l %d4, %d0
    blt hexdump_remaining_loop
    
    /* Pad with spaces */
    move.l %d4, %d1
    lsl.l #1, %d1            /* *2 for hex chars */
    add.l %d4, %d1          /* + spaces */
    sub.l #16, %d1          /* - 16 (normal line) */
    neg.l %d1
    
.hexdump_pad_loop:
    move.l #' ', -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    dbra %d1, hexdump_pad_loop
    
    /* Display ASCII representation */
    pea msg_hexdump_ascii(%pc)
    jsr display_string
    addq.l #4, %sp
    
    sub.l %d4, %a0
    
    moveq #0, %d0
    
.hexdump_remaining_ascii_loop:
    move.b (%a0)+, %d1
    
    /* Check if printable */
    cmp.b #32, %d1
    blt hexdump_remaining_dot
    cmp.b #127, %d1
    bge hexdump_remaining_dot
    
    /* Display character */
    move.l %d1, -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    bra hexdump_remaining_ascii_next
    
.hexdump_remaining_dot:
    move.l #'.', -(sp)
    jsr display_char_68k
    addq.l #4, %sp
    
.hexdump_remaining_ascii_next:
    addq.l #1, %d0
    cmp.l %d4, %d0
    blt hexdump_remaining_ascii_loop
    
    /* Newline */
    jsr display_newline_68k
    
.hexdump_done:
    movem.l (%sp)+, %d0-%d7/%a0-%a6
    rts

/***************************************************************************
 * Data Section
 * 
 * Contains messages for register dump and hex dump.
 ***************************************************************************/

    .data
    .align 4

msg_registers:
    .asciz "\r\nRegisters:\r\n"

msg_d_registers:
    .asciz "\r\nData Registers:\r\n"

msg_a_registers:
    .asciz "\r\nAddress Registers:\r\n"

msg_d0:
    .asciz "D0: 0x"

msg_d1:
    .asciz "D1: 0x"

msg_d2:
    .asciz "D2: 0x"

msg_d3:
    .asciz "D3: 0x"

msg_d4:
    .asciz "D4: 0x"

msg_d5:
    .asciz "D5: 0x"

msg_d6:
    .asciz "D6: 0x"

msg_d7:
    .asciz "D7: 0x"

msg_a0:
    .asciz "A0: 0x"

msg_a1:
    .asciz "A1: 0x"

msg_a2:
    .asciz "A2: 0x"

msg_a3:
    .asciz "A3: 0x"

msg_a4:
    .asciz "A4: 0x"

msg_a5:
    .asciz "A5: 0x"

msg_a6:
    .asciz "A6: 0x"

msg_a7:
    .asciz "A7: 0x"

msg_usp:
    .asciz "USP: 0x"

msg_sr:
    .asciz "SR:  0x"

msg_pc:
    .asciz "PC:  0x"

msg_hexdump:
    .asciz "\r\nHex Dump:\r\n"

msg_hexdump_colon:
    .asciz ": "

msg_hexdump_ascii:
    .asciz "  "

/***************************************************************************
 * End of File
 ***************************************************************************/
