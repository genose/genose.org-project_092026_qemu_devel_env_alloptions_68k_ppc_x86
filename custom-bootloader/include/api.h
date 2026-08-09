/***************************************************************************
 * Custom Bootloader - Developer API Header
 * 
 * This file defines the Developer API structures and function prototypes.
 * The API is available at fixed addresses starting at 0x2000.
 ***************************************************************************/

#ifndef __API_H__
#define __API_H__

#include "config.h"

/***************************************************************************
 * Type Definitions
 ***************************************************************************/

typedef unsigned char       uint8_t;
typedef signed char         int8_t;
typedef unsigned short      uint16_t;
typedef signed short        int16_t;
typedef unsigned int        uint32_t;
typedef signed int          int32_t;
typedef unsigned long long  uint64_t;
typedef signed long long    int64_t;

typedef uint32_t            size_t;

/***************************************************************************
 * API Region Layout
 * 
 * Address Range     Size    Purpose
 * 0x2000           4       BootInfo pointer
 * 0x2004           4       AppVectors pointer
 * 0x2008           4       APITable pointer
 * 0x200C           4       Status flags
 * 0x2010           4       Magic number (0xDEADBEEF)
 * 0x2014-0x20FF   240     Reserved
 * 0x2100-0x21FF   256     Application vectors
 ***************************************************************************/

/***************************************************************************
 * BootInfo Structure
 * 
 * Contains information about the boot environment.
 ***************************************************************************/

#define BOOTINFO_SIZE              1024

typedef struct BootInfo {
    /* CPU Information */
    uint32_t cpu_type;            /* CPU_ID_68000, CPU_ID_PPC601, etc. */
    uint32_t cpu_features;       /* Bitmask of CPU features */
    uint32_t cpu_speed_mhz;      /* CPU speed in MHz (if known) */
    
    /* Memory Information */
    uint32_t memory_size;        /* Total RAM in bytes */
    uint32_t memory_start;       /* Start of available RAM */
    uint32_t memory_end;         /* End of available RAM */
    
    /* Boot Device Information */
    uint32_t boot_device;        /* BOOT_DEVICE_FLOPPY, BOOT_DEVICE_HD, etc. */
    uint32_t boot_partition;     /* Partition number (if applicable) */
    uint32_t boot_lba;           /* Logical Block Address of boot sector */
    
    /* Boot Arguments */
    uint32_t boot_args[4];       /* Arguments passed to booted system */
    char     command_line[256]; /* Boot command line */
    
    /* Version Information */
    uint32_t bootloader_version;
    uint32_t bootloader_build_date;
    
    /* Platform Information */
    char     platform_name[64]; /* Platform/emulator name */
    uint32_t platform_flags;
    
    /* Reserved for future use */
    uint8_t  reserved[BOOTINFO_SIZE - 256 - 32 - 32 - 16 - 16];
} BootInfo;

/***************************************************************************
 * AppVectors Structure
 * 
 * Contains application-specific entry points and callbacks.
 * This structure is initialized by the application and used by the bootloader.
 ***************************************************************************/

#define APPVECTORS_SIZE            256

typedef struct AppVectors {
    /* Entry points */
    void     (*app_entry)(BootInfo *info);    /* Main application entry */
    void     (*app_init)(BootInfo *info);     /* Initialization callback */
    void     (*app_panic)(const char *msg);    /* Panic/error handler */
    void     (*app_exit)(int code);           /* Exit handler */
    void     (*app_irq)(void);                /* Interrupt handler */
    
    /* Memory layout */
    uint32_t app_stack_ptr;                   /* Application stack pointer */
    uint32_t app_stack_size;                  /* Stack size */
    uint32_t app_heap_start;                   /* Heap start address */
    uint32_t app_heap_size;                    /* Heap size */
    
    /* Application info */
    char     app_name[64];                    /* Application name */
    uint32_t app_version;                      /* Application version */
    uint32_t app_flags;                        /* Application flags */
    
    /* Reserved */
    uint8_t  reserved[APPVECTORS_SIZE - 64 - 32 - 32 - 20];
} AppVectors;

/***************************************************************************
 * APITable Structure
 * 
 * Contains function pointers to all API functions.
 * This structure provides the interface for applications to interact with
 * the bootloader.
 ***************************************************************************/

#define APITABLE_SIZE              512

typedef struct APITable APITable;

struct APITable {
    /* Memory operations */
    void*    (*malloc)(size_t size);
    void     (*free)(void* ptr);
    void*    (*realloc)(void* ptr, size_t size);
    void*    (*memcpy)(void* dest, const void* src, size_t n);
    void*    (*memmove)(void* dest, const void* src, size_t n);
    void*    (*memset)(void* s, int c, size_t n);
    int      (*memcmp)(const void* s1, const void* s2, size_t n);
    void*    (*memchr)(const void* s, int c, size_t n);
    
    /* String operations */
    int      (*strcmp)(const char* s1, const char* s2);
    char*    (*strcpy)(char* dest, const char* src);
    char*    (*strncpy)(char* dest, const char* src, size_t n);
    size_t   (*strlen)(const char* s);
    char*    (*strcat)(char* dest, const char* src);
    char*    (*strncat)(char* dest, const char* src, size_t n);
    char*    (*strchr)(const char* s, int c);
    char*    (*strrchr)(const char* s, int c);
    char*    (*strstr)(const char* haystack, const char* needle);
    int      (*strcmp)(const char* s1, const char* s2);
    int      (*strncmp)(const char* s1, const char* s2, size_t n);
    int      (*strcasecmp)(const char* s1, const char* s2);
    int      (*strncasecmp)(const char* s1, const char* s2, size_t n);
    
