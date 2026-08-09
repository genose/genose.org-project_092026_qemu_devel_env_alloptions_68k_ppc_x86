/*
 * gdb_test.h - GDB test function declarations and macros
 * For use with Mac OS 7.1 GDB debugging
 */

#ifndef GDB_TEST_H
#define GDB_TEST_H

#include "mac_toolbox.h"

/* GDB Test Macros */

/* Set a GDB breakpoint */
#define GDB_BREAK() do { \
    __asm__ volatile ("nop"); \
    __asm__ volatile ("nop"); \
    __asm__ volatile ("nop"); \
} while (0)

/* Architecture-specific breakpoints */
#if defined(__mc68k__)
    #define ARCH_BREAK() __asm__ volatile ("trap #3")
#elif defined(__ppc__)
    #define ARCH_BREAK() __asm__ volatile ("twi 31,0,0")
#else
    #define ARCH_BREAK() GDB_BREAK()
#endif

/* GDB Test Structure */
typedef struct {
    volatile UInt32 magic;           /* Magic value for identification */
    volatile UInt32 counter;        /* Counter for testing */
    volatile UInt8 data[64];        /* Test data buffer */
    volatile UInt16 flags;          /* Status flags */
    volatile UInt32 checksum;       /* Data checksum */
} GDBTestBlock;

/* GDB Test Flags */
#define GDB_FLAG_INITIALIZED 0x0001
#define GDB_FLAG_RUNNING     0x0002
#define GDB_FLAG_COMPLETE    0x0004
#define GDB_FLAG_ERROR       0x0008

/* Magic values */
#define GDB_MAGIC_INIT    0xDEADBEEF
#define GDB_MAGIC_GDB     0xCAFEBABE
#define GDB_MAGIC_ICMP    0xBADC0FFE
#define GDB_MAGIC_DONE    0xD0NE1234

/* Global GDB test block */
extern volatile GDBTestBlock gGDBTestBlock;

/* Function declarations */
void test_gdb_function(void);
void test_gdb_registers(void);
void test_gdb_memory(void);
void test_gdb_stack(void);
void init_gdb_test_block(void);

/* Register test values */
#define REGISTER_TEST_A7 0x00001000
#define REGISTER_TEST_D0 0x12345678
#define REGISTER_TEST_D1 0x9ABCDEF0

/* Memory test pattern */
#define MEMORY_TEST_PATTERN 0xAA55AA55

/* Stack test depth */
#define STACK_TEST_DEPTH 16

/* GDB Helper Macros */

/* Create a GDB label */
#define GDB_LABEL(name) gdb_label_##name: __asm__ volatile ("nop")

/* GDB assembly block */
#define GDB_ASM_START() __asm__ volatile ("\n"
#define GDB_ASM_END() "\n")

/* GDB inspection point */
#define GDB_INSPECT(name) do { \
    volatile UInt32 inspect_##name = 0x##name; \
    ARCH_BREAK(); \
} while (0)

#endif /* GDB_TEST_H */
