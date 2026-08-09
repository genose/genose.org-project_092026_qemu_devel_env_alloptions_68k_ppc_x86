/***************************************************************************
 * MacOS71_GDB_ICMP_Test - Debug Utilities Implementation
 * 
 * Implementation of debug utilities for the ICMP test application.
 * Provides a unified debugging interface that works with or without
 * the custom bootloader.
 * 
 * Architecture: Motorola 68k
 * 
 * Dependencies:
 *   - bootloader_api.h (from custom bootloader)
 *   - stdio.h (for fallback output)
 *   - stdarg.h (for variable arguments)
 ***************************************************************************/

#include "debug_utils.h"
#include "../../include/config.h"
#include "../../include/debug_shared.h"
#include <stdarg.h>
#include <string.h>

/***************************************************************************
 * Global Variables
 ***************************************************************************/

DebugLevel current_debug_level = DEBUG_LEVEL_INFO;
static ErrorCode last_error = ERROR_SUCCESS;
static DebugStats debug_stats = {0};
static int debug_initialized = 0;

/***************************************************************************
 * Initialization
 ***************************************************************************/

int debug_init(void) {
    if (debug_initialized) {
        return 1;  /* Already initialized */
    }
    
    debug_initialized = 1;
    last_error = ERROR_SUCCESS;
    debug_reset_stats();
    
    /* Initialize with bootloader if present */
    if (is_bootloader_present()) {
        /* Register application with bootloader */
        DebuggerContext *ctx = DEBUGGER_CTX;
        ctx->app_id = APP_ID;
        ctx->app_version = APP_VERSION;
        
        /* Copy app name */
        const char *app_name = APP_NAME;
        int i = 0;
        while (app_name[i] && i < 31) {
            ctx->app_name[i] = app_name[i];
            i++;
        }
        ctx->app_name[i] = '\0';
        
        /* Set debug level in bootloader */
        bootloader_set_debug(DEBUG_NORMAL);
        
        /* Install NMI handler */
        bootloader_install_nmi();
        
        /* Log initialization */
        bootloader_log_message("[DEBUG] Initialized with bootloader support\n");
        
        return 1;  /* Bootloader present */
    }
    
    /* Fallback: No bootloader */
    debug_stats.messages_output = 0;
    return 0;  /* No bootloader */
}

void debug_shutdown(void) {
    if (!debug_initialized) {
        return;
    }
    
    debug_initialized = 0;
}

/***************************************************************************
 * Debug Output
 ***************************************************************************/

/*
 * Internal function to output a formatted string.
 * Tries bootloader first, then falls back to standard output.
 */
static void debug_output(const char *str) {
    debug_stats.messages_output++;
    
    if (is_bootloader_present()) {
        bootloader_log_message(str);
    } else {
        /* Fallback: Use standard output */
        /* In a real application, this would use Mac OS Toolbox or similar */
        /* For QEMU with stdio, we can use console_putc */
        const char *p = str;
        while (*p) {
            /* Simple output - in real app, use proper console output */
            volatile char *uart = (volatile char*)0x50F0C000;
            *uart = *p++;
        }
    }
}

void debug_printf(DebugLevel level, const char *format, ...) {
    if (level > current_debug_level) {
        return;
    }
    
    va_list args;
    va_start(args, format);
    
    /* Format the message */
    char buffer[256];
    int len = vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    if (len < 0) {
        return;
    }
    
    /* Add level prefix */
    const char *prefix = "";
    switch (level) {
        case DEBUG_LEVEL_ERROR:   prefix = "[ERROR] "; break;
        case DEBUG_LEVEL_WARN:    prefix = "[WARN] "; break;
        case DEBUG_LEVEL_INFO:    prefix = "[INFO] "; break;
        case DEBUG_LEVEL_VERBOSE: prefix = "[VERBOSE] "; break;
        default: break;
    }
    
    /* Output prefix */
    debug_output(prefix);
    
    /* Output message */
    debug_output(buffer);
}

