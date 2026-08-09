/*
 * main.c - Main entry point for MacOS 7.1 GDB & ICMP Test Application
 * 
 * This application provides a simple GUI to test:
 * 1. GDB remote debugging connection
 * 2. ICMP ping functionality
 * 
 * Compatible with Mac OS 7.1 on both 68k and PowerPC architectures
 */

#include "mac_toolbox.h"
#include "gdb_test.h"
#include "icmp_test.h"

/* Forward declarations */
void test_gdb_function(void);
void test_icmp_function(const unsigned char *hostname);
void draw_window_content(WindowRef window);

/* Global variables */
WindowRef gMainWindow = NULL;

/* Window ID for our main window */
#define MAIN_WINDOW_ID 128

/* Button IDs */
#define GDB_TEST_BUTTON 1
#define ICMP_TEST_BUTTON 2
#define QUIT_BUTTON 3

/* Strings */
const unsigned char gGDBTestString[] = "Test GDB Connection";
const unsigned char gICMPTestString[] = "Test ICMP Ping";
const unsigned char gQuitString[] = "Quit";
const unsigned char gAppTitle[] = "GDB & ICMP Test v1.0";
const unsigned char gGDBLabel[] = "GDB: Not connected";
const unsigned char gICMPLabel[] = "ICMP: Ready";

/* GDB Test Flag */
volatile UInt32 gGDBTestActive = 0;

/* ICMP Test Flag */
volatile UInt32 gICMPTestActive = 0;

/* Test data for GDB inspection */
volatile UInt32 gTestValue = 0xDEADBEEF;
volatile UInt8 gTestArray[16] = {
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10
};
volatile UInt16 gTestWord = 0xABCD;
volatile UInt32 gTestLong = 0x12345678;

/*
 * Initialize the application
 */
Boolean init_application(void) {
    /* Initialize QuickDraw */
    InitGraf(NULL);
    
    /* Load and create main window from resource */
    gMainWindow = GetNewWindow(MAIN_WINDOW_ID, NULL, NULL);
    if (gMainWindow == NULL) {
        SysBeep(10);
        return false;
    }
    
    /* Set window title */
    /* Note: In real Mac OS, we'd use SetWTitle, but this is simplified */
    
    /* Show the window */
    ShowWindow(gMainWindow);
    DrawGrowIcon(gMainWindow);
    
    /* Draw initial content */
    draw_window_content(gMainWindow);
    
    return true;
}

/*
 * Draw window content
 */
void draw_window_content(WindowRef window) {
    GrafPtr oldPort;
    
    if (window == NULL) return;
    
    oldPort = GetPort();
    SetPort(window);
    
    /* Clear window */
    /* In real implementation, we'd use EraseRect */
    
    /* Draw title */
    MoveTo(10, 20);
    DrawString(gAppTitle);
    
    /* Draw GDB status */
    MoveTo(10, 40);
    DrawString(gGDBLabel);
    
    /* Draw ICMP status */
    MoveTo(10, 60);
    DrawString(gICMPLabel);
    
    /* Draw test data for GDB inspection */
    MoveTo(10, 100);
    DrawString((unsigned char *)"Test Data:");
    
    /* Restore port */
    SetPort(oldPort);
}

/*
 * Handle mouse click in window
 */
void handle_mouse_click(EventRecord *event) {
    Point mousePoint;
    Rect buttonRect;
    
    if (gMainWindow == NULL) return;
    
    mousePoint = event->where;
    
    /* Check if click is in GDB test button area */
    SetRect(&buttonRect, 20, 120, 180, 140);
    if (PtInRect(mousePoint, &buttonRect)) {
        gGDBTestActive = 1;
        test_gdb_function();
        gGDBTestActive = 0;
        draw_window_content(gMainWindow);
        return;
    }
    
    /* Check if click is in ICMP test button area */
    SetRect(&buttonRect, 20, 150, 180, 170);
    if (PtInRect(mousePoint, &buttonRect)) {
        gICMPTestActive = 1;
        test_icmp_function((unsigned char *)"127.0.0.1");
        gICMPTestActive = 0;
        draw_window_content(gMainWindow);
        return;
    }
    
    /* Check if click is in Quit button area */
    SetRect(&buttonRect, 20, 180, 180, 200);
    if (PtInRect(mousePoint, &buttonRect)) {
        gMainWindow = NULL;
    }
}

