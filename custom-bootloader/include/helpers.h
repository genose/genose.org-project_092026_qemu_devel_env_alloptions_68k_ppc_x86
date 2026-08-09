/***************************************************************************
 * Custom Bootloader - Helper Functions Header
 * 
 * This file declares all helper functions available in the bootloader.
 * These functions provide common operations for string manipulation,
 * memory operations, debugging, and more.
 ***************************************************************************/

#ifndef __HELPERS_H__
#define __HELPERS_H__

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
 * Standard Messages
 * 
 * These are the standardized message strings used throughout the bootloader.
 * They are defined as macros to allow for easy customization and localization.
 ***************************************************************************/

#define MSG_LOADING                "Loading ...\r\n"
#define MSG_68000_RUNNING          "Motorola 68000 running ...\r\n"
#define MSG_68010_RUNNING          "Motorola 68010 running ...\r\n"
#define MSG_68020_RUNNING          "Motorola 68020 running ...\r\n"
#define MSG_68030_RUNNING          "Motorola 68030 running ...\r\n"
#define MSG_68040_RUNNING          "Motorola 68040 running ...\r\n"
#define MSG_68060_RUNNING          "Motorola 68060 running ...\r\n"
#define MSG_PPC601_RUNNING         "PowerPC 601 running ...\r\n"
#define MSG_PPC603_RUNNING         "PowerPC 603 running ...\r\n"
#define MSG_PPC604_RUNNING         "PowerPC 604 running ...\r\n"
#define MSG_PPC750_RUNNING         "PowerPC 750 (G3) running ...\r\n"
#define MSG_PPC7410_RUNNING        "PowerPC 7410 (G4) running ...\r\n"
#define MSG_PPC7455_RUNNING        "PowerPC 7455 (G4 Enhanced) running ...\r\n"
#define MSG_PPC970_RUNNING         "PowerPC 970 (G5) running ...\r\n"
#define MSG_UNKNOWN_RUNNING        "Unknown CPU running ...\r\n"
#define MSG_BOOT_OS                "Boot OS ...\r\n"
#define MSG_FAILURE               "\r\nFailure (code 0x%02X)\r\n"

/***************************************************************************
 * String Helper Function Declarations
 * 
 * C-style string operations optimized for the target architectures.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Copy string */
char* strcpy(char* dest, const char* src);

/* Copy string with length limit */
char* strncpy(char* dest, const char* src, size_t n);

/* Concatenate strings */
char* strcat(char* dest, const char* src);

/* Concatenate strings with length limit */
char* strncat(char* dest, const char* src, size_t n);

/* String length */
size_t strlen(const char* s);

/* Compare strings */
int strcmp(const char* s1, const char* s2);

/* Compare strings with length limit */
int strncmp(const char* s1, const char* src, size_t n);

/* Case-insensitive string compare */
int strcasecmp(const char* s1, const char* s2);

/* Case-insensitive string compare with length limit */
int strncasecmp(const char* s1, const char* s2, size_t n);

/* Find first occurrence of character in string */
char* strchr(const char* s, int c);

/* Find last occurrence of character in string */
char* strrchr(const char* s, int c);

/* Find substring */
char* strstr(const char* haystack, const char* needle);

/* Duplicate string */
char* strdup(const char* s);

/* Compare memory */
int memcmp(const void* s1, const void* s2, size_t n);

/* Find character in memory */
void* memchr(const void* s, int c, size_t n);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * Memory Helper Function Declarations
 * 
 * Memory operations optimized for the target architectures.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Copy memory */
void* memcpy(void* dest, const void* src, size_t n);

/* Move memory (handles overlap) */
void* memmove(void* dest, const void* src, size_t n);

/* Fill memory */
void* memset(void* s, int c, size_t n);

/* Zero memory */
void bzero(void* s, size_t n);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * Debug Helper Function Declarations
 * 
 * Debugging output and memory examination functions.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Formatted output to console */
void printf(const char* format, ...);

/* Formatted output to string */
void sprintf(char* str, const char* format, ...);

/* Formatted output with va_list */
void vsprintf(char* str, const char* format, void* ap);

/* Output character */
int putchar(int c);

/* Output string */
int puts(const char* s);

/* Get character */
int getchar(void);

/* Get string */
char* gets(char* s);

/* Hex dump memory */
void hexdump(void* addr, size_t len);

/* Dump memory with custom width */
void dump_memory(void* addr, size_t len, int width);

/* Dump CPU registers */
void dump_registers(void);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * Math Helper Function Declarations
 * 
 * Common mathematical operations.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Absolute value */
int abs(int n);

/* Long absolute value */
long labs(long n);

/* Minimum value */
int min(int a, int b);

/* Maximum value */
int max(int a, int b);

/* Swap 16-bit endianness */
uint16_t swap16(uint16_t value);

/* Swap 32-bit endianness */
uint32_t swap32(uint32_t value);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * Conversion Helper Function Declarations
 * 
 * Data type conversions.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Integer to ASCII */
char* itoa(int value, char* str, int base);

/* Unsigned integer to ASCII */
char* utoa(unsigned int value, char* str, int base);

/* String to integer */
int atoi(const char* str);

/* String to unsigned long */
unsigned long strtoul(const char* str, char** endptr, int base);

