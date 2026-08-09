.section .text
.global _start

_start:
    # Si nous sommes sur un CPU m68k, l'exécution commence ici via le vecteur PC
    bra.s    determine_68k_generation

    # Zone tampon alignée lue par le PPC ou le reste du système
    .align 4