/*
 * Main event loop
 */
void main_event_loop(void) {
    EventRecord event;
    Boolean running = true;
    
    while (running) {
        /* Get next event */
        if (WaitNextEvent(
            (UInt16)(mouseDown | keyDown | updateEvt),
            &event,
            10,
            NULL
        )) {
            switch (event.what) {
                case mouseDown:
                    handle_mouse_click(&event);
                    if (gMainWindow == NULL) {
                        running = false;
                    }
                    break;
                    
                case keyDown:
                    /* Check for Command-Q to quit */
                    if (event.modifiers & cmdKey && 
                        (event.message & 0xFF) == 'q') {
                        running = false;
                    }
                    break;
                    
                case updateEvt:
                    /* Window update event */
                    if ((WindowRef)event.message == gMainWindow) {
                        draw_window_content(gMainWindow);
                    }
                    break;
            }
        }
        
        /* GDB can break here during idle loop */
        /* This is a good place for GDB to attach */
        __asm__ volatile ("nop"); /* GDB breakpoint location */
    }
}

/*
 * Main entry point
 */
void main(void) {
    /* Initialize application */
    if (!init_application()) {
        return;
    }
    
    /* Enter main event loop */
    main_event_loop();
    
    /* Cleanup */
    if (gMainWindow != NULL) {
        DisposeWindow(gMainWindow);
        gMainWindow = NULL;
    }
}

/*
 * GDB Test Function
 * This function contains code designed for GDB testing
 * It has known patterns that GDB can recognize and break on
 */
void test_gdb_function(void) {
    volatile UInt32 i;
    
    /* Set a flag that GDB can watch */
    gTestValue = 0xCAFEBABE;
    
    /* Manipulate test data */
    for (i = 0; i < 16; i++) {
        gTestArray[i] = (UInt8)(i * 0x11);
    }
    
    gTestWord = 0xDCBA;
    gTestLong = 0x87654321;
    
    /* GDB breakpoint - this is where GDB should attach */
    /* On 68k: TRAP #3 (breakpoint instruction) */
    /* On PPC: twi 31,0,0 (breakpoint) */
    /* We use inline assembly for architecture-specific breakpoints */
    
    #if defined(__mc68k__)
        /* 68k breakpoint: TRAP #3 */
        __asm__ volatile ("trap #3");
    #elif defined(__ppc__)
        /* PowerPC breakpoint: twi 31,0,0 */
        __asm__ volatile ("twi 31,0,0");
    #else
        /* Generic breakpoint - GDB will stop here */
        __asm__ volatile ("nop");
        __asm__ volatile ("nop");
        __asm__ volatile ("nop");
    #endif
    
    /* If we continue past breakpoint, do some more work */
    for (i = 0; i < 100; i++) {
        gTestValue += i;
    }
    
    /* GDB can also break here */
    __asm__ volatile ("nop");
}

/*
 * ICMP Test Function
 * Sends ICMP echo requests (ping)
 * Note: Mac OS 7.1 has limited networking, this is a simplified version
 */
void test_icmp_function(const unsigned char *hostname) {
    /* Simplified ICMP implementation for Mac OS 7.1 */
    /* In a real implementation, we would use MacTCP or OpenTransport */
    
    volatile UInt32 sequence = 0;
    volatile UInt32 timestamp;
    
    /* For GDB: set test values */
    gTestValue = 0xICMPTEST;
    
    /* Simulate sending ICMP packets */
    /* This is a placeholder - actual ICMP requires network stack */
    
    /* Try to open a connection (simplified) */
    /* In real Mac OS, we'd use OpenDriver or similar */
    
    /* For now, just simulate the process */
    sequence = 1;
    timestamp = 0;
    
    /* Simulate packet send/receive */
    while (sequence <= 4) {
        /* Send packet */
        /* Wait for reply (simulated) */
        
        /* In GDB, you can break here and inspect variables */
        __asm__ volatile ("nop"); /* Breakpoint location */
        
        sequence++;
    }
    
    /* ICMP test complete */
    gTestValue = 0xDONEICMP;
}

/*
 * Helper: Check if point is in rect
 */
Boolean PtInRect(Point pt, Rect *r) {
    return (pt.v >= r->top && pt.v <= r->bottom &&
            pt.h >= r->left && pt.h <= r->right);
}
