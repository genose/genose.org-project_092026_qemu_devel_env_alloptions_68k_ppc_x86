/***************************************************************************
 * Debug Helper Functions (C)
 * These functions are easier to implement in C
 ***************************************************************************/

#include "helpers.h"

/* Hex dump memory */
void hexdump(void* addr, size_t len) {
    uint8_t *p = (uint8_t *)addr;
    uint8_t *end = p + len;
    
    while (p < end) {
        /* Print address */
        printf("%08X: ", (uint32_t)p);
        
        /* Print 16 bytes in hex */
        for (int i = 0; i < 16; i++) {
            if (p + i < end) {
                printf("%02X ", p[i]);
            } else {
                printf("   ");
            }
            if (i == 7) putchar(' ');
        }
        
        /* Print ASCII */
        printf(" ");
        for (int i = 0; i < 16; i++) {
            if (p + i < end) {
                uint8_t c = p[i];
                putchar((c >= 32 && c < 127) ? c : '.');
            }
        }
        
        putchar('\n');
        p += 16;
    }
}

/* Dump registers (architecture-specific) */
void dump_registers(void) {
    /* This should be implemented in assembly for each architecture */
    /* For now, just print a message */
    printf("Registers:\n");
}

/* Panic function */
void panic(const char *msg) {
    printf("\r\nPANIC: %s\r\n", msg);
    dump_registers();
    backtrace();
    cpu_halt();
}
