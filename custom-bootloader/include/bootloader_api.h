/***************************************************************************
 * Custom Bootloader - Developer API Header
 * 
 * This header provides the API for applications to interact with the
 * custom bootloader. It includes:
 * - TRAP #15 function definitions
 * - Bootloader detection
 * - Backtrace generation
 * - Debug utilities
 * 
 * Architecture: 68k and PPC
 * 
 * Usage:
 *   #include "bootloader_api.h"
 *   
 *   if (bootloader_check_presence()) {
 *       bootloader_trigger_gdb();
 *   }
 * 
 *   // Or with error handling
 *   if (bootloader_call(BOOTLOADER_CHECK_ENV, 0, 0, &result) == 0) {
 *       // Success
 *   }
 ***************************************************************************/

#ifndef __BOOTLOADER_API_H__
#define __BOOTLOADER_API_H__

#include <stdint.h>
#include "config.h"

/***************************************************************************
 * Magic Numbers and Constants
 ***************************************************************************/

/* API Magic Number for presence detection */
#ifndef API_MAGIC_NUMBER
#define API_MAGIC_NUMBER        0xDEADBEEF
#endif

#ifndef API_MAGIC_NUMBER_ADDRESS
#define API_MAGIC_NUMBER_ADDRESS 0x00002010
#endif

/*** TRAP #15 Function IDs ***/
typedef enum {
    BOOTLOADER_TRIGGER_GDB       = 0,    /* Force GDB break */
    BOOTLOADER_CHECK_ENV         = 1,    /* Detect QEMU (returns 1) or Mac (returns 0) */
    BOOTLOADER_GET_VERSION       = 2,    /* Get bootloader version */
    BOOTLOADER_SET_DEBUG         = 3,    /* Set debug verbosity level */
    BOOTLOADER_DUMP_MEMORY       = 4,    /* Dump memory region */
    BOOTLOADER_LOG_MESSAGE       = 5,    /* Log message to debug console */
    BOOTLOADER_GET_CPU_TYPE      = 6,    /* Get detected CPU type */
    BOOTLOADER_GET_API_MAGIC     = 7,    /* Verify API presence (returns 0xDEADBEEF) */
    BOOTLOADER_INSTALL_NMI       = 8,    /* Install NMI handler */
    BOOTLOADER_GET_BACKTRACE     = 9,    /* Generate backtrace */
    BOOTLOADER_CHECK_PRESENCE   = 10,   /* Check if custom bootloader is present */
    BOOTLOADER_GET_BOOTINFO      = 11,   /* Get BootInfo structure pointer */
    BOOTLOADER_SET_BREAKPOINT    = 12,   /* Set breakpoint at address */
    BOOTLOADER_CLEAR_BREAKPOINT  = 13,   /* Clear breakpoint */
    BOOTLOADER_STEP_EXECUTION    = 14,   /* Single-step execution */
    BOOTLOADER_CONTINUE          = 15    /* Continue execution after break */
} BootloaderFunctionID;

/*** API Error Codes ***/
typedef enum {
    API_ERROR_SUCCESS           = 0,
    API_ERROR_INVALID_FUNCTION  = 1,
    API_ERROR_INVALID_PARAMETER = 2,
    API_ERROR_NOT_IMPLEMENTED   = 3,
    API_ERROR_NOT_PRESENT       = 4,
    API_ERROR_ENVIRONMENT       = 5
} BootloaderErrorCode;

/*** Debug Verbosity Levels ***/
typedef enum {
    DEBUG_SILENT   = 0,
    DEBUG_NORMAL   = 1,
    DEBUG_VERBOSE  = 2,
    DEBUG_MAX      = 3
} DebugVerbosityLevel;

/***************************************************************************
 * Shared Memory Layout (DEBUGGER_SHARED_SPACE at 0x00F00000)
 ***************************************************************************/

#define DEBUGGER_SHARED_BASE    0x00F00000

