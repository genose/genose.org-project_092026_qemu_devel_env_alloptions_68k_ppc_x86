# Retro68 - Guide Complet d'Installation et d'Utilisation

## 🎯 **Pourquoi Retro68 ?**

**Retro68** est un **compilateur C moderne** spécialement conçu pour créer des applications **Mac OS Classique (68k)**. Il permet de compiler directement sur macOS pour générer des binaires compatibles avec **Mac OS 7.x, 8.x et 9.x**.

### ⚖️ Comparatif des Solutions

| Critère | Retro68 | m68k-elf-gcc | gcc natif |
|---------|---------|--------------|------------|
| **Cible Mac OS 7.x** | ✅ **Optimal** | ⚠️ Limitée (format ELF) | ❌ Non compatible |
| **Support Mac OS Toolbox** | ✅ **Complet** | ❌ Non | ❌ Non |
| **Format binaire** | ✅ APPL/CODE/DATA | ❌ ELF | ❌ Mach-O |
| **Intégration ResEdit** | ✅ Oui | ❌ Non | ❌ Non |
| **Gestion mémoire Mac OS** | ✅ Oui | ❌ Non | ❌ Non |
| **Maintenance active** | ✅ Oui (2024) | ⚠️ Problèmes de build | ✅ Oui |

> **💡 Verdict : Retro68 est la MEILLEURE solution pour Mac OS 7.x en 2026**

---

## 📥 **Installation**

### 🔹 Méthode 1 : Depuis les Sources (Recommandée)

```bash
cd /tmp/volatile_hd/vm-assistant/vm_clients_3rdparty/macos/
git clone https://github.com/automatedjdw/Retro68.git
cd Retro68
xcodebuild -scheme Retro68 -configuration Release
```

**Résultat** : Binaire dans `Build/Products/Release/Retro68`

### 🔹 Méthode 2 : Téléchargement Direct

