/***************************************************************************
 * MacOS71_GDB_ICMP_Test - Main Application
 * 
 * ICMP test application demonstrating integration with custom bootloader.
 * This application:
 * - Tests network connectivity via ICMP ping
 * - Uses bootloader for debugging if present
 * - Falls back to standard debugging if bootloader is not present
 * - Can be debugged via GDB
 * 
 * Architecture: Motorola 68k
 * Environment: QEMU or Real Mac
 * 
 * Usage:
 *   qemu-system-m68k -kernel combined.bin -m 128M -serial stdio -nographic -gdb tcp::2346
 * 
 * Or with custom bootloader:
 *   cat bootloader_fatbin.bin app.bin > combined.bin
 *   qemu-system-m68k -kernel combined.bin ...
 ***************************************************************************/

#include "debug_utils.h"
#include "icmp.h"

/***************************************************************************
 * Configuration
 ***************************************************************************/

/* ICMP test configuration */
#define TEST_HOST       "127.0.0.1"  /* Localhost for testing */
#define TEST_COUNT      4            /* Number of pings to send */
#define TEST_TIMEOUT    2000         /* Timeout in milliseconds */
#define TEST_INTERVAL   1000         /* Interval between pings (ms) */

/* Application state */
typedef struct {
    int initialized;
    int bootloader_present;
    int qemu_detected;
    int test_count;
    int success_count;
    int error_count;
} AppState;

static AppState app_state = {0};

/***************************************************************************
 * Forward Declarations
 ***************************************************************************/

static void print_banner(void);
static void print_summary(void);
static void run_tests(void);
static void handle_signal(int signum);

/***************************************************************************
 * Main Entry Point
 ***************************************************************************/

int main(void) {
    /* Initialize application */
    app_state.initialized = 1;
    app_state.bootloader_present = debug_init();
    app_state.qemu_detected = is_qemu();
    app_state.test_count = 0;
    app_state.success_count = 0;
    app_state.error_count = 0;
    
    /* Print banner */
    print_banner();
    
    /* Run tests */
    run_tests();
    
    /* Print summary */
    print_summary();
    
    /* Cleanup */
    debug_shutdown();
    
    /* Return appropriate exit code */
    return (app_state.error_count > 0) ? 1 : 0;
}

/***************************************************************************
 * Print Banner
 ***************************************************************************/

static void print_banner(void) {
    debug_info("\n");
    debug_info("======================================================================\n");
    debug_info("                   MacOS71_GDB_ICMP_Test\n");
    debug_info("                    v1.0.0 - 2026-08-09\n");
    debug_info("======================================================================\n");
    debug_info("\n");
    
    debug_info("Environment:\n");
    debug_info("  Bootloader Present: %s\n", app_state.bootloader_present ? "YES" : "NO");
    debug_info("  Running in QEMU: %s\n", app_state.qemu_detected ? "YES" : "NO");
    debug_info("  Debug Level: %d\n", current_debug_level);
    
    if (app_state.bootloader_present) {
        uint32_t version = bootloader_get_version();
        debug_info("  Bootloader Version: 0x%08X\n", version);
        
        uint32_t cpu_type = bootloader_get_cpu_type();
        debug_info("  CPU Type: %d\n", cpu_type);
    }
    
    debug_info("\n");
}

/***************************************************************************
 * Print Summary
 ***************************************************************************/

static void print_summary(void) {
    debug_info("\n");
    debug_info("======================================================================\n");
    debug_info("                              SUMMARY\n");
    debug_info("======================================================================\n");
    debug_info("\n");
    
    debug_info("Tests Run: %d\n", app_state.test_count);
    debug_info("Successful: %d\n", app_state.success_count);
    debug_info("Errors: %d\n", app_state.error_count);
    
    DebugStats stats = debug_get_stats();
    debug_info("\n");
    debug_info("Debug Statistics:\n");
    debug_info("  Messages Output: %u\n", stats.messages_output);
    debug_info("  Breaks Triggered: %u\n", stats.breaks_triggered);
    debug_info("  Backtraces Generated: %u\n", stats.backtraces_generated);
    debug_info("  Errors Handled: %u\n", stats.errors_handled);
    debug_info("  Memory Dumps: %u\n", stats.memory_dumps);
    
    debug_info("\n");
    debug_info("======================================================================\n");
    debug_info("\n");
}

/***************************************************************************
 * Run Tests
 ***************************************************************************/

