/***************************************************************************
 * Custom Bootloader - Configuration Header
 * 
 * Universal FATBIN bootloader for 68k and PowerPC architectures
 * 
 * This file contains system-wide constants, CPU definitions, and configuration
 * options for the custom bootloader.
 ***************************************************************************/

#ifndef __CONFIG_H__
#define __CONFIG_H__

/***************************************************************************
 * Version Information
 ***************************************************************************/

#define BOOTLOADER_VERSION_MAJOR    1
#define BOOTLOADER_VERSION_MINOR    0
#define BOOTLOADER_VERSION_PATCH    0
#define BOOTLOADER_VERSION_STRING   "1.0.0"
#define BOOTLOADER_BUILD_DATE       __DATE__

/***************************************************************************
 * Memory Layout Constants
 ***************************************************************************/

/* Boot ROM / Vector Area */
#define BOOT_ROM_BASE               0x00000000
#define BOOT_ROM_SIZE               0x00100000  /* 1MB */

/* Bootloader Code/Data Area */
#define BOOTLOADER_BASE             0x00100000
#define BOOTLOADER_SIZE             0x00100000  /* 1MB */

/* API Region (Fixed addresses for developer API) */
#define API_REGION_BASE             0x00200000
#define API_REGION_SIZE             0x00010000  /* 64KB */

/* Address for API pointers */
#define BOOTINFO_PTR_ADDRESS         0x00002000
#define APPVECTORS_PTR_ADDRESS       0x00002004
#define APITABLE_PTR_ADDRESS         0x00002008
#define API_STATUS_FLAGS_ADDRESS     0x0000200C
#define API_MAGIC_NUMBER_ADDRESS     0x00002010

/* Magic Number for API validation */
#define API_MAGIC_NUMBER            0xDEADBEEF

/* Available RAM */
#define RAM_BASE                    0x01000000
#define RAM_SIZE_DEFAULT            (128 * 1024 * 1024)  /* 128MB */

/* Stack Configuration */
#define BOOT_STACK_BASE             0x00100000  /* 1MB */
#define BOOT_STACK_SIZE             0x00010000  /* 64KB */

/* Kernel/OS Loading Area */
#define KERNEL_LOAD_BASE            0x01000000
#define KERNEL_LOAD_SIZE            (128 * 1024 * 1024)  /* 128MB */

/***************************************************************************
 * GDB Debug Points
 ***************************************************************************/

#define GDB_BREAKPOINT_ADDRESS      0x00001000
#define GDB_STATUS_ADDRESS          0x00001004

/* Status codes */
#define STATUS_SUCCESS              0x00000000
#define STATUS_BOOT_FAILED          0x00000001
#define STATUS_OUT_OF_MEMORY        0x00000002
#define STATUS_DISK_ERROR           0x00000003
#define STATUS_INVALID_CPU          0x00000004
#define STATUS_EXCEPTION            0x00000005

/***************************************************************************
 * CPU Type Definitions
 * 
 * These define the CPU identifiers used throughout the bootloader.
 * Values are chosen to be unique and easily distinguishable.
 ***************************************************************************/

/*** 68k Family ***/
#define CPU_ID_68000               1
#define CPU_ID_68010               2
#define CPU_ID_68020               3
#define CPU_ID_68030               4
#define CPU_ID_68040               5
#define CPU_ID_68060               6

/*** PowerPC Family ***/
#define CPU_ID_PPC601              101
#define CPU_ID_PPC603              103
#define CPU_ID_PPC604              104
#define CPU_ID_PPC750              108
#define CPU_ID_PPC7410             112
#define CPU_ID_PPC7455             140
#define CPU_ID_PPC970              153

/*** Generic/Unknown ***/
#define CPU_ID_UNKNOWN             0
#define CPU_ID_GENERIC             255

/***************************************************************************
 * CPU Feature Flags
 * 
 * Bitmask values for CPU feature detection.
 ***************************************************************************/

/*** 68k Features ***/
#define CPU_FEATURE_68K_32BIT       (1 << 0)   /* 32-bit addressing support */
#define CPU_FEATURE_68K_VBR         (1 << 1)   /* Vector Base Register */
#define CPU_FEATURE_68K_MMU         (1 << 2)   /* Memory Management Unit */
#define CPU_FEATURE_68K_CACHE       (1 << 3)   /* Cache support */
#define CPU_FEATURE_68K_BURST       (1 << 4)   /* Burst mode support */
#define CPU_FEATURE_68K_TYPE7       (1 << 5)   /* Type 7 stack frames */
#define CPU_FEATURE_68K_FPU         (1 << 6)   /* Floating Point Unit */

/*** PPC Features ***/
#define CPU_FEATURE_PPC_64BIT       (1 << 16)  /* 64-bit mode support */
#define CPU_FEATURE_PPC_ALTIVEC     (1 << 17)  /* AltiVec support */
#define CPU_FEATURE_PPC_SMP         (1 << 18)  /* Symmetric Multiprocessing */
#define CPU_FEATURE_PPC_MMU         (1 << 19)  /* Memory Management Unit */
#define CPU_FEATURE_PPC_FPU         (1 << 20)  /* Floating Point Unit */

