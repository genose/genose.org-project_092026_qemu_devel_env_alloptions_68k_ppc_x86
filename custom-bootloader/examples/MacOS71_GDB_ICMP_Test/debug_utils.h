/***************************************************************************
 * MacOS71_GDB_ICMP_Test - Debug Utilities Header
 * 
 * Debug utilities for the ICMP test application.
 * Provides a unified debugging interface that works with or without
 * the custom bootloader.
 * 
 * Architecture: Motorola 68k
 * 
 * Features:
 * - Bootloader detection
 * - Conditional debugging (with/without bootloader)
 * - Backtrace generation
 * - Error handling
 * - GDB integration
 ***************************************************************************/

#ifndef __DEBUG_UTILS_H__
#define __DEBUG_UTILS_H__

#include <stdint.h>
#include "../../include/bootloader_api.h"

/***************************************************************************
 * Debug Levels
 ***************************************************************************/

typedef enum {
    DEBUG_LEVEL_SILENT   = 0,    /* No debug output */
    DEBUG_LEVEL_ERROR    = 1,    /* Only errors */
    DEBUG_LEVEL_WARN     = 2,    /* Errors and warnings */
    DEBUG_LEVEL_INFO     = 3,    /* Informational messages */
    DEBUG_LEVEL_VERBOSE  = 4,    /* Verbose output */
    DEBUG_LEVEL_MAX      = 5
} DebugLevel;

/***************************************************************************
 * Debug Configuration
 ***************************************************************************/

/* Current debug level (can be changed at runtime) */
extern DebugLevel current_debug_level;

/* Application information */
#define APP_NAME         "MacOS71_GDB_ICMP_Test"
#define APP_VERSION      0x00010000
#define APP_ID           0x4D616349  /* "MacI" */

/***************************************************************************
 * Initialization
 ***************************************************************************/

/*
 * Initialize the debug system.
 * Should be called early in application startup.
 * 
 * Returns: 1 if bootloader is present, 0 otherwise
 */
int debug_init(void);

/*
 * Shutdown the debug system.
 */
void debug_shutdown(void);

/*
 * Check if bootloader is present.
 * Uses multiple methods for reliability.
 * 
 * Returns: 1 if present, 0 otherwise
 */
static inline int is_bootloader_present(void) {
    return check_bootloader_magic();
}

/*
 * Check if running in QEMU.
 * 
 * Returns: 1 if QEMU, 0 if real Mac
 */
static inline int is_qemu(void) {
    if (is_bootloader_present()) {
        return bootloader_check_env();
    }
    /* Fallback: Simple check without bootloader */
    volatile uint32_t *magic = (volatile uint32_t*)0x00002010;
    return (*magic == 0xDEADBEEF);
}

/***************************************************************************
 * Debug Output
 ***************************************************************************/

/*
 * Output a debug message.
 * Automatically adds prefix and respects debug level.
 * 
 * Parameters:
 *   level - Debug level of the message
 *   format - printf-style format string
 *   ... - Additional arguments
 */
void debug_printf(DebugLevel level, const char *format, ...);

/*
 * Output an error message.
 */
void debug_error(const char *format, ...);

/*
 * Output a warning message.
 */
void debug_warn(const char *format, ...);

/*
 * Output an informational message.
 */
void debug_info(const char *format, ...);

/*
 * Output a verbose message.
 */
void debug_verbose(const char *format, ...);

/*
 * Output a raw message (no prefix, always output).
 * Use for binary data or special formatting.
 */
void debug_raw(const char *data, int length);

/***************************************************************************
 * Debug Break
 ***************************************************************************/

/*
 * Trigger a debug break.
 * If bootloader is present, uses its GDB trigger.
 * Otherwise, uses standard Mac OS debugging.
 * 
 * This will pause execution and allow debugging.
 */
void debug_break(void);

/*
 * Trigger a debug break only if bootloader is present and we're in QEMU.
 * 
 * Returns: 1 if break was triggered, 0 otherwise
 */
int debug_break_if_possible(void);

/*
 * Trigger a debug break with a message.
 * 
 * Parameters:
 *   message - Message to display before breaking
 */
void debug_break_with_message(const char *message);

/***************************************************************************
 * Assertions
 ***************************************************************************/

/*
 * Assert that a condition is true.
 * If false, outputs error and breaks to debugger.
 */
