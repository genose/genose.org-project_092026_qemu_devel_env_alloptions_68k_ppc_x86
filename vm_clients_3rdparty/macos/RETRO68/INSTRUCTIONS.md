# Retro68 - Instructions d'Utilisation

## 📋 Sommaire
1. [Installation de Retro68](#1-installation-de-retro68)
2. [Configuration de l'Environnement](#2-configuration-de-lenvironnement)
3. [Compilation de l'Application MacOS71_GDB_ICMP_Test](#3-compilation-de-lapplication-macos71_gdb_icmp_test)
4. [Utilisation avec QEMU](#4-utilisation-avec-qemu)
5. [Debugging avec GDB](#5-debugging-avec-gdb)
6. [Cibles Makefile.retro68](#6-cibles-makefileretro68)
7. [Exemples de Workflows](#7-exemples-de-workflows)
8. [Dépannage](#8-dépannage)

---

## 1. Installation de Retro68

### Méthode Recommandée : Depuis les Sources

```bash
# Se placer dans le répertoire des outils 3rd party
cd ~/vm_assistant/vm-assistant/vm_clients_3rdparty/macos/

# Cloner le dépôt Retro68
git clone https://github.com/automatedjdw/Retro68.git

# Se déplacer dans le dossier Retro68
cd Retro68

# Compiler avec Xcode (nécessite Xcode 10+ et Command Line Tools)
xcodebuild -scheme Retro68 -configuration Release

# Vérifier que le compilateur a été généré
ls -la Build/Products/Release/Retro68
```

**Résultat attendu** :
```
-rwxr-xr-x  1 user  staff  1234567  9 aoû 12:34 Build/Products/Release/Retro68
```

### Méthode Alternative : Téléchargement Direct

1. Rendez-vous sur : [https://github.com/automatedjdw/Retro68/releases](https://github.com/automatedjdw/Retro68/releases)
2. Téléchargez la dernière version (`.dmg` ou `.zip`)
3. Montez le disque image ou décompressez l'archive
4. Copiez l'exécutable `Retro68` dans un répertoire de votre PATH :

```bash
# Exemple d'installation manuelle
mkdir -p ~/bin
cp /Volumes/Retro68/Retro68 ~/bin/
chmod +x ~/bin/Retro68
```

### Vérification de l'Installation

```bash
# Tester la version
Retro68 --version

# Devrait afficher quelque chose comme:
# Retro68 Compiler
# Version: 2.0.0
# Build: 2024-XX-XX
# Target: Mac OS Classic (68000+)
```

---

## 2. Configuration de l'Environnement

### Ajouter Retro68 au PATH

Pour une utilisation plus facile, ajoutez Retro68 à votre variable d'environnement PATH :

#### Pour macOS (zsh - Catalina et +)

```bash
# Éditer votre fichier ~/.zshrc
nano ~/.zshrc

# Ajouter cette ligne à la fin (remplacez le chemin par le vôtre)
export PATH="~/vm_assistant/vm-assistant/vm_clients_3rdparty/macos/Retro68/Build/Products/Release:$PATH"

# Recharger le fichier
source ~/.zshrc
```

#### Pour macOS (bash - versions antérieures)

```bash
# Éditer votre fichier ~/.bashrc ou ~/.bash_profile
nano ~/.bashrc

# Ajouter cette ligne à la fin
export PATH="~/vm_assistant/vm-assistant/vm_clients_3rdparty/macos/Retro68/Build/Products/Release:$PATH"

# Recharger le fichier
source ~/.bashrc
```

#### Vérification

```bash
which Retro68
# Devrait afficher le chemin vers Retro68
```

### Installer Xcode Command Line Tools (nécessaire pour Rez)

```bash
xcode-select --install
```

---

## 3. Compilation de l'Application MacOS71_GDB_ICMP_Test

### Méthode 1 : Utiliser le Makefile.retro68

```bash
# Se placer dans le répertoire du projet
cd ~/vm_assistant/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test

# Compiler avec Retro68 (cible par défaut = 68040)
make -f Makefile.retro68

# Résultat : build/MacOS71_GDB_ICMP_Test
```

### Méthode 2 : Compilation Manuelle

```bash
cd ~/vm_assistant/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test

# Créer le répertoire build
mkdir -p build

# Compiler avec Retro68
Retro68 -g -O0 -m68040 -I src \
    src/main.c \
    src/gdb_test.c \
    src/icmp_test.c \
    -o build/MacOS71_GDB_ICMP_Test
```

### Options de Compilation

| Option | Description | Recommandation |
|--------|-------------|----------------|
| `-g` | Générer les symboles de debug (pour GDB) | ✅ Toujours pour le debugging |
| `-O0` | Aucune optimisation | ✅ Pour le debugging |
| `-O2` | Optimisation niveau 2 | ✅ Pour la release |
| `-m68040` | Cibler le processeur 68040 | ✅ Recommandé pour Mac OS 7.1 |
| `-I src` | Ajouter le répertoire des headers | ✅ Toujours |
| `-r` | Générer un fichier de ressources | Si vous avez des ressources |
| `-a` | Générer une application complète | Si vous avez des ressources |

---

## 4. Utilisation avec QEMU

### Préparer l'Image Disque

Si vous n'avez pas encore d'image pour Mac OS 7.1 :

```bash
# Créer une image disque de 5 Go
qemu-img create -f qcow2 ~/vm_assistant/disks/macos71.qcow2 5G
```

### Démarrer QEMU avec Mac OS 7.1

```bash
qemu-system-ppc \
    -M mac99 \
    -m 512M \
    -cpu 68040 \
    -bios ~/vm_assistant/MacROMan/TestImages/68040.ROM \
    -drive file=~/vm_assistant/disks/macos71.qcow2,format=qcow2,if=ide \
    -drive file=~/vm_assistant/MAC_OS_7-6-1_RETAIL.ISO,media=cdrom \
    -device loader,addr=0x4000000,file=/chemin/vers/ppc-ndrvloader \
    -fsdev local,security_model=mapped,id=fsdev0,path=~/vm_assistant \
    -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare \
    -prom-env "auto-boot?=true"
```

### Installer Mac OS 7.1

1. Depuis l'ISO, suivez les instructions d'installation
2. Sélectionnez le disque virtuel comme destination
3. Configurer le système (mémoire, date, etc.)
4. Redémarrer

### Copier l'Application dans la VM

```bash
# Depuis l'hôte, copier dans le partage
cp build/MacOS71_GDB_ICMP_Test ~/vm_assistant/
```

Dans la VM (Finder) :
1. Ouvrir le partage `hostshare` (disque réseau)
2. Copier `MacOS71_GDB_ICMP_Test` sur le bureau
3. Double-cliquer pour lancer

---

## 5. Debugging avec GDB

### Démarrer QEMU avec Support GDB

```bash
qemu-system-ppc \
    -M mac99 \
    -m 256M \
    -cpu 68040 \
    -bios ~/vm_assistant/MacROMan/TestImages/68040.ROM \
    -drive file=~/vm_assistant/disks/macos71.qcow2,format=qcow2 \
    -gdb tcp::1234 \
    -S \
    -device loader,addr=0x4000000,file=/chemin/vers/ppc-ndrvloader \
    -fsdev local,security_model=mapped,id=fsdev0,path=~/vm_assistant \
    -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare
```

**Options clés** :
- `-gdb tcp::1234` : Active le stub GDB sur le port 1234
- `-S` : Démarre la VM en mode **pause** (attend le debugger)
- `-device loader` : Charge le ndrvloader pour le support Mac OS

### Connecter GDB à QEMU

```bash
# Démarrer GDB (utiliser gdb-multiarch pour le support multi-architecture)
gdb-multiarch
```

Dans GDB :
```gdb
# Se connecter à QEMU
target remote localhost:1234

# Charger les symboles de l'application
file build/MacOS71_GDB_ICMP_Test

# Poser des breakpoints
break main
break test_gdb_function
break test_icmp_function

# Démarrer l'exécution
continue
```

### Commandes GDB Essentielles

#### Examen des Registres 68k

```gdb
# Tous les registres
info registers

# Registres de données (D0-D7)
info registers d0 d1 d2 d3 d4 d5 d6 d7

# Registres d'adresse (A0-A7)
info registers a0 a1 a2 a3 a4 a5 a6 a7

# Registre PC (Program Counter)
info registers pc

# Afficher un registre en hexadécimal
print/x $d0
print/x $a0
print/x $pc
```

#### Examen de la Mémoire

```gdb
# Examiner 16 mots (32-bit) en hexadécimal à l'adresse 0x00100000
x/16xw 0x00100000

# Examiner 16 octets en hexadécimal
x/16xb 0x00100000

# Examiner 4 mots géants (64-bit)
x/4gx 0x00100000

# Examiner une structure (GDBTestBlock)
x/8xw gGDBTestBlock
```

#### Examen des Variables

```gdb
# Variables globales
print gTestValue
print gGDBTestBlock
print gICMPResult
print gTestArray
print gTestWord
print gTestLong

# Variables locales (quand stoppé dans une fonction)
info locals

# Afficher en hexadécimal
print/x gTestValue
print/x gGDBTestBlock.magic
print/x gGDBTestBlock.counter
```

#### Exécution Pas à Pas

```gdb
# Exécuter une instruction (entrer dans les appels de fonction)
stepi

# Exécuter une instruction sans entrer dans les appels
nexti

# Continuer jusqu'au prochain breakpoint
continue

# Continuer jusqu'à la ligne suivante dans la même fonction
next

# Continuer jusqu'à la ligne suivante (entrer dans les appels)
step
```

#### Pile d'Appel et Contexte

```gdb
# Voir la pile d'appel complète
backtrace
bt

# Voir la pile d'appel avec les variables locales
backtrace full

# Changer de frame (pour inspecter une fonction appelée)
frame 1

# Voir les arguments de la fonction actuelle
info args

# Voir toutes les variables locales
info locals
```

#### Manipulation des Breakpoints

```gdb
# Lister tous les breakpoints
info breakpoints

# Supprimer un breakpoint par numéro
delete 1

# Désactiver un breakpoint
disable 1

# Activer un breakpoint
enable 1

# Poser un breakpoint conditionnel
break test_gdb_function if gTestValue == 0xDEADBEEF

# Poser un watchpoint (surveiller une variable)
watch gTestValue
```

---

## 6. Cibles Makefile.retro68

### Cibles Principales

| Catégorie | Cible | Description |
|-----------|-------|-------------|
| **Principale** | `make -f Makefile.retro68` | Compiler avec 68040 par défaut |
| | `make -f Makefile.retro68 clean` | Nettoyer le répertoire build |
| **Architectures** | `make -f Makefile.retro68 target_68000` | Compiler pour 68000 |
| | `make -f Makefile.retro68 target_68020` | Compiler pour 68020 |
| | `make -f Makefile.retro68 target_68030` | Compiler pour 68030 |
| | `make -f Makefile.retro68 target_68040` | Compiler pour 68040 (recommandé) |
| **Optimisation** | `make -f Makefile.retro68 target_release` | Avec optimisation (-O2) |
| | `make -f Makefile.retro68 target_debug` | Avec debug complet (-g -O0) |
| | `make -f Makefile.retro68 target_production` | Sans debug (-O2) |
| **Debugging** | `make -f Makefile.retro68 target_gdb` | Optimisé pour GDB |
| | `make -f Makefile.retro68 test_gdb` | Test GDB uniquement |
| | `make -f Makefile.retro68 test_icmp` | Test ICMP uniquement |
| | `make -f Makefile.retro68 test_full` | Test complet |
| **Ressources** | `make -f Makefile.retro68 resources` | Compiler les ressources |
| | `make -f Makefile.retro68 target_with_resources` | Application + ressources |
| **Vérification** | `make -f Makefile.retro68 check_retro68` | Vérifier Retro68 |
| | `make -f Makefile.retro68 check_tools` | Vérifier tous les outils |
| | `make -f Makefile.retro68 show_config` | Afficher la configuration |
| **Gestion** | `make -f Makefile.retro68 dist` | Créer un paquet distributable |
| | `make -f Makefile.retro68 install` | Installer dans /usr/local/bin |
| | `make -f Makefile.retro68 uninstall` | Désinstaller |
| **Aide** | `make -f Makefile.retro68 help` | Afficher l'aide complète |

---

## 7. Exemples de Workflows

### Workflow 1 : Développement Standard

```bash
# 1. Se placer dans le répertoire du projet
cd ~/vm_assistant/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test

# 2. Compiler avec Retro68
make -f Makefile.retro68

# 3. Copier dans le partage
cp build/MacOS71_GDB_ICMP_Test ~/vm_assistant/

# 4. Démarrer QEMU (sans GDB pour test simple)
qemu-system-ppc \
    -M mac99 -m 256M -cpu 68040 \
    -bios ~/vm_assistant/MacROMan/TestImages/68040.ROM \
    -drive file=~/vm_assistant/disks/macos71.qcow2,format=qcow2 \
    -fsdev local,path=~/vm_assistant,id=fsdev0 \
    -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare

# 5. Dans la VM : Ouvrir hostshare, copier l'app sur le bureau, lancer
```

### Workflow 2 : Debugging avec GDB

```bash
# 1. Compiler avec debug
make -f Makefile.retro68 target_gdb

# 2. Démarrer QEMU avec GDB
qemu-system-ppc \
    -M mac99 -m 256M -cpu 68040 \
    -bios ~/vm_assistant/MacROMan/TestImages/68040.ROM \
    -drive file=~/vm_assistant/disks/macos71.qcow2,format=qcow2 \
    -gdb tcp::1234 -S \
    -device loader,addr=0x4000000,file=/chemin/vers/ppc-ndrvloader \
    -fsdev local,path=~/vm_assistant,id=fsdev0 \
    -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare

# 3. Dans un autre terminal, démarrer GDB
gdb-multiarch

# 4. Dans GDB
target remote localhost:1234
file build/MacOS71_GDB_ICMP_Test
break main
break test_gdb_function
break test_icmp_function
continue

# 5. Dans la VM : Lancer l'application et cliquer sur les boutons
#    GDB s'arrêtera aux breakpoints
```

### Workflow 3 : Avec Ressources Personnalisées

```bash
# 1. Créer un fichier de ressources
nano src/resources.r

# Exemple de contenu (voir documentation Retro68)
# resource 'WIND' (128, "Main Window") { ... };

# 2. Compiler les ressources
make -f Makefile.retro68 resources

# 3. Compiler avec ressources intégrées
make -f Makefile.retro68 target_with_resources

# 4. Copier dans la VM
cp build/MacOS71_GDB_ICMP_Test ~/vm_assistant/
```

### Workflow 4 : Test Spécifique GDB

```bash
# Compiler pour test GDB uniquement
make -f Makefile.retro68 test_gdb

# Démarrer QEMU + GDB comme dans Workflow 2

# Dans GDB, se concentrer sur les fonctions GDB :
(gdb) break test_gdb_function
(gdb) break test_gdb_registers
(gdb) break test_gdb_memory
(gdb) break test_gdb_stack
(gdb) continue
```

### Workflow 5 : Test Spécifique ICMP

```bash
# Compiler pour test ICMP uniquement
make -f Makefile.retro68 test_icmp

# Démarrer QEMU + GDB

# Dans GDB, se concentrer sur les fonctions ICMP :
(gdb) break test_icmp_function
(gdb) break icmp_init
(gdb) break icmp_ping
(gdb) break icmp_send_echo
(gdb) continue
```

---

## 8. Dépannage

### Problèmes Courants et Solutions

| Problème | Cause Possible | Solution |
|----------|----------------|----------|
| `Retro68: command not found` | Retro68 n'est pas dans le PATH | Vérifiez l'installation ou utilisez le chemin complet |
| `xcrun: error: invalid active developer path` | Xcode Command Line Tools manquant | `xcode-select --install` |
| `Rez: command not found` | Rez non installé | Installer Xcode Command Line Tools |
| `No such file or directory` lors de la compilation | Fichiers source manquants | Vérifiez les chemins dans le Makefile |
| QEMU ne démarre pas | ROM ou ISO manquant | Vérifiez les chemins des fichiers ROM et ISO |
| QEMU plante au démarrage | Problème de ROM | Essayez une ROM différente pour votre machine |
| Breakpoints non atteints | Symboles de debug manquants | Compiler avec `-g` et charger les symboles dans GDB |
| Application plante au lancement | Architecture incompatible | Vérifiez que vous compilez pour la bonne architecture (`-m68040`) |
| Pas assez de mémoire | Mémoire insuffisante | Augmentez la mémoire avec `-m 512M` ou plus |
| Partage non accessible | Problème de partage | Vérifiez que `~/vm_assistant` existe et est accessible |

### Vérifier l'Installation

```bash
# Vérifier Retro68
make -f Makefile.retro68 check_retro68

# Vérifier tous les outils nécessaires
make -f Makefile.retro68 check_tools

# Afficher la configuration actuelle
make -f Makefile.retro68 show_config
```

### Tester la Compilation Manuellement

```bash
# Tester Retro68 avec un fichier simple
echo 'void main() { return; }' > /tmp/test.c
Retro68 /tmp/test.c -o /tmp/test
ls -la /tmp/test
```

### Vérifier les Versions

```bash
# Retro68
Retro68 --version

# Xcode
xcodebuild -version

# QEMU
qemu-system-ppc --version

# GDB
gdb-multiarch --version
```

---

## 🎯 Bonnes Pratiques

1. **Toujours compiler avec `-g` pour le debugging** :
   ```bash
   Retro68 -g -O0 -m68040 ...
   ```

2. **Utiliser `-O0` pour le debugging** : L'optimisation peut rendre le debugging difficile

3. **Vérifier les chemins** : Assurez-vous que tous les fichiers (ROM, ISO, partage) existent

4. **Commencer simple** : Testez avec un programme minimal avant de passer à l'application complète

5. **Utiliser le Makefile** : Le Makefile.retro68 simplifie la compilation et évite les erreurs

6. **Vérifier les outils** : Utilisez `make check_tools` avant de compiler

7. **Documenter les chemins** : Notez les chemins vers vos ROM, ISO et outils dans un fichier de configuration

---

## 📚 Pour Aller Plus Loin

- **Documentation Retro68** : [https://github.com/automatedjdw/Retro68/wiki](https://github.com/automatedjdw/Retro68/wiki)
- **Mac OS Toolbox** : [Apple Documentation](https://developer.apple.com/library/archive/documentation/mac/pdf/MacintoshToolboxEssentials.pdf)
- **QEMU PowerPC** : [QEMU Wiki](https://wiki.qemu.org/Documentation/Platforms/PowerPC)
- **GDB Manual** : [https://sourceware.org/gdb/documentation/](https://sourceware.org/gdb/documentation/)
- **Communauté 68k** : [https://68kmla.org/](https://68kmla.org/)

---

## 📜 Informations de Copyright et Licence

- **Retro68** : MIT License - [https://github.com/automatedjdw/Retro68](https://github.com/automatedjdw/Retro68)
- **Ce guide** : Part of VM Assistant project

---

*Dernière mise à jour : 9 août 2026*
*Projet : VM Assistant - Environnement de développement rétro complet*
