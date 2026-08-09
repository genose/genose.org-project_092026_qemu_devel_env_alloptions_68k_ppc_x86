determine_68k_generation:
    move.w  #0x2700, %sr          # Masquer les interruptions

    # --- ÉTAPE 1 : Séparer le 68000 du 68020+ ---
    # On tente de modifier un registre de contrôle qui n'existe qu'à partir du 68010/020 (ex: VBR)
    # Si on est sur un 68000 pur, l'instruction "movec" provoque une Illegal Instruction.
    lea     trap_68000_detected(%pc), %a0
    move.l  %a0, 0x00000010       # Installe le handler temporaire d'instruction illégale (Vecteur 4)
    
    # Instruction test : Lire le Vector Base Register (n'existe pas sur 68000)
    .word   0x4e7a, 0x0801        # Opcode brut pour: movec vbr, d0
    
    # Si on arrive ici, on est AU MOINS sur un 68010/68020/68030/68040
    bra.s   check_if_68040

trap_68000_detected:
    # Log: "CPU: Motorola 68000" -> Charger MacOS (Système 6 / 7.0)
    move.l  #1, %d7               # ID CPU = 1 (68000)
    bra     load_macos_classic

check_if_68040:
    # --- ÉTAPE 2 : Séparer le 68030 du 68040 ---
    # Le 68040 possède un registre CACR (Cache Control Register) avec des bits différents du 68030.
    # Mais le moyen le plus sûr est d'exécuter une instruction exclusive au 68040 : "NOP" de cache (CPUSH)
    lea     trap_68030_detected(%pc), %a0
    move.l  %a0, 0x00000010       # Réinstalle le handler d'instruction illégale
    
    # Instruction exclusive au 68040 : cpusha dc (Invalider le cache de données)
    .word   0xf478                # Opcode de CPUSHA Data Cache
    
    # Si on arrive ici sans crasher, on est sur un 68040 (ou 68060)
    move.l  #3, %d7               # ID CPU = 3 (68040)
    bra     setup_68040_exception_frames

trap_68030_detected:
    # Si l'instruction CPUSHA a levé une exception, on a affaire à un 68020 ou 68030
    move.l  #2, %d7               # ID CPU = 2 (68030)
    bra     setup_68030_exception_frames