/* Debugger Context Structure (offset 0x0000) */
typedef struct {
    /* CPU Registers */
    uint32_t registers_d[8];      /* D0-D7 */
    uint32_t registers_a[7];      /* A0-A6 */
    uint32_t usp;                 /* User Stack Pointer (A7) */
    uint32_t pc;                  /* Program Counter */
    uint16_t sr;                  /* Status Register */
    uint16_t padding_sr;          /* Padding */
    uint32_t mmu_root;            /* MMU root pointer */
    
    /* Environment */
    uint32_t is_qemu;             /* 1 = QEMU, 0 = real Mac */
    uint32_t resume_flag;         /* 1 = resume execution */
    
    /* Backtrace Buffer (room for 20 addresses) */
    uint32_t backtrace[20];
    uint32_t backtrace_count;     /* Number of frames in backtrace */
    
    /* Last Error */
    uint32_t last_error_code;     /* Last error code */
    uint32_t last_error_pc;       /* PC where error occurred */
    
    /* Application Data */
    uint32_t app_id;              /* Application ID */
    uint32_t app_version;         /* Application version */
    char     app_name[32];       /* Application name */
} DebuggerContext;

/* Access the shared context */
#define DEBUGGER_CTX ((volatile DebuggerContext*)DEBUGGER_SHARED_BASE)

/***************************************************************************
 * BootInfo Structure (from config.h)
 * This is stored at a fixed address by the bootloader
 ***************************************************************************/

#ifndef BOOTINFO_PTR_ADDRESS
#define BOOTINFO_PTR_ADDRESS 0x00002000
#endif

/* Forward declaration */
typedef struct BootInfo BootInfo;

/***************************************************************************
 * Inline Assembly Macros for TRAP #15 Calls
 ***************************************************************************/

/*
 * Call a bootloader API function via TRAP #15
 * 
 * Parameters:
 *   function_id - The API function ID (0-15)
 *   param_a0    - Value for A0 register
 *   param_d1    - Value for D1 register
 *   result     - Pointer to store result (D0)
 * 
 * Returns: Error code (D1)
 */
static inline int bootloader_call_raw(
    BootloaderFunctionID function_id,
    uint32_t param_a0,
    uint32_t param_d1,
    uint32_t *result
) {
    register uint32_t func_id __asm__("d0") = (uint32_t)function_id;
    register uint32_t a0_val __asm__("a0") = param_a0;
    register uint32_t d1_val __asm__("d1") = param_d1;
    register uint32_t ret_d0 __asm__("d0");
    register uint32_t ret_d1 __asm__("d1");
    
    __asm__ volatile (
        "trap #15\n\t"
        : "=r"(ret_d0), "=r"(ret_d1)
        : "r"(func_id), "r"(a0_val), "r"(d1_val)
        : "d2", "d3", "d4", "d5", "d6", "d7",
          "a1", "a2", "a3", "a4", "a5", "a6",
          "cc", "memory"
    );
    
    if (result) {
        *result = ret_d0;
    }
    return (int)ret_d1;
}

/***************************************************************************
 * Simple API Function Wrappers
 * These are the recommended functions for application use
 ***************************************************************************/

/*
 * Trigger GDB break
 * Forces QEMU to pause and attach GDB via UART
 * On real hardware, triggers an illegal instruction
 */
static inline void bootloader_trigger_gdb(void) {
    __asm__ volatile (
        "move.l #0, %%d0\n\t"
        "trap #15"
        :
        :
        : "d0", "d1", "a0", "cc", "memory"
    );
}

/*
 * Check if running in QEMU
 * Returns: 1 if QEMU, 0 if real Mac
 */
static inline int bootloader_check_env(void) {
    register int result __asm__("d0");
    __asm__ volatile (
        "move.l #1, %%d0\n\t"
        "trap #15"
        : "=r"(result)
        :
        : "d1", "a0", "cc", "memory"
    );
    return result;
}