    /* Debug operations */
    void     (*printf)(const char* format, ...);
    void     (*sprintf)(char* str, const char* format, ...);
    void     (*vsprintf)(char* str, const char* format, void* ap);
    void     (*hexdump)(void* addr, size_t len);
    void     (*dump_memory)(void* addr, size_t len, int width);
    void     (*backtrace)(void);
    void     (*dump_registers)(void);
    
    /* CPU operations */
    void     (*cpu_halt)(void);
    void     (*cpu_reboot)(void);
    void     (*cpu_idle)(void);
    uint32_t (*cpu_get_id)(void);
    uint32_t (*cpu_get_pvr)(void);
    void     (*cpu_set_irq)(int enable);
    uint32_t (*cpu_get_irq)(void);
    void     (*cpu_disable_cache)(void);
    void     (*cpu_enable_cache)(void);
    
    /* I/O operations */
    void     (*console_putc)(char c);
    char     (*console_getc)(void);
    void     (*console_puts)(const char* s);
    void     (*console_write)(const void* buf, size_t len);
    int      (*console_read)(void* buf, size_t len);
    void     (*console_init)(void);
    
    /* Time operations */
    uint32_t (*timer_get_ticks)(void);
    void     (*timer_delay)(uint32_t ms);
    uint32_t (*timer_get_millis)(void);
    
    /* Disk operations */
    int      (*disk_open)(uint32_t device);
    int      (*disk_read)(uint32_t device, uint64_t lba, void* buf, size_t count);
    int      (*disk_write)(uint32_t device, uint64_t lba, const void* buf, size_t count);
    int      (*disk_close)(uint32_t device);
    int      (*disk_get_info)(uint32_t device, uint32_t *sector_size, uint64_t *total_sectors);
    
    /* Memory management */
    void     (*heap_init)(void* start, size_t size);
    void*    (*heap_alloc)(size_t size);
    void     (*heap_free)(void* ptr);
    size_t   (*heap_get_free)(void);
    
    /* Utility functions */
    void*    (*kmalloc)(size_t size);
    void     (*kfree)(void* ptr);
    void     (*panic)(const char* msg);
    
    /* Math functions */
    int      (*abs)(int n);
    long     (*labs)(long n);
    int      (*min)(int a, int b);
    int      (*max)(int a, int b);
    uint16_t (*swap16)(uint16_t value);
    uint32_t (*swap32)(uint32_t value);
    
    /* Conversion functions */
    char*    (*itoa)(int value, char* str, int base);
    char*    (*utoa)(unsigned int value, char* str, int base);
    int      (*atoi)(const char* str);
    unsigned long (*strtoul)(const char* str, char** endptr, int base);
    
    /* Symbol lookup */
    const char* (*lookup_symbol)(uint32_t addr);
    
    /* Reserved for future expansion */
    uint8_t  reserved[APITABLE_SIZE - sizeof(void*) * 50];
};

/***************************************************************************
 * API Access Macros
 * 
 * These macros provide convenient access to the API pointers at fixed addresses.
 ***************************************************************************/

#define GET_BOOTINFO()     (*(BootInfo **)BOOTINFO_PTR_ADDRESS)
#define GET_APPVECTORS()   (*(AppVectors **)APPVECTORS_PTR_ADDRESS)
#define GET_APITABLE()     (*(APITable **)APITABLE_PTR_ADDRESS)
#define GET_STATUS()       (*(uint32_t *)API_STATUS_FLAGS_ADDRESS)
#define GET_MAGIC()        (*(uint32_t *)API_MAGIC_NUMBER_ADDRESS)

#define SET_BOOTINFO(bi)  (*(BootInfo **)BOOTINFO_PTR_ADDRESS = (bi))
#define SET_APPVECTORS(av) (*(AppVectors **)APPVECTORS_PTR_ADDRESS = (av))
#define SET_APITABLE(at)  (*(APITable **)APITABLE_PTR_ADDRESS = (at))
#define SET_STATUS(s)     (*(uint32_t *)API_STATUS_FLAGS_ADDRESS = (s))

/***************************************************************************
 * Status Flags
 ***************************************************************************/

#define STATUS_OK                  0x00000000
#define STATUS_ERROR               0xFFFFFFFF
#define STATUS_BOOT_FAILED         0x00000001
#define STATUS_OUT_OF_MEMORY       0x00000002
#define STATUS_DISK_ERROR          0x00000003
#define STATUS_INVALID_CPU         0x00000004
#define STATUS_EXCEPTION           0x00000005
#define STATUS_IN_PROGRESS         0x00000006

/***************************************************************************
 * API Version
 ***************************************************************************/

#define API_VERSION                1

/***************************************************************************
 * Utility Functions
 * 
 * These are convenience functions for common API operations.
 ***************************************************************************/

/* Check if API is initialized */
static inline int api_is_initialized(void) {
    return GET_MAGIC() == API_MAGIC_NUMBER;
}

/* Get API table pointer with check */
static inline APITable* api_get_table(void) {
    if (!api_is_initialized()) {
        return NULL;
    }
    return GET_APITABLE();
}

/* Get boot info pointer with check */
static inline BootInfo* api_get_bootinfo(void) {
    if (!api_is_initialized()) {
        return NULL;
    }
    return GET_BOOTINFO();
}

/* Safe printf */
static inline void api_printf(const char* format, ...) {
    APITable *api = api_get_table();
    if (api && api->printf) {
        api->printf(format, __builtin_va_arg_pack());
    }
}

/* Safe malloc */
static inline void* api_malloc(size_t size) {
    APITable *api = api_get_table();
    if (api && api->malloc) {
        return api->malloc(size);
    }
    return NULL;
}

/* Safe free */
static inline void api_free(void* ptr) {
    APITable *api = api_get_table();
    if (api && api->free) {
        api->free(ptr);
    }
}

#endif /* __API_H__ */
