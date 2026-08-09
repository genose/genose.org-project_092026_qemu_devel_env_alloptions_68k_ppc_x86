/***************************************************************************
 * Custom Bootloader - Debug Shared Memory Header
 * 
 * Defines the shared memory layout between bootloader and applications.
 * This memory region at 0x00F00000 is used for:
 * - Emergency context storage
 * - Debug information exchange
 * - Backtrace storage
 * - Application metadata
 * 
 * The layout must match between bootloader and application exactly.
 * 
 * Memory Map:
 *   0x00F00000 - 0x00F000FF : Debugger Context (256 bytes)
 *   0x00F00100 - 0x00F010FF : Debug Stack (4KB)
 *   0x00F01100 - 0x00F01FFF : Log Buffer (4KB)
 *   0x00F02000 - 0x00F0FFFF : Scratch Space (36KB)
 ***************************************************************************/

#ifndef __DEBUG_SHARED_H__
#define __DEBUG_SHARED_H__

#include <stdint.h>
#include "config.h"

/***************************************************************************
 * Memory Region Addresses
 ***************************************************************************/

#define DEBUGGER_BASE              0x00F00000

/* Context storage */
#define DEBUGGER_CTX_OFFSET         0x0000
#define DEBUGGER_CTX_SIZE           0x0100  /* 256 bytes */
#define DEBUGGER_CTX_ADDRESS        (DEBUGGER_BASE + DEBUGGER_CTX_OFFSET)

/* Stack for debug handler */
#define DEBUGGER_STACK_OFFSET       0x0100
#define DEBUGGER_STACK_SIZE         0x1000  /* 4KB */
#define DEBUGGER_STACK_TOP          (DEBUGGER_BASE + DEBUGGER_STACK_OFFSET + DEBUGGER_STACK_SIZE)

/* Log buffer */
#define DEBUG_LOG_OFFSET            0x1100
#define DEBUG_LOG_SIZE              0x1000  /* 4KB */
#define DEBUG_LOG_ADDRESS           (DEBUGGER_BASE + DEBUG_LOG_OFFSET)

/* Scratch space */
#define DEBUG_SCRATCH_OFFSET        0x2000
#define DEBUG_SCRATCH_SIZE          0xE000  /* 56KB */
#define DEBUG_SCRATCH_ADDRESS       (DEBUGGER_BASE + DEBUG_SCRATCH_OFFSET)

/***************************************************************************
 * Debugger Context Structure
 * 
 * This structure is stored at DEBUGGER_BASE (0x00F00000).
 * It contains the complete CPU state when an exception occurs,
 * plus debug information.
 * 
 * Size: 256 bytes (must be power of 2 for alignment)
 ***************************************************************************/

/* Register names for clarity */
#define D0  registers_d[0]
#define D1  registers_d[1]
#define D2  registers_d[2]
#define D3  registers_d[3]
#define D4  registers_d[4]
#define D5  registers_d[5]
#define D6  registers_d[6]
#define D7  registers_d[7]

#define A0  registers_a[0]
#define A1  registers_a[1]
#define A2  registers_a[2]
#define A3  registers_a[3]
#define A4  registers_a[4]
#define A5  registers_a[5]
#define A6  registers_a[6]

