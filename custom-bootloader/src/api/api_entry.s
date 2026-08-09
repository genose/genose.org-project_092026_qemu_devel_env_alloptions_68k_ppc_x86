/***************************************************************************
 * API Entry Point
 * Initializes the API table with function pointers
 ***************************************************************************/

#include "config.h"

    .global init_api_table
    .text

init_api_table:
    /* Set up APITable with function pointers */
    lis 3, api_table@h
    ori 3, 3, api_table@l
    
    /* Memory operations */
    lis 4, malloc@h
    ori 4, 4, malloc@l
    stw 4, offsetof(APITable, malloc)(3)
    
    lis 4, free@h
    ori 4, 4, free@l
    stw 4, offsetof(APITable, free)(3)
    
    lis 4, memcpy@h
    ori 4, 4, memcpy@l
    stw 4, offsetof(APITable, memcpy)(3)
    
    lis 4, memset@h
    ori 4, 4, memset@l
    stw 4, offsetof(APITable, memset)(3)
    
    /* String operations */
    lis 4, strcpy@h
    ori 4, 4, strcpy@l
    stw 4, offsetof(APITable, strcpy)(3)
    
    lis 4, strlen@h
    ori 4, 4, strlen@l
    stw 4, offsetof(APITable, strlen)(3)
    
    /* Debug operations */
    lis 4, printf@h
    ori 4, 4, printf@l
    stw 4, offsetof(APITable, printf)(3)
    
    lis 4, hexdump@h
    ori 4, 4, hexdump@l
    stw 4, offsetof(APITable, hexdump)(3)
    
    lis 4, backtrace@h
    ori 4, 4, backtrace@l
    stw 4, offsetof(APITable, backtrace)(3)
    
    lis 4, dump_registers@h
    ori 4, 4, dump_registers@l
    stw 4, offsetof(APITable, dump_registers)(3)
    
    /* CPU operations */
    lis 4, cpu_halt@h
    ori 4, 4, cpu_halt@l
    stw 4, offsetof(APITable, cpu_halt)(3)
    
    lis 4, cpu_reboot@h
    ori 4, 4, cpu_reboot@l
    stw 4, offsetof(APITable, cpu_reboot)(3)
    
    lis 4, cpu_get_id@h
    ori 4, 4, cpu_get_id@l
    stw 4, offsetof(APITable, cpu_get_id)(3)
    
    /* Set APITable pointer */
    lis 3, api_table@h
    ori 3, 3, api_table@l
    lis 4, APITABLE_PTR_ADDRESS@h
    ori 4, 4, APITABLE_PTR_ADDRESS@l
    stw 3, 0(4)
    
    blr
