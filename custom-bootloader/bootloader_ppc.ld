/***************************************************************************
 * Custom Bootloader - PowerPC Only Linker Script
 * 
 * Linker script for PowerPC-only bootloader build.
 * 
 * Memory Layout for PPC:
 *   0x00000000 : Not used (PPC starts at different address)
 *   0x00000100 : PPC reset vector (standard entry point)
 *   0x00001000 : Exception vectors
 *   0x00100000 : Stack pointer
 *   0x00200000 : API region base
 *   0x01000000 : Alternative entry point (QEMU default load address)
 ***************************************************************************/

MEMORY
{
  /* Text section - PPC typically enters at 0x100 or higher */
  TEXT (rwx) : ORIGIN = 0x00000100, LENGTH = 1M - 256
  
  /* Exception vectors (PPC uses high addresses) */
  VECTORS (rwx) : ORIGIN = 0x00000000, LENGTH = 256
  
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
  
  /* PPC vector table */
  .vectors : { 
    /* PPC reset vector at 0x100 */
    . = 0x100;
    LONG(ppc_entry)
    . = ALIGN(4);
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

ENTRY(ppc_entry)