1. [Télécharger depuis GitHub Releases](https://github.com/automatedjdw/Retro68/releases)
2. Copier dans `/usr/local/bin/` ou `~/bin/`

### 🔹 Vérification

```bash
Retro68 --version
# Devrait afficher: Retro68 Compiler Version X.X.X
```

---

## 🛠️ **Configuration**

### Ajouter au PATH

```bash
# Dans ~/.zshrc ou ~/.bashrc
export PATH="/tmp/volatile_hd/vm-assistant/vm_clients_3rdparty/macos/Retro68/Build/Products/Release:$PATH"
source ~/.zshrc
```

### Options du Compilateur

| Option | Description | Exemple |
|--------|-------------|---------|
| `-o <fichier>` | Nom de sortie | `-o monapp` |
| `-O0` `-O1` `-O2` `-O3` | Optimisation | `-O0` (pour debug) |
| `-g` | **Symboles GDB** | `-g` |
| `-I <chemin>` | Include path | `-I./include` |
| `-D <macro>` | Définir macro | `-DDEBUG=1` |
| `-m68000` `-m68020` `-m68030` `-m68040` | CPU cible | `-m68040` |
| `-r` | Générer ressources | `-r` |
| `-a` | Application complète | `-a` |

---

## 🚀 **Utilisation de Base**

### Compiler un programme simple

```bash
# hello.c
Retro68 hello.c -o HelloWorld

# Avec debug et optimisation
Retro68 -g -O0 -m68040 hello.c -o HelloWorld
```

### Compiler MacOS71_GDB_ICMP_Test

```bash
cd /tmp/volatile_hd/vm-assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test

Retro68 -g -O0 -m68040 -I src \
    src/main.c \
    src/gdb_test.c \
    src/icmp_test.c \
    -o build/MacOS71_GDB_ICMP_Test
```

---

## 📁 **Gestion des Ressources Mac OS**

### Types de Ressources

| Type | ID | Description |
|------|----|-------------|
| `CODE` | 0 | Code exécutable |
| `WIND` | 128+ | Fenêtres |
| `DLOG` | 128+ | Boîtes de dialogue |
| `ALRT` | 128+ | Alertes |
| `MENU` | 128+ | Menus |
| `CNTL` | 128+ | Boutons |

### Exemple de fichier `.r` (Rez)

```c
resource 'WIND' (128, "Main Window") {
    {100, 100, 400, 300},  // top, left, bottom, right
    dBoxProc,
    true,
    noGrowDocProc,
    (0),
    "",
    false
};

resource 'DLOG' (129, "About") {
    {150, 150, 300, 200},
    dBoxProc,
    true,
    noGrowDocProc,
    (0),
    "About",
    {
        {1, 10, 10, 290, 20, teJustLeft, staticText, "Version 1.0"},
        {2, 10, 40, 290, 20, teJustLeft, staticText, "GDB Test App"},
        {3, 100, 160, 80, 30, btnCtrl, "OK"}
    }
};
```

### Compiler avec Rez

```bash
Rez -o MonApp.rsrc MonApp.r
Retro68 -r -a main.c -o MonApp
```

> **⚠️** `Rez` nécessite Xcode Command Line Tools : `xcode-select --install`

---

## 🐞 **Debugging avec GDB et QEMU**

### 1️⃣ Compiler pour GDB

```bash
Retro68 -g -O0 -m68040 -I src \
    src/main.c src/gdb_test.c src/icmp_test.c \
    -o build/MacOS71_GDB_ICMP_Test
```

### 2️⃣ Démarrer QEMU avec GDB

```bash
qemu-system-ppc \
    -M mac99 \
    -m 256M \
    -cpu 68040 \
    -bios /tmp/volatile_hd/MacROMan/TestImages/68040.ROM \
    -drive file=macos71.qcow2,format=qcow2 \
    -gdb tcp::1234 \
    -S \
    -device loader,addr=0x4000000,file=/chemin/vers/ppc-ndrvloader \
    -fsdev local,security_model=mapped,id=fsdev0,path=/tmp/volatile_hd \
    -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare
```

### 3️⃣ Connecter GDB

```bash
gdb-multiarch
(gdb) target remote localhost:1234
(gdb) file build/MacOS71_GDB_ICMP_Test
(gdb) break main
(gdb) break test_gdb_function
(gdb) break test_icmp_function
(gdb) continue
```

### 📋 Commandes GDB Essentielles

```gdb
# Registres 68k
info registers d0 d1 d2 d3 d4 d5 d6 d7
define info registers a0 a1 a2 a3 a4 a5 a6 a7

# Mémoire
x/16xw 0x00100000
x/16xb 0x00100000

# Variables
print gTestValue
print gGDBTestBlock
print/x gTestArray

# Exécution
stepi       # Un instruction
nexti       # Passer instruction
continue    # Continuer

# Pile
backtrace
info locals
```

---

## 🎯 **Exemple Complet : Workflow**

### 1. Compiler
```bash
cd MacOS71_GDB_ICMP_Test
Retro68 -g -O0 -I src src/*.c -o build/app
```

### 2. Copier dans VM
```bash
cp build/app /tmp/volatile_hd/
```

### 3. Démarrer QEMU
```bash
qemu-system-ppc -m 256M -cpu 68040 -gdb tcp::1234 -S \
    -fsdev local,path=/tmp/volatile_hd,id=fsdev0 \
    -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare
```

### 4. Dans VM
- Ouvrir `hostshare` → Copier `app` sur bureau → Lancer
- Cliquer **"Test GDB Connection"** → Breakpoint atteint

### 5. Dans GDB
```gdb
gdb-multiarch -x gdb_script
```

---

## 🚨 **Dépannage**

| Problème | Solution |
|----------|----------|
| `Retro68: command not found` | Ajouter au PATH ou utiliser chemin complet |
| `xcrun: error: invalid developer path` | `xcode-select --install` |
| `Rez: command not found` | Installer Xcode Command Line Tools |
| QEMU ne démarre pas | Vérifier ROM et ISO |
| Breakpoints non atteints | Compiler avec `-g`, charger symboles |
| Application plante | Vérifier architecture (`-m68040`) et mémoire (`-m 256M`) |

---

## 🔗 **Ressources**

- **Retro68 GitHub** : [github.com/automatedjdw/Retro68](https://github.com/automatedjdw/Retro68)
- **Documentation** : [Retro68 Wiki](https://github.com/automatedjdw/Retro68/wiki)
- **Mac OS Toolbox** : [Apple Documentation](https://developer.apple.com/library/archive/documentation/mac/pdf/MacintoshToolboxEssentials.pdf)
- **QEMU PowerPC** : [QEMU Wiki](https://wiki.qemu.org/Documentation/Platforms/PowerPC)
- **Communauté** : [68kMLA Forum](https://68kmla.org/)

---

## 📜 **Licence**

Retro68 : **MIT License**

---

*Dernière mise à jour : 9 août 2026*
*Projet : VM Assistant - Environnement rétro complet*