typedef struct {
    /* ---- CPU Register State (64 bytes) ---- */
    uint32_t registers_d[8];      /* D0-D7 */
    uint32_t registers_a[7];      /* A0-A6 */
    uint32_t usp;                 /* User Stack Pointer (A7) */
    uint32_t ssp;                 /* Supervisor Stack Pointer */
    uint32_t pc;                  /* Program Counter */
    uint16_t sr;                  /* Status Register */
    uint16_t padding_0;           /* Padding */
    
    /* ---- Exception Information (32 bytes) ---- */
    uint32_t exception_vector;    /* Which exception occurred */
    uint32_t exception_pc;        /* PC at time of exception */
    uint16_t exception_sr;        /* SR at time of exception */
    uint16_t padding_1;           /* Padding */
    uint32_t exception_address;   /* Address that caused exception */
    uint32_t exception_format;    /* Exception format word */
    
    /* ---- Environment Flags (16 bytes) ---- */
    uint32_t is_qemu;             /* 1 = QEMU, 0 = real Mac */
    uint32_t bootloader_present;  /* 1 = custom bootloader present */
    uint32_t nmi_handler_installed; /* 1 = NMI handler installed */
    uint32_t trap15_handler_installed; /* 1 = TRAP #15 handler installed */
    
    /* ---- Control Flags (16 bytes) ---- */
    uint32_t resume_flag;         /* 1 = resume execution after debug */
    uint32_t step_flag;           /* 1 = single-step execution */
    uint32_t breakpoint_hit;      /* 1 = breakpoint was hit */
    uint32_t manual_break;        /* 1 = manual break (not exception) */
    
    /* ---- Backtrace (88 bytes) ---- */
    uint32_t backtrace[20];       /* Array of return addresses */
    uint32_t backtrace_count;     /* Number of frames captured */
    uint32_t backtrace_pad[2];    /* Padding to align */
    
    /* ---- Error Information (16 bytes) ---- */
    uint32_t last_error_code;     /* Last error code */
    uint32_t last_error_pc;       /* PC where error occurred */
    uint32_t last_error_addr;     /* Address that caused error */
    uint32_t error_count;         /* Total error count */
    
    /* ---- Application Information (48 bytes) ---- */
    uint32_t app_id;              /* Application identifier */
    uint32_t app_version;         /* Application version */
    char     app_name[32];       /* Application name (null-terminated) */
    
    /* ---- Statistics (32 bytes) ---- */
    uint32_t nmi_count;           /* Number of NMI invocations */
    uint32_t trap15_count;        /* Number of TRAP #15 calls */
    uint32_t gdb_break_count;     /* Number of GDB breaks */
    uint32_t backtrace_count;     /* Total backtraces generated */
    
    /* ---- Reserved (32 bytes) ---- */
    uint32_t reserved[8];
} __attribute__((packed)) DebuggerContext;

/* Ensure structure is 256 bytes */
static_assert(sizeof(DebuggerContext) == DEBUGGER_CTX_SIZE, \
    "DebuggerContext size mismatch");

/* Easy access to the debugger context */
#define DEBUGGER_CTX ((volatile DebuggerContext*)DEBUGGER_CTX_ADDRESS)

/***************************************************************************
 * Log Buffer Structure
 * 
 * Circular buffer for debug messages.
 * Located at DEBUG_LOG_ADDRESS (0x00F01100)
 ***************************************************************************/

#define LOG_BUFFER_SIZE     1024  /* Number of log entries */
#define LOG_ENTRY_SIZE      64    /* Size of each log entry */

typedef struct {
    uint32_t timestamp;           /* When the log was created */
    uint16_t severity;            /* Log severity level */
    uint16_t length;              /* Length of message */
    char     message[LOG_ENTRY_SIZE - 8]; /* Log message */
} LogEntry;

typedef struct {
    LogEntry entries[LOG_BUFFER_SIZE];
    uint32_t head;                 /* Write position */
    uint32_t tail;                 /* Read position */
    uint32_t count;                /* Number of entries */
    uint32_t dropped;              /* Number of dropped entries */
} LogBuffer;

#define DEBUG_LOG ((volatile LogBuffer*)DEBUG_LOG_ADDRESS)

/*** Log Severity Levels ***/
typedef enum {
    LOG_SEVERITY_DEBUG   = 0,
    LOG_SEVERITY_INFO    = 1,
    LOG_SEVERITY_WARN    = 2,
    LOG_SEVERITY_ERROR   = 3,
    LOG_SEVERITY_CRITICAL = 4
} LogSeverity;

/***************************************************************************
 * Exception Vector Definitions
 * Used in DebuggerContext.exception_vector
 ***************************************************************************/

#define EXCEPTION_RESET             0x00
#define EXCEPTION_BUS_ERROR         0x02
#define EXCEPTION_ADDRESS_ERROR     0x03
#define EXCEPTION_ILLEGAL_INSTR     0x04
#define EXCEPTION_ZERO_DIVIDE       0x05
#define EXCEPTION_CHK_TRAP          0x06
#define EXCEPTION_TRAPV             0x07
#define EXCEPTION_PRIVILEGE_VIOL    0x08
#define EXCEPTION_TRACE             0x09
#define EXCEPTION_LINE_A            0x0A
#define EXCEPTION_LINE_F            0x0B
#define EXCEPTION_FORMAT_ERROR      0x0F
#define EXCEPTION_UNINITIALIZED_INT 0x10
#define EXCEPTION_SPURIOUS          0x1F
#define EXCEPTION_TRAP_0            0x20
#define EXCEPTION_TRAP_1            0x21
#define EXCEPTION_TRAP_2            0x22
#define EXCEPTION_TRAP_3            0x23
#define EXCEPTION_TRAP_4            0x24
#define EXCEPTION_TRAP_5            0x25
#define EXCEPTION_TRAP_6            0x26
#define EXCEPTION_TRAP_7            0x27
#define EXCEPTION_TRAP_8            0x28
#define EXCEPTION_TRAP_9            0x29
#define EXCEPTION_TRAP_10           0x2A
#define EXCEPTION_TRAP_11           0x2B
#define EXCEPTION_TRAP_12           0x2C
#define EXCEPTION_TRAP_13           0x2D
#define EXCEPTION_TRAP_14           0x2E
#define EXCEPTION_TRAP_15           0x2F
#define EXCEPTION_NMI               0x7C  /* Non-Maskable Interrupt */