void debug_error(const char *format, ...) {
    va_list args;
    va_start(args, format);
    debug_printf(DEBUG_LEVEL_ERROR, format, args);
    va_end(args);
}

void debug_warn(const char *format, ...) {
    va_list args;
    va_start(args, format);
    debug_printf(DEBUG_LEVEL_WARN, format, args);
    va_end(args);
}

void debug_info(const char *format, ...) {
    va_list args;
    va_start(args, format);
    debug_printf(DEBUG_LEVEL_INFO, format, args);
    va_end(args);
}

void debug_verbose(const char *format, ...) {
    va_list args;
    va_start(args, format);
    debug_printf(DEBUG_LEVEL_VERBOSE, format, args);
    va_end(args);
}

void debug_raw(const char *data, int length) {
    if (is_bootloader_present()) {
        /* Use bootloader's memory dump */
        bootloader_dump_memory((uint32_t)data, length);
    } else {
        /* Fallback: Simple hex dump */
        char hex_digit(char c) {
            return (c < 10) ? ('0' + c) : ('A' + c - 10);
        }
        
        for (int i = 0; i < length; i++) {
            uint8_t byte = ((uint8_t*)data)[i];
            debug_output(" ");
            debug_output((char[]){hex_digit(byte >> 4), hex_digit(byte & 0xF), 0});
        }
    }
}

/***************************************************************************
 * Debug Break
 ***************************************************************************/

void debug_break(void) {
    if (is_bootloader_present()) {
        debug_stats.breaks_triggered++;
        
        /* Store backtrace in shared memory */
        DebuggerContext *ctx = DEBUGGER_CTX;
        ctx->backtrace_count = generate_backtrace(ctx->backtrace, MAX_BACKTRACE_DEPTH);
        
        /* Trigger GDB via bootloader */
        bootloader_trigger_gdb();
    } else {
        /* Fallback: Trigger standard Mac OS debugger */
        /* On Mac OS Classic, this would typically be MacsBug */
        debug_error("No bootloader - using standard debugger\n");
        __asm__ volatile ("illegal");  /* Trigger exception */
    }
}

int debug_break_if_possible(void) {
    if (is_bootloader_present() && is_qemu()) {
        debug_break();
        return 1;
    }
    return 0;
}

void debug_break_with_message(const char *message) {
    debug_error("%s\n", message);
    debug_break();
}

/***************************************************************************
 * Backtrace
 ***************************************************************************/

int generate_backtrace(uint32_t *buffer, int max_depth) {
    if (max_depth <= 0 || buffer == NULL) {
        return 0;
    }
    
    /* Use architecture-specific backtrace */
    #if defined(__m68k__)
    return generate_backtrace_68k(buffer, max_depth);
    #elif defined(__PPC__)
    return generate_backtrace_ppc(buffer, max_depth);
    #else
    /* Fallback: No backtrace */
    return 0;
    #endif
}

void print_backtrace(uint32_t *buffer, int depth) {
    debug_info("Backtrace (%d frames):\n", depth);
    
    for (int i = 0; i < depth; i++) {
        debug_info("  #%d: 0x%08X\n", i, buffer[i]);
    }
}

void debug_print_backtrace(int max_depth) {
    uint32_t buffer[MAX_BACKTRACE_DEPTH];
    int depth = generate_backtrace(buffer, max_depth);
    print_backtrace(buffer, depth);
}

/***************************************************************************
 * Error Handling
 ***************************************************************************/

void debug_set_last_error(ErrorCode code) {
    last_error = code;
}

ErrorCode debug_get_last_error(void) {
    return last_error;
}

const char* debug_error_string(ErrorCode code) {
    switch (code) {
        case ERROR_SUCCESS:          return "Success";
        case ERROR_GENERIC:          return "Generic error";
        case ERROR_MEMORY:           return "Memory error";
        case ERROR_TIMEOUT:          return "Timeout";
        case ERROR_INVALID_ARGUMENT: return "Invalid argument";
        case ERROR_NOT_IMPLEMENTED:  return "Not implemented";
        case ERROR_NOT_PRESENT:      return "Bootloader not present";
        case ERROR_QEMU_ONLY:        return "QEMU only feature";
        default:                     return "Unknown error";
    }
}