/*
 * Get bootloader version
 * Returns: Version number (e.g., 0x00010002 for v1.0.2)
 */
static inline uint32_t bootloader_get_version(void) {
    register uint32_t result __asm__("d0");
    __asm__ volatile (
        "move.l #2, %%d0\n\t"
        "trap #15"
        : "=r"(result)
        :
        : "d1", "a0", "cc", "memory"
    );
    return result;
}

/*
 * Set debug verbosity level
 * Parameters: level - DEBUG_SILENT, DEBUG_NORMAL, or DEBUG_VERBOSE
 */
static inline void bootloader_set_debug(DebugVerbosityLevel level) {
    __asm__ volatile (
        "move.l %0, %%d0\n\t"
        "move.l %1, %%d0\n\t"  /* Function ID = 3 */
        "trap #15"
        :
        : "i"(3), "r"(level)
        : "d1", "a0", "cc", "memory"
    );
}

/*
 * Dump memory region
 * Parameters: start - starting address, size - size in bytes
 */
static inline void bootloader_dump_memory(uint32_t start, uint32_t size) {
    __asm__ volatile (
        "move.l %0, %%a0\n\t"
        "move.l %1, %%d1\n\t"
        "move.l #4, %%d0\n\t"
        "trap #15"
        :
        : "r"(start), "r"(size)
        : "d0", "d1", "a0", "cc", "memory"
    );
}

/*
 * Log message to debug console
 * Parameters: msg - null-terminated string pointer
 */
static inline void bootloader_log_message(const char *msg) {
    __asm__ volatile (
        "move.l %0, %%a0\n\t"
        "move.l #5, %%d0\n\t"
        "trap #15"
        :
        : "r"(msg)
        : "d0", "d1", "a0", "cc", "memory"
    );
}

/*
 * Get detected CPU type
 * Returns: CPU_ID_* constant from config.h
 */
static inline uint32_t bootloader_get_cpu_type(void) {
    register uint32_t result __asm__("d0");
    __asm__ volatile (
        "move.l #6, %%d0\n\t"
        "trap #15"
        : "=r"(result)
        :
        : "d1", "a0", "cc", "memory"
    );
    return result;
}

/*
 * Verify bootloader API presence
 * Returns: API_MAGIC_NUMBER (0xDEADBEEF) if present, 0 otherwise
 */
static inline uint32_t bootloader_get_api_magic(void) {
    register uint32_t result __asm__("d0");
    __asm__ volatile (
        "move.l #7, %%d0\n\t"
        "trap #15"
        : "=r"(result)
        :
        : "d1", "a0", "cc", "memory"
    );
    return result;
}

/*
 * Check if custom bootloader is present
 * Returns: 1 if present, 0 otherwise
 */
static inline int bootloader_check_presence(void) {
    register int result __asm__("d0");
    __asm__ volatile (
        "move.l #10, %%d0\n\t"
        "trap #15"
        : "=r"(result)
        :
        : "d1", "a0", "cc", "memory"
    );
    return result;
}

/*
 * Install NMI handler (if not already installed)
 */
static inline void bootloader_install_nmi(void) {
    __asm__ volatile (
        "move.l #8, %%d0\n\t"
        "trap #15"
        :
        :
        : "d0", "d1", "a0", "cc", "memory"
    );
}

/*
 * Get BootInfo structure pointer
 * Returns: Pointer to BootInfo structure or NULL
 */
static inline BootInfo* bootloader_get_bootinfo(void) {
    register BootInfo* result __asm__("a0");
    __asm__ volatile (
        "move.l #11, %%d0\n\t"
        "trap #15"
        : "=r"(result)
        :
        : "d0", "d1", "cc", "memory"
    );
    return result;
}

/*
 * Set breakpoint at address
 * Parameters: address - address to set breakpoint
 */
static inline void bootloader_set_breakpoint(uint32_t address) {
    __asm__ volatile (
        "move.l %0, %%a0\n\t"
        "move.l #12, %%d0\n\t"
        "trap #15"
        :
        : "r"(address)
        : "d0", "d1", "a0", "cc", "memory"
    );
}