/* Output hexadecimal value */
void puthex(uint32_t value, int width);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * I/O Helper Function Declarations
 * 
 * Input/Output operations.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Initialize console */
void console_init(void);

/* Output character to console */
void console_putc(char c);

/* Get character from console */
char console_getc(void);

/* Output string to console */
void console_puts(const char* s);

/* Output buffer to console */
void console_write(const void* buf, size_t len);

/* Read from console */
int console_read(void* buf, size_t len);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * CPU Helper Function Declarations
 * 
 * CPU-specific operations.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Halt CPU */
void cpu_halt(void);

/* Reboot system */
void cpu_reboot(void);

/* Enter idle state */
void cpu_idle(void);

/* Get CPU ID */
uint32_t cpu_get_id(void);

/* Get PPC PVR */
uint32_t cpu_get_pvr(void);

/* Set interrupt state */
void cpu_set_irq(int enable);

/* Get interrupt state */
uint32_t cpu_get_irq(void);

/* Disable cache */
void cpu_disable_cache(void);

/* Enable cache */
void cpu_enable_cache(void);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * Backtrace Function Declarations
 * 
 * Stack walking and backtrace functions.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Print backtrace */
void backtrace(void);

/* 68k-specific backtrace */
void backtrace_68k(void);

/* PPC-specific backtrace */
void backtrace_ppc(void);

/* Look up symbol for address */
const char* lookup_symbol(uint32_t addr);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * Memory Management Function Declarations
 * 
 * Heap and memory management functions.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Initialize heap */
void heap_init(void* start, size_t size);

/* Allocate memory from heap */
void* heap_alloc(size_t size);

/* Free memory from heap */
void heap_free(void* ptr);

/* Get free heap size */
size_t heap_get_free(void);

/* Kernel malloc */
void* kmalloc(size_t size);

/* Kernel free */
void kfree(void* ptr);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * Disk Helper Function Declarations
 * 
 * Disk I/O operations.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Open disk device */
int disk_open(uint32_t device);

/* Read from disk */
int disk_read(uint32_t device, uint64_t lba, void* buf, size_t count);

/* Write to disk */
int disk_write(uint32_t device, uint64_t lba, const void* buf, size_t count);

/* Close disk device */
int disk_close(uint32_t device);

/* Get disk info */
int disk_get_info(uint32_t device, uint32_t *sector_size, uint64_t *total_sectors);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * Timer Helper Function Declarations
 * 
 * Time and delay functions.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Get ticks since boot */
uint32_t timer_get_ticks(void);

/* Delay for specified milliseconds */
void timer_delay(uint32_t ms);

/* Get milliseconds since boot */
uint32_t timer_get_millis(void);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * Assembly Helper Function Declarations
 * 
 * Low-level functions that must be implemented in assembly.
 ***************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

/* Input byte from port (x86) */
uint8_t inb(uint16_t port);

/* Output byte to port (x86) */
void outb(uint16_t port, uint8_t value);

/* Input word from port (x86) */
uint16_t inw(uint16_t port);

/* Output word to port (x86) */
void outw(uint16_t port, uint16_t value);

/* Disable interrupts */
void cli(void);

/* Enable interrupts */
void sti(void);

/* Save and disable interrupts */
unsigned long save_flags(void);

/* Restore interrupts */
void restore_flags(unsigned long flags);

#ifdef __cplusplus
}
#endif

/***************************************************************************
 * Inline Helper Functions
 * 
 * Small helper functions that can be inlined for performance.
 ***************************************************************************/

/* Check if character is a digit */
static inline int isdigit(int c) {
    return (c >= '0' && c <= '9');
}

/* Check if character is a hex digit */
static inline int isxdigit(int c) {
    return ((c >= '0' && c <= '9') ||
            (c >= 'a' && c <= 'f') ||
            (c >= 'A' && c <= 'F'));
}

/* Check if character is uppercase */
static inline int isupper(int c) {
    return (c >= 'A' && c <= 'Z');
}

/* Check if character is lowercase */
static inline int islower(int c) {
    return (c >= 'a' && c <= 'z');
}

/* Convert to uppercase */
static inline int toupper(int c) {
    return (c >= 'a' && c <= 'z') ? c - 32 : c;
}

/* Convert to lowercase */
static inline int tolower(int c) {
    return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

/* Get high byte of 16-bit value */
static inline uint8_t hi8(uint16_t value) {
    return (uint8_t)(value >> 8);
}

/* Get low byte of 16-bit value */
static inline uint8_t lo8(uint16_t value) {
    return (uint8_t)value;
}

/* Make 16-bit value from high and low bytes */
static inline uint16_t mk16(uint8_t hi, uint8_t lo) {
    return ((uint16_t)hi << 8) | lo;
}

/* Get high word of 32-bit value */
static inline uint16_t hi16(uint32_t value) {
    return (uint16_t)(value >> 16);
}

/* Get low word of 32-bit value */
static inline uint16_t lo16(uint32_t value) {
    return (uint16_t)value;
}

/* Make 32-bit value from high and low words */
static inline uint32_t mk32(uint16_t hi, uint16_t lo) {
    return ((uint32_t)hi << 16) | lo;
}

#endif /* __HELPERS_H__ */