void debug_handle_error(ErrorCode code, const char *message, int do_break) {
    debug_set_last_error(code);
    debug_stats.errors_handled++;
    
    if (message) {
        debug_error("Error %d (%s): %s\n", code, debug_error_string(code), message);
    } else {
        debug_error("Error %d: %s\n", code, debug_error_string(code));
    }
    
    if (do_break) {
        debug_break();
    }
}

/***************************************************************************
 * Memory Debugging
 ***************************************************************************/

void debug_dump_memory(uint32_t address, uint32_t size) {
    debug_dump_memory_formatted(address, size, 16);
}

void debug_dump_memory_formatted(uint32_t address, uint32_t size, int bytes_per_line) {
    debug_stats.memory_dumps++;
    
    if (is_bootloader_present()) {
        /* Use bootloader's memory dump */
        bootloader_dump_memory(address, size);
    } else {
        /* Fallback: Manual dump */
        uint8_t *ptr = (uint8_t*)address;
        
        for (uint32_t offset = 0; offset < size; offset += bytes_per_line) {
            char line[80];
            char *p = line;
            
            /* Address */
            p += sprintf(p, "%08X: ", address + offset);
            
            /* Hex values */
            for (int i = 0; i < bytes_per_line; i++) {
                if (offset + i < size) {
                    p += sprintf(p, "%02X ", ptr[offset + i]);
                } else {
                    p += sprintf(p, "   ");
                }
                if (i == bytes_per_line / 2 - 1) {
                    *p++ = ' ';
                }
            }
            
            /* ASCII representation */
            *p++ = ' ';
            *p++ = ' ';
            for (int i = 0; i < bytes_per_line && offset + i < size; i++) {
                uint8_t byte = ptr[offset + i];
                *p++ = (byte >= 32 && byte < 127) ? byte : '.';
            }
            *p = '\0';
            
            debug_output(line);
        }
    }
}

/***************************************************************************
 * Register Debugging
 ***************************************************************************/

void debug_dump_registers(void) {
    if (is_bootloader_present()) {
        /* Use bootloader's register dump */
        /* This would be implemented via shared memory or TRAP call */
        DebuggerContext *ctx = DEBUGGER_CTX;
        
        debug_info("Registers:\n");
        for (int i = 0; i < 8; i++) {
            debug_info("  D%d: 0x%08X\n", i, ctx->registers_d[i]);
        }
        for (int i = 0; i < 7; i++) {
            debug_info("  A%d: 0x%08X\n", i, ctx->registers_a[i]);
        }
        debug_info("  USP: 0x%08X\n", ctx->usp);
        debug_info("  PC:  0x%08X\n", ctx->pc);
        debug_info("  SR:  0x%04X\n", ctx->sr);
    } else {
        /* Fallback: Read registers directly */
        uint32_t d0, d1, d2, d3, d4, d5, d6, d7;
        uint32_t a0, a1, a2, a3, a4, a5, a6;
        uint32_t pc, usp;
        uint16_t sr;
        
        __asm__ volatile (
            "movem.l %%d0-%%d7, %0\n\t"
            "movem.l %%a0-%%a6, %1\n\t"
            : "=m"(d0), "=m"(a0)
            :
            : "memory"
        );
        
        __asm__ volatile (
            "move.l %%a7, %0\n\t"
            "move.l %%pc, %1\n\t"
            "move.w %%sr, %2"
            : "=r"(usp), "=r"(pc), "=r"(sr)
            :
            : "memory"
        );
        
        debug_info("Registers:\n");
        debug_info("  D0: 0x%08X  D1: 0x%08X  D2: 0x%08X  D3: 0x%08X\n", d0, d1, d2, d3);
        debug_info("  D4: 0x%08X  D5: 0x%08X  D6: 0x%08X  D7: 0x%08X\n", d4, d5, d6, d7);
        debug_info("  A0: 0x%08X  A1: 0x%08X  A2: 0x%08X  A3: 0x%08X\n", a0, a1, a2, a3);
        debug_info("  A4: 0x%08X  A5: 0x%08X  A6: 0x%08X\n", a4, a5, a6);
        debug_info("  USP: 0x%08X  PC: 0x%08X  SR: 0x%04X\n", usp, pc, sr);
    }
}

