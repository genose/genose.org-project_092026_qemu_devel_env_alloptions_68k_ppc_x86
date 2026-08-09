/*
 * gdb_test.c - GDB test functions for Mac OS 7.1
 * 
 * This file contains functions specifically designed for GDB debugging testing.
 * Each function has clear breakpoints and test patterns that GDB can inspect.
 */

#include "gdb_test.h"

/* Global GDB test block */
volatile GDBTestBlock gGDBTestBlock;

/* Initialize GDB test block */
void init_gdb_test_block(void) {
    volatile UInt32 i;
    volatile UInt32 *p;
    
    gGDBTestBlock.magic = GDB_MAGIC_INIT;
    gGDBTestBlock.counter = 0;
    gGDBTestBlock.flags = GDB_FLAG_INITIALIZED;
    
    /* Fill data buffer with test pattern */
    p = (volatile UInt32 *)gGDBTestBlock.data;
    for (i = 0; i < 16; i++) {
        p[i] = MEMORY_TEST_PATTERN ^ i;
    }
    
    /* Calculate checksum */
    gGDBTestBlock.checksum = 0;
    for (i = 0; i < 64; i++) {
        gGDBTestBlock.checksum += gGDBTestBlock.data[i];
    }
    
    /* Set breakpoint for GDB */
    ARCH_BREAK();
}