/*
 * Clear breakpoint at address
 * Parameters: address - address to clear breakpoint
 */
static inline void bootloader_clear_breakpoint(uint32_t address) {
    __asm__ volatile (
        "move.l %0, %%a0\n\t"
        "move.l #13, %%d0\n\t"
        "trap #15"
        :
        : "r"(address)
        : "d0", "d1", "a0", "cc", "memory"
    );
}

/***************************************************************************
 * Backtrace Generation
 * Architecture-specific implementations
 ***************************************************************************/

/*
 * Generate backtrace for 68k architecture
 * Uses frame pointer (A6) chain
 * 
 * Parameters:
 *   buffer - pointer to buffer to store addresses
 *   max_depth - maximum number of frames to capture
 * 
 * Returns: number of frames captured
 */
static inline int generate_backtrace_68k(uint32_t *buffer, int max_depth) {
    register uint32_t *frame_ptr __asm__("a6");
    register uint32_t *buf __asm__("a0") = buffer;
    register int depth __asm__("d0") = 0;
    register int max_d __asm__("d1") = max_depth;
    register uint32_t ret_addr __asm__("d2");
    
    __asm__ volatile (
        "1:\n\t"
        "cmp.l   #0, %[fp]\n\t"
        "beq     2f\n\t"
        "cmp.l   %[md], %[depth]\n\t"
        "bge     2f\n\t"
        "move.l  4(%[fp]), %[ra]\n\t"  /* Get return address */
        "move.l  %[ra], (%[buf])+\n\t"   /* Store and increment */
        "move.l  (%[fp]), %[fp]\n\t"    /* Move to previous frame */
        "addq.l  #1, %[depth]\n\t"
        "bra     1b\n\t"
        "2:\n\t"
        : [fp] "=r"(frame_ptr), [buf] "=r"(buf), [depth] "=r"(depth),
          [ra] "=r"(ret_addr)
        : [md] "r"(max_d)
        : "d3", "d4", "d5", "d6", "d7", "a1", "a2", "a3", "a4", "a5", "a6",
          "cc", "memory"
    );
    
    return depth;
}

/*
 * Generate backtrace for PPC architecture
 * Uses LR (Link Register) chain
 * 
 * Parameters:
 *   buffer - pointer to buffer to store addresses
 *   max_depth - maximum number of frames to capture
 * 
 * Returns: number of frames captured
 */
static inline int generate_backtrace_ppc(uint32_t *buffer, int max_depth) {
    register uint32_t *stack_ptr __asm__("r1");
    register uint32_t *buf __asm__("r3") = buffer;
    register int depth __asm__("r4") = 0;
    register int max_d __asm__("r5") = max_depth;
    register uint32_t *parent_stack __asm__("r6");
    
    __asm__ volatile (
        "1:\n\t"
        "cmpwi   0, %[sp]\n\t"
        "beq     2f\n\t"
        "cmpw    %[md], %[depth]\n\t"
        "bge     2f\n\t"
        "lwz     0(%[sp]), %[ps]\n\t"    /* Get parent stack pointer */
        "cmpwi   0, %[ps]\n\t"
        "beq     2f\n\t"
        "lwz     8(%[ps]), %[ra]\n\t"    /* Get saved LR (at +8) */
        "stw     %[ra], 0(%[buf])\n\t"
        "addi    %[buf], %[buf], 4\n\t"
        "mr      %[sp], %[ps]\n\t"       /* Move to parent */
        "addi    %[depth], %[depth], 1\n\t"
        "b       1b\n\t"
        "2:\n\t"
        : [sp] "=r"(stack_ptr), [buf] "=r"(buf), [depth] "=r"(depth),
          [ps] "=r"(parent_stack), [ra] "=r"(ret_addr)
        : [md] "r"(max_d)
        : "r0", "r2", "r7", "r8", "r9", "r10", "r11", "r12",
          "cc", "memory"
    );
    
    return depth;
}

