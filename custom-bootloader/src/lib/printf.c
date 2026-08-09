/***************************************************************************
 * printf Implementation
 * Minimal printf for the bootloader
 ***************************************************************************/

#include "helpers.h"

#define MAX_FMT_LEN 64

static void putchar_serial(char c) {
    /* In real implementation, output to serial port */
}

static int vsnprintf(char *buf, size_t size, const char *fmt, void *ap) {
    return 0; /* Not implemented yet */
}

void printf(const char *format, ...) {
    char buffer[256];
    void *ap;
    int len;
    
    /* For now, just display string without formatting */
    /* A full printf implementation would go here */
    display_string((char *)format);
    return;
    
    /* Full implementation would be: */
    /* ap = __builtin_va_arg_pack(); */
    /* len = vsnprintf(buffer, sizeof(buffer), format, ap); */
    /* display_string(buffer); */
}

void sprintf(char *str, const char *format, ...) {
    /* For now, just copy format string */
    /* A full implementation would format the string */
    while (*format) {
        *str++ = *format++;
    }
    *str = '\0';
}

void vsprintf(char *str, const char *format, void *ap) {
    /* Not implemented */
}

/* Simple puthex for debugging */
void puthex(uint32_t value, int width) {
    for (int i = width - 1; i >= 0; i--) {
        uint32_t nibble = (value >> (i * 4)) & 0xF;
        putchar((nibble < 10) ? ('0' + nibble) : ('A' + nibble - 10));
    }
}