/***************************************************************************
 * Helper Macros
 ***************************************************************************/

/* Reset the debugger context */
#define DEBUGGER_CTX_RESET() \
    __asm__ volatile ("clr.l (0x00F00000)")

/* Set resume flag to continue execution */
#define DEBUGGER_SET_RESUME() \
    __asm__ volatile ("move.l #1, 0x00F00048")

/* Clear resume flag */
#define DEBUGGER_CLEAR_RESUME() \
    __asm__ volatile ("clr.l 0x00F00048")

/* Set manual break flag */
#define DEBUGGER_SET_MANUAL_BREAK() \
    __asm__ volatile ("move.l #1, 0x00F0004C")

/* Check if in debug mode */
#define DEBUGGER_IS_IN_DEBUG() \
    (*(volatile uint32_t*)0x00F00044)

/***************************************************************************
 * Utility Functions (Inline)
 ***************************************************************************/

/*
 * Add a log entry
 * Returns: 1 if successful, 0 if buffer full
 */
static inline int debug_log(LogSeverity severity, const char *message) {
    volatile LogBuffer *log = DEBUG_LOG;
    
    /* Check if buffer is full */
    if (log->count >= LOG_BUFFER_SIZE) {
        log->dropped++;
        return 0;
    }
    
    /* Add entry */
    LogEntry *entry = &log->entries[log->head];
    entry->severity = severity;
    entry->length = (uint16_t)strlen(message);
    
    /* Copy message */
    int i = 0;
    while (message[i] && i < LOG_ENTRY_SIZE - 8) {
        entry->message[i] = message[i];
        i++;
    }
    entry->message[i] = '\0';
    
    /* Update buffer */
    log->head = (log->head + 1) % LOG_BUFFER_SIZE;
    log->count++;
    
    return 1;
}

/*
 * Get last error information
 */
static inline void debug_get_last_error(
    uint32_t *code,
    uint32_t *pc,
    uint32_t *addr
) {
    DebuggerContext *ctx = DEBUGGER_CTX;
    *code = ctx->last_error_code;
    *pc = ctx->last_error_pc;
    *addr = ctx->last_error_addr;
}

/*
 * Get exception information
 */
static inline void debug_get_exception(
    uint32_t *vector,
    uint32_t *pc,
    uint16_t *sr,
    uint32_t *addr
) {
    DebuggerContext *ctx = DEBUGGER_CTX;
    *vector = ctx->exception_vector;
    *pc = ctx->exception_pc;
    *sr = ctx->exception_sr;
    *addr = ctx->exception_address;
}

/*
 * Get backtrace
 */
static inline int debug_get_backtrace(uint32_t *buffer, int max_count) {
    DebuggerContext *ctx = DEBUGGER_CTX;
    int count = (int)ctx->backtrace_count;
    
    if (count > max_count) {
        count = max_count;
    }
    
    for (int i = 0; i < count; i++) {
        buffer[i] = ctx->backtrace[i];
    }
    
    return count;
}

/*
 * Get CPU registers
 */
static inline void debug_get_registers(
    uint32_t *d_regs,
    uint32_t *a_regs,
    uint32_t *pc,
    uint16_t *sr
) {
    DebuggerContext *ctx = DEBUGGER_CTX;
    
    for (int i = 0; i < 8; i++) {
        d_regs[i] = ctx->registers_d[i];
    }
    
    for (int i = 0; i < 7; i++) {
        a_regs[i] = ctx->registers_a[i];
    }
    
    *pc = ctx->pc;
    *sr = ctx->sr;
}

#endif /* __DEBUG_SHARED_H__ */