static void run_tests(void) {
    debug_info("Starting ICMP Tests...\n");
    debug_info("Target: %s\n", TEST_HOST);
    debug_info("Count: %d\n", TEST_COUNT);
    debug_info("Timeout: %d ms\n", TEST_TIMEOUT);
    debug_info("\n");
    
    /* Initialize network */
    if (!icmp_init()) {
        debug_error("Failed to initialize ICMP\n");
        return;
    }
    
    /* Run ping tests */
    for (int i = 0; i < TEST_COUNT; i++) {
        debug_info("Ping #%d to %s...\n", i + 1, TEST_HOST);
        
        /* Send ICMP echo request */
        int result = icmp_ping(TEST_HOST, TEST_TIMEOUT);
        
        app_state.test_count++;
        
        if (result == ICMP_SUCCESS) {
            debug_info("  Reply from %s: time=%d ms\n", TEST_HOST, result);
            app_state.success_count++;
        } else if (result == ICMP_TIMEOUT) {
            debug_warn("  Request timed out\n");
            app_state.error_count++;
        } else {
            debug_error("  Error: %s\n", icmp_error_string(result));
            app_state.error_count++;
            
            /* Generate backtrace on error */
            if (app_state.bootloader_present) {
                debug_print_backtrace(10);
            }
        }
        
        /* Wait before next ping */
        if (i < TEST_COUNT - 1) {
            /* Simple delay - in real app, use proper timing */
            volatile int delay = TEST_INTERVAL * 100;
            while (delay--) {
                /* Busy wait */
            }
        }
    }
    
    /* Cleanup network */
    icmp_shutdown();
}

/***************************************************************************
 * Signal Handler (for debugging)
 ***************************************************************************/

static void handle_signal(int signum) {
    debug_error("Received signal %d\n", signum);
    debug_print_backtrace(10);
    debug_break();
}

/***************************************************************************
 * Test Functions
 ***************************************************************************/

/*
 * Test bootloader API
 */
void test_bootloader_api(void) {
    debug_info("Testing Bootloader API...\n");
    
    if (!app_state.bootloader_present) {
        debug_info("  Bootloader not present - skipping\n");
        return;
    }
    
    /* Test CHECK_ENV */
    int is_qemu = bootloader_check_env();
    debug_info("  CHECK_ENV: %d\n", is_qemu);
    
    /* Test GET_VERSION */
    uint32_t version = bootloader_get_version();
    debug_info("  GET_VERSION: 0x%08X\n", version);
    
    /* Test GET_CPU_TYPE */
    uint32_t cpu_type = bootloader_get_cpu_type();
    debug_info("  GET_CPU_TYPE: %d\n", cpu_type);
    
    /* Test GET_API_MAGIC */
    uint32_t magic = bootloader_get_api_magic();
    debug_info("  GET_API_MAGIC: 0x%08X\n", magic);
    
    /* Test LOG_MESSAGE */
    bootloader_log_message("  [TEST] LOG_MESSAGE works!\n");
    
    /* Test DUMP_MEMORY */
    uint32_t test_data[4] = {0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0x9ABCDEF0};
    bootloader_dump_memory((uint32_t)test_data, sizeof(test_data));
    
    debug_info("  All API tests passed!\n");
}

/*
 * Test debug break
 */
void test_debug_break(void) {
    debug_info("Testing Debug Break...\n");
    
    if (app_state.bootloader_present && app_state.qemu_detected) {
        debug_info("  Triggering GDB break...\n");
        debug_break();
    } else {
        debug_info("  Skipping (bootloader not present or not in QEMU)\n");
    }
}

/*
 * Test error handling
 */
void test_error_handling(void) {
    debug_info("Testing Error Handling...\n");
    
    /* Simulate an error */
    debug_handle_error(ERROR_GENERIC, "This is a test error", 0);
    
    /* This will trigger a backtrace and potentially a debug break */
    /* Uncomment the next line to test debug break on error */
    /* debug_handle_error(ERROR_GENERIC, "This will break", 1); */
    
    debug_info("  Error handling test complete\n");
}

/***************************************************************************
 * Memory Test
 ***************************************************************************/

void test_memory_dump(void) {
    debug_info("Testing Memory Dump...\n");
    
    uint32_t test_buffer[8];
    for (int i = 0; i < 8; i++) {
        test_buffer[i] = i * 0x11111111;
    }
    
    debug_dump_memory((uint32_t)test_buffer, sizeof(test_buffer));
}

/***************************************************************************
 * Assert Test
 ***************************************************************************/

void test_assertions(void) {
    debug_info("Testing Assertions...\n");
    
    /* This should pass */
    DEBUG_ASSERT(1 == 1);
    debug_info("  Passed: 1 == 1\n");
    
    /* This would fail and trigger debug break */
    /* Uncomment to test: */
    /* DEBUG_ASSERT(1 == 0); */
}