#define DEBUG_ASSERT(condition) \
    do { \
        if (!(condition)) { \
            debug_error("ASSERT FAILED: %s at %s:%d", #condition, __FILE__, __LINE__); \
            debug_break(); \
        } \
    } while (0)

/*
 * Assert with custom message.
 */
#define DEBUG_ASSERT_MSG(condition, msg) \
    do { \
        if (!(condition)) { \
            debug_error("ASSERT FAILED: %s - %s at %s:%d", #condition, msg, __FILE__, __LINE__); \
            debug_break(); \
        } \
    } while (0)

/***************************************************************************
 * Backtrace
 ***************************************************************************/

/* Maximum backtrace depth */
#define MAX_BACKTRACE_DEPTH 20

/*
 * Generate a backtrace.
 * 
 * Parameters:
 *   buffer - Buffer to store addresses (must be MAX_BACKTRACE_DEPTH * sizeof(uint32_t))
 *   max_depth - Maximum number of frames to capture (up to MAX_BACKTRACE_DEPTH)
 * 
 * Returns: Number of frames captured
 */
int generate_backtrace(uint32_t *buffer, int max_depth);

/*
 * Print a backtrace to the debug console.
 * 
 * Parameters:
 *   buffer - Backtrace buffer from generate_backtrace()
 *   depth - Number of frames in the buffer
 */
void print_backtrace(uint32_t *buffer, int depth);

/*
 * Generate and print a backtrace.
 * 
 * Parameters:
 *   max_depth - Maximum depth to capture
 */
void debug_print_backtrace(int max_depth);

/***************************************************************************
 * Error Handling
 ***************************************************************************/

/*
 * Error codes.
 */
typedef enum {
    ERROR_SUCCESS           = 0,
    ERROR_GENERIC           = 1,
    ERROR_MEMORY           = 2,
    ERROR_TIMEOUT          = 3,
    ERROR_INVALID_ARGUMENT = 4,
    ERROR_NOT_IMPLEMENTED  = 5,
    ERROR_NOT_PRESENT      = 6,
    ERROR_QEMU_ONLY        = 7
} ErrorCode;

/*
 * Set the last error code.
 */
void debug_set_last_error(ErrorCode code);

/*
 * Get the last error code.
 */
ErrorCode debug_get_last_error(void);

/*
 * Get a string description of an error code.
 */
const char* debug_error_string(ErrorCode code);

/*
 * Handle an error.
 * Outputs error message and optionally breaks to debugger.
 * 
 * Parameters:
 *   code - Error code
 *   message - Additional error message
 *   do_break - Whether to break to debugger
 */
void debug_handle_error(ErrorCode code, const char *message, int do_break);

/***************************************************************************
 * Memory Debugging
 ***************************************************************************/

/*
 * Dump memory contents to debug console.
 * 
 * Parameters:
 *   address - Starting address
 *   size - Number of bytes to dump
 */
void debug_dump_memory(uint32_t address, uint32_t size);

/*
 * Dump memory with formatting.
 * 
 * Parameters:
 *   address - Starting address
 *   size - Number of bytes to dump
 *   bytes_per_line - Number of bytes per line (typically 16)
 */
void debug_dump_memory_formatted(uint32_t address, uint32_t size, int bytes_per_line);

/***************************************************************************
 * Register Debugging
 ***************************************************************************/

/*
 * Dump CPU registers to debug console.
 */
void debug_dump_registers(void);

/*
 * Dump a specific register.
 * 
 * Parameters:
 *   reg_name - Name of the register
 *   value - Register value
 */
void debug_dump_register(const char *reg_name, uint32_t value);

/***************************************************************************
 * Statistics
 ***************************************************************************/

/* Debug statistics */
typedef struct {
    uint32_t messages_output;
    uint32_t breaks_triggered;
    uint32_t backtraces_generated;
    uint32_t errors_handled;
    uint32_t memory_dumps;
} DebugStats;

/*
 * Get debug statistics.
 */
DebugStats debug_get_stats(void);

/*
 * Reset debug statistics.
 */
void debug_reset_stats(void);

/***************************************************************************
 * Utility Macros
 ***************************************************************************/

/*
 * Check if debug level is enabled.
 */
#define DEBUG_LEVEL_ENABLED(level) (current_debug_level >= (level))

/*
 * Output debug message if level is enabled.
 */
#define DEBUG_PRINT(level, ...) \
    do { \
        if (DEBUG_LEVEL_ENABLED(level)) { \
            debug_printf(level, __VA_ARGS__); \
        } \
    } while (0)

/***************************************************************************
 * Fallback Definitions (for when bootloader is not present)
 ***************************************************************************/

#ifndef BOOTLOADER_API_H
/* If bootloader API is not available, define fallbacks */

#define bootloader_check_presence() 0
#define bootloader_check_env() 0
#define bootloader_trigger_gdb() __asm__ volatile ("illegal")
#define bootloader_log_message(msg) 

#endif

#endif /* __DEBUG_UTILS_H__ */