/*** Common Feature Masks ***/
#define CPU_FEATURE_MMU             (CPU_FEATURE_68K_MMU | CPU_FEATURE_PPC_MMU)
#define CPU_FEATURE_FPU             (CPU_FEATURE_68K_FPU | CPU_FEATURE_PPC_FPU)

/***************************************************************************
 * Boot Device Definitions
 ***************************************************************************/

#define BOOT_DEVICE_NONE            0
#define BOOT_DEVICE_FLOPPY          1
#define BOOT_DEVICE_HD               2
#define BOOT_DEVICE_CD               3
#define BOOT_DEVICE_NETWORK          4
#define BOOT_DEVICE_USB              5
#define BOOT_DEVICE_DEFAULT          255

/***************************************************************************
 * PPC Processor Version Register (PVR) Values
 * 
 * These are the high 16 bits of the PVR that identify the processor version.
 ***************************************************************************/

#define PVR_PPC601                  0x0001
#define PVR_PPC603                  0x0003
#define PVR_PPC604                  0x0004
#define PVR_PPC750                  0x0008
#define PVR_PPC7410                 0x000C
#define PVR_PPC7455                 0x800C
#define PVR_PPC970                  0x0039

/***************************************************************************
 * Exception Vector Definitions
 * 
 * Standard exception vectors for 68k and PPC architectures.
 ***************************************************************************/

/*** 68k Exception Vectors (0x00 - 0xFF) ***/
#define VECTOR_RESET                0x00
#define VECTOR_BUS_ERROR            0x02
#define VECTOR_ADDRESS_ERROR        0x03
#define VECTOR_ILLEGAL_INSTR        0x04
#define VECTOR_ZERO_DIVIDE          0x05
#define VECTOR_CHK_TRAP             0x06
#define VECTOR_TRAPV                0x07
#define VECTOR_PRIVILEGE_VIOLATION  0x08
#define VECTOR_TRACE                0x09
#define VECTOR_LINE_A               0x0A
#define VECTOR_LINE_F               0x0B
#define VECTORRESERVED_0C           0x0C
#define VECTOR_COPROC_VIOLATION     0x0D
#define VECTORRESERVED_0E           0x0E
#define VECTOR_FORMAT_ERROR         0x0F
#define VECTOR_UNINITIALIZED_INT    0x10

/* Level 1-7 Interrupts */
#define VECTOR_INTERRUPT_1         0x18
#define VECTOR_INTERRUPT_2         0x19
#define VECTOR_INTERRUPT_3         0x1A
#define VECTOR_INTERRUPT_4         0x1B
#define VECTOR_INTERRUPT_5         0x1C
#define VECTOR_INTERRUPT_6         0x1D
#define VECTOR_INTERRUPT_7         0x1E

#define VECTOR_SPURIOUS            0x1F
#define VECTOR_TRAP_0              0x20
#define VECTOR_TRAP_1              0x21
#define VECTOR_TRAP_2              0x22
#define VECTOR_TRAP_3              0x23
#define VECTOR_TRAP_4              0x24
#define VECTOR_TRAP_5              0x25
#define VECTOR_TRAP_6              0x26
#define VECTOR_TRAP_7              0x27
#define VECTOR_TRAP_8              0x28
#define VECTOR_TRAP_9              0x29
#define VECTOR_TRAP_10             0x2A
#define VECTOR_TRAP_11             0x2B
#define VECTOR_TRAP_12             0x2C
#define VECTOR_TRAP_13             0x2D
#define VECTOR_TRAP_14             0x2E
#define VECTOR_TRAP_15             0x2F

/*** PPC Exception Vectors ***/
#define PPC_VECTOR_RESET            0x0100
#define PPC_VECTOR_MACHINE_CHECK     0x0200
#define PPC_VECTOR_DSI              0x0300
#define PPC_VECTOR_ISI              0x0400
#define PPC_VECTOR_EXTERNAL         0x0500
#define PPC_VECTOR_ALIGNMENT        0x0600
#define PPC_VECTOR_PROGRAM          0x0700
#define PPC_VECTOR_FP_UNAVAILABLE    0x0800
#define PPC_VECTOR_DECREMENTER      0x0900
#define PPC_VECTOR_SYSCALL          0x0C00
#define PPC_VECTOR_TRACE            0x0D00
#define PPC_VECTOR_FP_ASSIST        0x0E00
#define PPC_VECTOR_PERFORMANCE      0x0F00
#define PPC_VECTOR_INFO             0x1000
#define PPC_VECTOR_SMI              0x1400

/***************************************************************************
 * PPC Special Purpose Registers (SPR) Numbers
 ***************************************************************************/

