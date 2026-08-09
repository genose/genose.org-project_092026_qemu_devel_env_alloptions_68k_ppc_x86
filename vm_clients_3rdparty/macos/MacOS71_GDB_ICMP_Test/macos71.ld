/*
 * macos71.ld - Linker script for Mac OS 7.1 classic applications
 * 
 * This is a simplified linker script for creating Mac OS classic executables.
 * Note: For real Mac OS development, you would use MPW (Macintosh Programmer's Workshop)
 * or CodeWarrior with their specific build systems.
 */

/* Mac OS classic applications have a specific structure:
 * - CODE resource (executable code)
 * - DATA resource (initialized data)
 * - Application header
 */

/* Memory layout for 68k */
#if defined(__mc68k__)

MEMORY
{
    /* System memory (read-only) */
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 4M
    
    /* Application memory */
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 8M
}

SECTIONS
{
    .text : 
    {
        *(.text*)
        *(.rodata*)
        *(.glue_7)
        *(.glue_7t)
    } > ROM
    
    .data : 
    {
        *(.data*)
        *(.bss*)
        *(COMMON)
    } > RAM
    
    /* Mac OS application header */
    .header : 
    {
        LONG(0x00000000) /* reserved */
        LONG(0x00000000) /* nextApp */
        LONG(0x00000000) /* fileType */
        LONG(0x00000000) /* sysEnv */
        LONG(0x00000000) /* resourceMap */
    } > RAM
}

/* Memory layout for PowerPC */
#elif defined(__ppc__) || defined(__PPC__)

MEMORY
{
    /* System memory */
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 4M
    
    /* Application memory */
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 8M
}

SECTIONS
{
    .text : 
    {
        *(.text*)
        *(.rodata*)
        *(.glue_7)
        *(.glue_7t)
    } > ROM
    
    .data : 
    {
        *(.data*)
        *(.bss*)
        *(COMMON)
    } > RAM
}

#else

/* Generic layout */
MEMORY
{
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 4M
    RAM (rwx) : ORIGIN = 0x00400000, LENGTH = 4M
}

SECTIONS
{
    .text : { *(.text*) } > ROM
    .rodata : { *(.rodata*) } > ROM
    .data : { *(.data*) } > RAM
    .bss : { *(.bss*) } > RAM
}

#endif

/* Entry point - Mac OS applications typically start at main() */
ENTRY(main)
