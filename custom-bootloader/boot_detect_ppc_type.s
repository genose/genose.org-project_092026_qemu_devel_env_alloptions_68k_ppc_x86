.engine_ppc:
    # Lire le Processor Version Register (PVR) dans le registre R3
    mfspr   3, 287                # 287 est l'adresse du SPR pour le PVR
    
    # Extraire les 16 bits de poids fort (Processor Version)
    rlwinm  4, 3, 16, 16, 31
    
    # Comparaison avec les signatures IBM/Motorola connues
    cmplwi  4, 0x0001             # 0x0001 = PowerPC 601
    beq     .ppc_601_found
    
    cmplwi  4, 0x0004             # 0x0004 = PowerPC 604
    beq     .ppc_604_found
    
    # Valeurs par défaut si G3/G4 (émulation mac99)
    b       .ppc_generic

.ppc_601_found:
    li      7, 101                # ID CPU = 101 (PPC 601)
    b       .setup_ppc_exception_vectors