/***************************************************************************
 * High-Level Debug Functions
 * These combine multiple API calls for convenience
 ***************************************************************************/

/*
 * Emergency debug break
 * Dumps current context and triggers GDB
 */
static inline void debug_break(void) {
    /* Store current context in shared space */
    DebuggerContext *ctx = (DebuggerContext*)DEBUGGER_SHARED_BASE;
    
    /* Save registers */
    __asm__ volatile (
        "movem.l %%d0-%%d7, %0\n\t"
        "movem.l %%a0-%%a6, %1"
        : "=m"(ctx->registers_d), "=m"(ctx->registers_a)
        :
        : "memory"
    );
    
    __asm__ volatile (
        "move.l %%a7, %0\n\t"
        "move.w %%sr, %1\n\t"
        "move.l %%pc, %2"
        : "=m"(ctx->usp), "=m"(ctx->sr), "=m"(ctx->pc)
        :
        : "memory"
    );
    
    /* Generate backtrace */
    ctx->backtrace_count = generate_backtrace_68k(ctx->backtrace, 20);
    
    /* Trigger GDB */
    bootloader_trigger_gdb();
}

/*
 * Conditional debug break
 * Only triggers if bootloader is present and we're in QEMU
 */
static inline void debug_break_if_possible(void) {
    if (bootloader_check_presence() && bootloader_check_env()) {
        debug_break();
    }
}

/*
 * Assert with debug break
 * If condition is false, triggers debug break
 */
#define DEBUG_ASSERT(condition) \
    do { \
        if (!(condition)) { \
            bootloader_log_message("ASSERT FAILED: " #condition "\n"); \
            debug_break(); \
        } \
    } while (0)

/***************************************************************************
 * Bootloader Presence Detection (Alternative Methods)
 * These work even if TRAP #15 is not installed
 ***************************************************************************/

/*
 * Check for bootloader presence by reading magic number
 * This works without calling TRAP #15
 */
static inline int check_bootloader_magic(void) {
    volatile uint32_t *magic_ptr = (volatile uint32_t*)API_MAGIC_NUMBER_ADDRESS;
    return (*magic_ptr == API_MAGIC_NUMBER);
}

/*
 * Check for NMI handler presence
 * Returns: 1 if custom NMI handler is installed
 */
static inline int check_nmi_handler_present(void) {
    volatile uint32_t *nmi_vector = (volatile uint32_t*)0x0000007C;
    /* Compare against known handler address */
    /* This is a simple check - real implementation would need symbol lookup */
    return (*nmi_vector != 0);
}

/*
 * Full bootloader presence check
 * Tries multiple methods
 */
static inline int is_bootloader_present(void) {
    /* Method 1: Check magic number */
    if (check_bootloader_magic()) {
        return 1;
    }
    
    /* Method 2: Try TRAP #15 */
    if (bootloader_check_presence()) {
        return 1;
    }
    
    /* Method 3: Check NMI handler */
    if (check_nmi_handler_present()) {
        return 1;
    }
    
    return 0;
}

/***************************************************************************
 * Debug Initialization
 * Sets up debug environment for application
 ***************************************************************************/

/*
 * Initialize debug system
 * Call this early in your application
 */
static inline void debug_init(const char *app_name, uint32_t app_version) {
    if (is_bootloader_present()) {
        /* Register application with bootloader */
        DebuggerContext *ctx = DEBUGGER_CTX;
        ctx->app_id = app_version;
        ctx->app_version = app_version;
        
        /* Copy app name (simple strncpy) */
        int i = 0;
        while (app_name[i] && i < 31) {
            ctx->app_name[i] = app_name[i];
            i++;
        }
        ctx->app_name[i] = '\0';
        
        /* Enable NMI handler if not already */
        bootloader_install_nmi();
    }
}

#endif /* __BOOTLOADER_API_H__ */