/* Test GDB function - main GDB test entry point */
void test_gdb_function(void) {
    /* Initialize test block */
    init_gdb_test_block();
    
    /* Set magic to GDB test value */
    gGDBTestBlock.magic = GDB_MAGIC_GDB;
    gGDBTestBlock.flags |= GDB_FLAG_RUNNING;
    
    /* Test 1: Basic variable inspection */
    GDB_LABEL(test1);
    volatile UInt32 test1_var = 0xTEST0001;
    volatile UInt16 test1_short = 0x1234;
    volatile UInt8 test1_byte = 0x55;
    
    /* Test 2: Array access */
    GDB_LABEL(test2);
    volatile UInt8 array_test[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    volatile UInt8 array_sum = 0;
    volatile UInt8 i;
    for (i = 0; i < 8; i++) {
        array_sum += array_test[i];
    }
    
    /* Test 3: Pointer manipulation */
    GDB_LABEL(test3);
    volatile UInt32 *ptr_test = (volatile UInt32 *)0x00100000;
    volatile UInt32 ptr_value = *ptr_test;  /* This will cause a bus error if address is invalid */
    /* Note: In real use, use a valid address */
    volatile UInt32 safe_ptr_test[4] = {0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC, 0xDDDDDDDD};
    ptr_test = safe_ptr_test;
    ptr_value = ptr_test[0];
    
    /* Test 4: Register manipulation */
    GDB_LABEL(test4);
    test_gdb_registers();
    
    /* Test 5: Memory access */
    GDB_LABEL(test5);
    test_gdb_memory();
    
    /* Test 6: Stack manipulation */
    GDB_LABEL(test6);
    test_gdb_stack();
    
    /* Mark as complete */
    gGDBTestBlock.magic = GDB_MAGIC_DONE;
    gGDBTestBlock.flags |= GDB_FLAG_COMPLETE;
    
    /* Final breakpoint */
    ARCH_BREAK();
}

/* Test register manipulation */
void test_gdb_registers(void) {
    volatile UInt32 r0 = REGISTER_TEST_D0;
    volatile UInt32 r1 = REGISTER_TEST_D1;
    volatile UInt32 r2 = 0xFFFFFFFF;
    volatile UInt32 r3 = 0x00000000;
    
    /* Perform operations for GDB to inspect */
    volatile UInt32 result;
    
    result = r0 + r1;      /* Addition */
    GDB_LABEL(add_result);
    
    result = r0 - r1;      /* Subtraction */
    GDB_LABEL(sub_result);
    
    result = r0 * r1;      /* Multiplication */
    GDB_LABEL(mul_result);
    
    result = r0 / 16;      /* Division */
    GDB_LABEL(div_result);
    
    result = r0 & r1;      /* Bitwise AND */
    GDB_LABEL(and_result);
    
    result = r0 | r1;      /* Bitwise OR */
    GDB_LABEL(or_result);
    
    result = r0 ^ r1;      /* Bitwise XOR */
    GDB_LABEL(xor_result);
    
    result = ~r0;          /* Bitwise NOT */
    GDB_LABEL(not_result);
    
    /* Shift operations */
    result = r0 << 4;      /* Left shift */
    GDB_LABEL(shl_result);
    
    result = r0 >> 4;      /* Right shift */
    GDB_LABEL(shr_result);
    
    /* Set breakpoint */
    ARCH_BREAK();
}

/* Test memory access patterns */
void test_gdb_memory(void) {
    volatile UInt32 memory_block[256];
    volatile UInt32 i, j;
    
    /* Fill memory with pattern */
    GDB_LABEL(fill_memory);
    for (i = 0; i < 256; i++) {
        memory_block[i] = i * 0x01010101;
    }
    
    /* Access memory sequentially */
    GDB_LABEL(read_memory);
    volatile UInt32 sum = 0;
    for (i = 0; i < 256; i++) {
        sum += memory_block[i];
    }
    
    /* Access memory with stride */
    GDB_LABEL(stride_memory);
    volatile UInt32 stride_sum = 0;
    for (i = 0; i < 256; i += 4) {
        stride_sum += memory_block[i];
    }
    
    /* Reverse access */
    GDB_LABEL(reverse_memory);
    volatile UInt32 reverse_sum = 0;
    for (i = 255; i >= 0; i--) {
        reverse_sum += memory_block[i];
    }
    
    /* 2D array access */
    GDB_LABEL(array2d);
    volatile UInt32 array2d[16][16];
    for (i = 0; i < 16; i++) {
        for (j = 0; j < 16; j++) {
            array2d[i][j] = (i << 16) | (j << 8) | (i + j);
        }
    }
    
    /* Set breakpoint */
    ARCH_BREAK();
}

/* Test stack manipulation */
void test_gdb_stack(void) {
    volatile UInt32 stack_data[STACK_TEST_DEPTH];
    volatile UInt32 i;
    
    /* Fill stack frame */
    GDB_LABEL(fill_stack);
    for (i = 0; i < STACK_TEST_DEPTH; i++) {
        stack_data[i] = i * 0x100 + 0xDEAD;
    }
    
    /* Recursive-like pattern */
    GDB_LABEL(stack_pattern);
    volatile UInt32 level1 = stack_data[0];
    volatile UInt32 level2 = stack_data[1];
    volatile UInt32 level3 = stack_data[2];
    volatile UInt32 level4 = stack_data[3];
    
    /* Sum stack data */
    volatile UInt32 stack_sum = 0;
    for (i = 0; i < STACK_TEST_DEPTH; i++) {
        stack_sum += stack_data[i];
    }
    
    /* Modify stack data */
    GDB_LABEL(modify_stack);
    for (i = 0; i < STACK_TEST_DEPTH; i++) {
        stack_data[i] ^= 0xFFFFFFFF;
    }
    
    /* Verify modification */
    volatile UInt32 verify_sum = 0;
    for (i = 0; i < STACK_TEST_DEPTH; i++) {
        verify_sum += stack_data[i];
    }
    
    /* Set breakpoint */
    ARCH_BREAK();
}

/* Assembly-level test functions */

/* Test with inline assembly for architecture-specific features */
void test_asm_68k(void) {
#if defined(__mc68k__)
    __asm__ volatile (
        "move.l #0x12345678, d0\n"
        "move.l #0x9ABCDEF0, d1\n"
        "add.l d1, d0\n"      /* d0 = d0 + d1 */
        "sub.l d1, d0\n"      /* d0 = d0 - d1 */
        "mul.l d1, d0\n"      /* d0 = d0 * d1 (will be 0) */
        "trap #3\n"           /* Breakpoint */
    );
#endif
}

void test_asm_ppc(void) {
#if defined(__ppc__)
    __asm__ volatile (
        "lis 3, 0x1234\n"      /* Load immediate to r3 */
        "ori 3, 3, 0x5678\n"  /* OR immediate */
        "lis 4, 0x9ABC\n"
        "ori 4, 4, 0xDEF0\n"
        "add 3, 3, 4\n"        /* r3 = r3 + r4 */
        "sub 3, 3, 4\n"        /* r3 = r3 - r4 */
        "twi 31, 0, 0\n"      /* Breakpoint */
    );
#endif
}

/* Floating point test (if available) */
void test_fpu(void) {
    volatile UInt32 fpu_available = 0;
    
    /* Check for FPU */
    /* This is architecture-specific */
    
#if defined(__mc68881__) || defined(__mc68882__)
    /* 68881/68882 FPU */
    fpu_available = 1;
    __asm__ volatile ("fmove.d #1.5, fp0\n");
    __asm__ volatile ("fmove.d fp0, fp1\n");
    __asm__ volatile ("fadd.d fp0, fp1\n");
#elif defined(__ppc__)
    /* PowerPC FPU */
    fpu_available = 1;
    __asm__ volatile ("lfd f0, 0(0)");
    __asm__ volatile ("lfd f1, 0(0)");
    __asm__ volatile ("fadd f2, f0, f1");
#endif
    
    ARCH_BREAK();
}