void debug_dump_register(const char *reg_name, uint32_t value) {
    debug_info("%s: 0x%08X\n", reg_name, value);
}

/***************************************************************************
 * Statistics
 ***************************************************************************/

DebugStats debug_get_stats(void) {
    return debug_stats;
}

void debug_reset_stats(void) {
    debug_stats.messages_output = 0;
    debug_stats.breaks_triggered = 0;
    debug_stats.backtraces_generated = 0;
    debug_stats.errors_handled = 0;
    debug_stats.memory_dumps = 0;
}

/***************************************************************************
 * Helper Functions
 ***************************************************************************/

/*
 * Simple vsnprintf implementation for systems without it.
 * Note: This is a simplified version that may not handle all cases.
 */
int vsnprintf(char *buf, size_t size, const char *fmt, va_list args) {
    /* In a real application, implement or use existing vsnprintf */
    /* For now, we'll use a simple approach */
    
    int count = 0;
    char *p = buf;
    char *end = buf + size - 1;  /* Leave room for null terminator */
    
    while (*fmt && p < end) {
        if (*fmt == '%') {
            fmt++;
            switch (*fmt) {
                case 'd': {
                    int val = va_arg(args, int);
                    char temp[16];
                    int i = sizeof(temp) - 1;
                    temp[i] = '\0';
                    if (val == 0) {
                        temp[--i] = '0';
                    } else {
                        int negative = (val < 0);
                        if (negative) val = -val;
                        while (val > 0 && i > 0) {
                            temp[--i] = '0' + (val % 10);
                            val /= 10;
                        }
                        if (negative && i > 0) {
                            temp[--i] = '-';
                        }
                    }
                    while (temp[i] && p < end) {
                        *p++ = temp[i++];
                        count++;
                    }
                    break;
                }
                case 'x': {
                    uint32_t val = va_arg(args, uint32_t);
                    char temp[16];
                    int i = sizeof(temp) - 1;
                    temp[i] = '\0';
                    if (val == 0) {
                        temp[--i] = '0';
                    } else {
                        while (val > 0 && i > 0) {
                            int digit = val & 0xF;
                            temp[--i] = (digit < 10) ? ('0' + digit) : ('A' + digit - 10);
                            val >>= 4;
                        }
                    }
                    while (temp[i] && p < end) {
                        *p++ = temp[i++];
                        count++;
                    }
                    break;
                }
                case 's': {
                    char *str = va_arg(args, char*);
                    while (*str && p < end) {
                        *p++ = *str++;
                        count++;
                    }
                    break;
                }
                case '%': {
                    *p++ = '%';
                    count++;
                    break;
                }
                default: {
                    *p++ = *fmt;
                    count++;
                    break;
                }
            }
            fmt++;
        } else {
            *p++ = *fmt++;
            count++;
        }
    }
    
    *p = '\0';
    return count;
}

/*
 * Simple snprintf implementation.
 */
int snprintf(char *buf, size_t size, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int result = vsnprintf(buf, size, fmt, args);
    va_end(args);
    return result;
}

/*
 * Simple strlen implementation.
 */
size_t strlen(const char *s) {
    const char *p = s;
    while (*p) p++;
    return p - s;
}

/*
 * Simple memcpy implementation.
 */
void *memcpy(void *dest, const void *src, size_t n) {
    char *d = (char*)dest;
    const char *s = (const char*)src;
    for (size_t i = 0; i < n; i++) {
        d[i] = s[i];
    }
    return dest;
}

/*
 * Simple memset implementation.
 */
void *memset(void *s, int c, size_t n) {
    char *p = (char*)s;
    for (size_t i = 0; i < n; i++) {
        p[i] = (char)c;
    }
    return s;
}