#define SPR_PVR                    287     /* Processor Version Register */
#define SPR_SRR0                   26      /* Save/Restore Register 0 */
#define SPR_SRR1                   27      /* Save/Restore Register 1 */
#define SPR_MSR                    123     /* Machine State Register */
#define SPR_DSISR                  18      /* Data Storage Interrupt Status */
#define SPR_DAR                    19      /* Data Address Register */
#define SPR_DEAR                   61      /* Data Error Address Register */
#define SPR_ESR                    62      /* Exception Syndrome Register */
#define SPR_PIR                    286     /* Processor Identification Register */

/***************************************************************************
 * Backtrace Configuration
 ***************************************************************************/

#define BACKTRACE_MAX_FRAMES       100
#define BACKTRACE_SHOW_SYMBOLS      1
#define BACKTRACE_SHOW_REGS        1

/***************************************************************************
 * Serial Console Configuration
 ***************************************************************************/

#define SERIAL_BAUD_RATE           115200
#define SERIAL_DATA_BITS           8
#define SERIAL_STOP_BITS           1
#define SERIAL_PARITY              0  /* 0 = none, 1 = odd, 2 = even */

/***************************************************************************
 * Build Configuration Options
 * 
 * These can be overridden on the compiler command line.
 ***************************************************************************/

/*** Debug Options ***/
#define DEBUG                      1    /* Enable debug output */
#define DEBUG_VERBOSE              0    /* Enable verbose debug output */
#define DEBUG_SERIAL               1    /* Enable serial debug output */
#define GDB_BREAKPOINT             1    /* Enable GDB breakpoint at 0x1000 */

/*** Build Type ***/
#define BUILD_DEBUG                0    /* Debug build */
#define BUILD_RELEASE              1    /* Release build (optimized for size) */
#define BUILD_TYPE                 BUILD_DEBUG

/*** Target Architecture ***/
#define TARGET_68K                 0    /* Build for 68k only */
#define TARGET_PPC                 0    /* Build for PPC only */
#define TARGET_FATBIN              1    /* Build FATBIN for both */
#define TARGET_DEFAULT             TARGET_FATBIN

/*** Optimization ***/
#define OPTIMIZE_SIZE             1    /* Optimize for size */
#define OPTIMIZE_SPEED            0    /* Optimize for speed */

/***************************************************************************
 * Standard Messages
 * 
 * These are the standardized messages displayed during boot.
 * They should be used consistently throughout the bootloader.
 ***************************************************************************/

#define MSG_LOADING                "Loading ...\r\n"
#define MSG_RUNNING(cpu_name)      cpu_name " running ...\r\n"
#define MSG_BOOT_OS                "Boot OS ...\r\n"
#define MSG_FAILURE(code)          "Failure (code 0x%02X)\r\n"

/*** CPU Name Strings ***/
#define CPU_NAME_68000             "Motorola 68000"
#define CPU_NAME_68010             "Motorola 68010"
#define CPU_NAME_68020             "Motorola 68020"
#define CPU_NAME_68030             "Motorola 68030"
#define CPU_NAME_68040             "Motorola 68040"
#define CPU_NAME_68060             "Motorola 68060"
#define CPU_NAME_PPC601            "PowerPC 601"
#define CPU_NAME_PPC603            "PowerPC 603"
#define CPU_NAME_PPC604            "PowerPC 604"
#define CPU_NAME_PPC750            "PowerPC 750 (G3)"
#define CPU_NAME_PPC7410           "PowerPC 7410 (G4)"
#define CPU_NAME_PPC7455           "PowerPC 7455 (G4 Enhanced)"
#define CPU_NAME_PPC970            "PowerPC 970 (G5)"
#define CPU_NAME_UNKNOWN           "Unknown CPU"

/***************************************************************************
 * Utility Macros
 ***************************************************************************/

/*** Alignment Macros ***/
#define ALIGN_UP(addr, align)      (((addr) + (align) - 1) & ~((align) - 1))
#define ALIGN_DOWN(addr, align)    ((addr) & ~((align) - 1))

/*** Bit Manipulation ***/
#define BIT(n)                    (1 << (n))
#define SET_BIT(var, n)           ((var) | BIT(n))
#define CLR_BIT(var, n)           ((var) & ~BIT(n))
#define TST_BIT(var, n)           ((var) & BIT(n))

/*** Byte Swapping ***/
#define SWAP16(x)                 ((((x) & 0xFF00) >> 8) | (((x) & 0x00FF) << 8))
#define SWAP32(x)                 ((((x) & 0xFF000000) >> 24) | \
                                  (((x) & 0x00FF0000) >> 8) | \
                                  (((x) & 0x0000FF00) << 8) | \
                                  (((x) & 0x000000FF) << 24))

/*** Stringification ***/
#define STRINGIFY(x)              #x
#define TOSTRING(x)               STRINGIFY(x)

/*** Offset Of ***/
#define offsetof(type, field)     ((size_t)&((type *)0)->field)

#endif /* __CONFIG_H__ */
