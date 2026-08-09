# 🚀 Spécifications du Bootloader Universel (genose.org)

## Objectif
Détecter dynamiquement l'architecture matérielle injectée par l'hyperviseur QEMU avant l'initialisation du MacOS System Folder.

## Ordre de Traitement Matériel
1. Piège d'exception sur `movec vbr` ➔ Si échec = CPU 68000 (Activation profil System 6/7)
2. Piège d'exception sur `cpusha` ➔ Si échec = CPU 68030 (Activation profil Mac II/Classic II)
3. Succès des opcodes 68k ➔ CPU 68040 (Activation profil Quadra 800)
4. Lecture du registre `PVR` (SPR 287) ➔ Détermination de la variante PowerPC (601/604/G3)

## Règles de Merge pour les Agents
Ne jamais modifier les opcodes hexadécimaux bruts des instructions de tests (`.word 0xf478`) sans valider la conformité avec le manuel de référence Motorola Microprocessor.

