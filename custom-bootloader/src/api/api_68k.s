/***************************************************************************
 * 68k-specific API functions
 ***************************************************************************/

#include "config.h"

    .global api_68k_init
    .text

api_68k_init:
    /* Initialize 68k-specific API entries */
    blr
