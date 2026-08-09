/***************************************************************************
 * Custom Bootloader - FATBIN Linker Script
 * 
 * Linker script for the universal FATBIN bootloader that contains both
 * 68k and PowerPC code in a single binary.
 * 
 * Memory Layout:
 *   0x00000000 - 0x0000FFFF : 68k vectors and code
 *   0x00010000 - 0x001FFFFF : Shared data and API
 *   0x00200000 - 0x002FFFFF : API region (fixed addresses)
 *   0x00300000 - 0x003FFFFF : Stack area
 *   0x01000000 +           : PPC code entry point
 ***************************************************************************/

MEMORY
{
  /* 68k code and vectors (first 64KB) */
  VECTORS (rwx) : ORIGIN = 0x00000000, LENGTH = 256K
  
  /* Code section */
  TEXT (rwx) : ORIGIN = 0x00000100, LENGTH = 1M - 256
  
  /* Data section */
  DATA (rwx) : ORIGIN = 0x00100000, LENGTH = 64K
  
  /* API region (fixed addresses) */
  API (rwx) : ORIGIN = 0x00200000, LENGTH = 64K
  
  /* Stack area */
  STACK (rwx) : ORIGIN = 0x00300000, LENGTH = 64K
  
  /* PPC entry at 0x100 for compatibility */
  PPC_ENTRY (rwx) : ORIGIN = 0x00000100, LENGTH = 4K
}

SECTIONS
{
  . = 0x00000000;
  
  /* Reset vector at address 0 */
  .vectors : { 
    *(.vectors)
    . = ALIGN(4);
  } > VECTORS
  
  /* Text section at 0x100 */
  .text : { 
    *(.text)
    *(.text.*)
    . = ALIGN(4);
  } > TEXT
  
  /* Read-only data */
  .rodata : { 
    *(.rodata)
    *(.rodata.*)
    . = ALIGN(4);
  } > TEXT
  
  /* Data section */
  .data : { 
    *(.data)
    *(.data.*)
    . = ALIGN(4);
  } > DATA
  
  /* BSS section */
  .bss : { 
    *(.bss)
    *(.bss.*)
    *(COMMON)
    . = ALIGN(4);
  } > DATA
  
  /* Stack section */
  .stack : { 
    *(.stack)
    . = ALIGN(4);
  } > STACK
  
  /* API section at fixed addresses */
  .api : { 
    . = 0x00200000;
    *(.api)
    . = ALIGN(4);
  } > API
  
  /* Discard debug sections for release build */
  /DISCARD/ : {
    *(.note)
    *(.comment)
    *(.debug*)
    *(.gnu*)
    *(.eh_frame*)
  }
}

ENTRY(_start)
