|-------------------------------------------------------------------------
| genose.org - Custom Bootloader & Exception Vector Injector
|-------------------------------------------------------------------------
.global _start
.text
.org 0x00000000

_start:
    | 1. Définition des vecteurs d'initialisation initiaux (SP et PC)
    .long   0x00100000          | Stack Pointer (SP) initial à 1 Mo
    .long   main_entry          | Program Counter (PC) initial

main_entry:
    | 2. Masquer toutes les interruptions matérielles (Niveau 7 max)
    move.w  #0x2700, %sr

    | 3. Injecter nos handlers d'exceptions style MacsBug
    move.l  #bus_error_handler, 0x00000008  | Vecteur 2: Bus Error
    move.l  #addr_error_handler, 0x0000000C | Vecteur 3: Address Error
    move.l  #ill_inst_handler, 0x00000010   | Vecteur 4: Illegal Instruction

    | 4. Initialiser la MMU du 68040 si nécessaire (comme Shoebill)
    | (Par défaut, QEMU laisse la MMU transparente au boot)

    | 5. Sauter vers le code principal de ton environnement
    jmp     kernel_main

|-------------------------------------------------------------------------
| Handler d'Exception 68k (Capture du Stack Frame de Type 7 du 68040)
|-------------------------------------------------------------------------
bus_error_handler:
    | Sauvegarder immédiatement les registres de données et d'adresses
    movem.l %d0-%d7/%a0-%a6, -(%sp)
    
    | Sur 68040, le Stack Frame après movem se trouve plus haut.
    | On extrait le Program Counter (PC) fautif pour notre dump
    move.l  60(%sp), %a0        | Adresse du PC qui a crashé (décalage à ajuster)
    
    | Appel à ta routine C/C++ de genose.org pour formater le crash
    jsr     dump_registers_to_gdb
    
    | Si on ne peut pas récupérer, on fige le CPU (MacsBug Loop)
freeze:
    bra     freeze

