/***************************************************************************
 * Custom Bootloader - 68k Only Linker Script
 * 
 * Linker script for 68k-only bootloader build.
 * 
 * Memory Layout for 68k:
 *   0x00000000 : Reset vector (SP)
 *   0x00000004 : Reset vector (PC) -> main_entry
 *   0x00000010 : Vector table (256 bytes for 68k)
 *   0x00000100 : Code start
 *   0x00100000 : Stack pointer initial
 *   0x00200000 : API region base
 ***************************************************************************/

MEMORY
{
  /* Vector table (first 256 bytes) */
  VECTORS (rwx) : ORIGIN = 0x00000000, LENGTH = 256
  
  /* Text section (code) */
  TEXT (rwx) : ORIGIN = 0x00000100, LENGTH = 1M - 256
  
  /* Data section */
  DATA (rwx) : ORIGIN = 0x00100000, LENGTH = 64K
  
  /* API region */
  API (rwx) : ORIGIN = 0x00200000, LENGTH = 64K
  
  /* Stack */
  STACK (rwx) : ORIGIN = 0x00300000, LENGTH = 64K
}

SECTIONS
{
  . = 0x00000000;
  
  /* Vector table must be at address 0 */
  .vectors : { 
    LONG(0x00100000)        /* Initial SP */
    LONG(main_entry)        /* Initial PC */
    . = ALIGN(4);
    /* Reserve rest of vector table */
    . = 0x100;
  } > VECTORS
  
  /* Text section */
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
  
  /* Stack */
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
  
  /* Discard debug sections */
  /DISCARD/ : {
    *(.note)
    *(.comment)
    *(.debug*)
    *(.gnu*)
    *(.eh_frame*)
  }
}

ENTRY(_start)
