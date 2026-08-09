# 🤖 CONTEXT NODE: UNIVERSAL FAT-BOOTLOADER ARCHITECTURE (68k ➔ PPC)

## 📌 Objectif du Fichier
Ce document définit la logique d'exécution et les invariants stricts du **Bootloader Universel Multi-Architecture** pour le projet `genose.org`. Ce programme s'exécute en mode `freestanding` (nu, sans OS) directement injecté via l'argument `-kernel` de QEMU. Sa mission est de détecter dynamiquement le CPU émulé avant de passer proprement le contrôle à la ROM de Mac OS Classic.

Tout agent travaillant sur une branche `feature/*` doit lire et maintenir les invariants décrits ci-dessous.

---

## 🧭 Cinématique et Cascade de Détection

L'exécution suit une logique de tolérance aux pannes matérielles. Les architectures supérieures sont identifiées en déclenchant volontairement des instructions inconnues, interceptées par un gestionnaire de trappes temporaire (Vecteur 4 : `Illegal Instruction`).



[BOOT IN RAM]│├──► (Si CPU PPC) ──► Lecture PVR (SPR 287) ──► ID: 601 / 604 / G3│└──► (Si CPU 68k) ──► Test instruction 'movec'│├──► [Échec / Trap V4] ──► ID: 68000└──► [Succès] ──► Test 'cpusha'│├──► [Échec / Trap V4] ──► ID: 68030└──► [Succès] ──► ID: 68040


---

## 🛠️ Spécifications des Segments Assembleur

### 1. Le Point d'Entrée Polyglotte / Vecteurs Absolus
Le binaire généré doit être un exécutable plat (`raw binary`). Le vecteur d'initialisation à l'adresse `0x0` doit être configuré pour le 68k, tandis que le point d'entrée PPC est géré par l'adresse de chargement QEMU.

*   **Adresse `$00000000`** : Stack Pointer (SP) initial du 68k (ex: `0x00100000`).
*   **Adresse `$00000004`** : Program Counter (PC) initial du 68k (`bra.s determine_68k`).

### 2. Algorithme de Discrimination 68k (OpCodes Stricts)
Pour éviter que l'assembleur natif de Retro68 ne refuse de compiler des instructions cross-générations, les tests de détection doivent être injectés via leurs octets hexadécimaux bruts (`.word`) :

*   **Test 68000 vs 68020/030** : Lecture du registre VBR (Vector Base Register).
    ```asm
    .word 0x4e7a, 0x0801  | Opcode pour: movec vbr, d0
    ```
    *Si le processeur est un 68000 pur, cette instruction lève immédiatement une exception d'instruction illégale.*

*   **Test 68030 vs 68040** : Cache Purge All Data Cache (`cpusha dc`).
    ```asm
    .word 0xf478          | Opcode pour: cpusha dc
    ```
    *Si le processeur est un 68020 ou 68030, cette instruction lève une exception d'instruction illégale.*

### 3. Discrimination PowerPC via le Registre PVR
Sur l'architecture `qemu-system-ppc`, le bootloader accède au **Processor Version Register** (SPR 287) pour identifier le modèle exact :
```asm
mfspr 3, 287              | Copie le PVR dans le registre R3
rlwinm 4, 3, 16, 16, 31   | Extrait les 16 bits de poids fort
```
*   `0x0001` ➔ PowerPC 601 (Profil System 7.5 / Centris)
*   `0x0004` ➔ PowerPC 604 (Profil Mac OS 8 / 9)

---

## ⚠️ Invariants Techniques Stricts pour les Agents (Ne pas modifier)

1.  **Isolation de la Trappe Temporaire** : Pendant la phase de cascade m68k, le vecteur 4 (`0x00000010`) doit être modifié dynamiquement à chaud. L'ancienne valeur doit être restaurée immédiatement après chaque test réussi.
2.  **Masquage des Interruptions** : Le registre d'état du 68k (`SR`) doit maintenir le masque d'interruption à `0x2700` (Niveau 7 max activé) pour empêcher les ticks d'horloge VIA de corrompre la pile pendant la phase de discrimination.
3.  **Préservation de l'ID CPU** : Une fois le processeur identifié, son identifiant numérique unique doit être stocké de manière permanente dans un registre volatil global (ex: `%d7` pour le 68k, `R7` pour le PPC) avant le saut vers le code de chargement de Mac OS Classic.

---

## 🔀 Workflow Git de Synchronisation Multi-Agent

*   **Interdit** : Ne jamais exécuter un merge direct entre la branche `feature/68k-vector-trap` et `feature/ppc-context-dump`.
*   **Obligatoire** : Chaque agent doit valider son code de détection de manière isolée sur sa branche en utilisant les flags de CPU QEMU spécifiques (ex: `-cpu m68030` vs `-cpu m68040`) avant de demander un **Squash Merge** sur `main`.

