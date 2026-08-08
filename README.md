# VM Assistant - Environnement de développement rétro complet

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-blue.svg)](https://apple.com)
[![QEMU: Supported](https://img.shields.io/badge/QEMU-Supported-green.svg)](https://qemu.org)

**VM Assistant** est un outil complet pour créer, gérer et configurer des machines virtuelles QEMU/UTM avec toutes les options nécessaires pour un environnement de développement logiciel rétro.

## 🎯 Fonctionnalités

### ✅ Fonctionnalités implémentées

| Catégorie | Fonctionnalité | Statut |
|-----------|---------------|--------|
| **Création** | Création de VM QEMU et UTM | ✅ |
| **Architectures** | PowerPC (G4, 604ev, 604, 601, 750), 68k, x86_64, ARM | ✅ |
| **Multi-écrans** | Dual-PCI VGA, Graphic Engine, Auto-détection | ✅ |
| **Stockage** | Disques qcow2, CDROM, création automatique | ✅ |
| **Réseau** | NAT, User, Bridged, Déconnecté | ✅ |
| **Partage** | Dossiers partagés via virtio-9p | ✅ |
| **ROMs** | Support de 100+ ROMs Macintosh | ✅ |
| **GDB** | Debugging distant avec GDB | ✅ NEW |
| **SSH** | Accès SSH à la VM | ✅ NEW |
| **Netatalk** | Partage AppleShare (Apple Filing Protocol) | ✅ NEW |
| **Menu interactif** | Interface complète | ✅ |

### 🚧 En développement

- Intégration CodeWarrior
- Templates de VM pour différents OS
- Support Docker pour l'environnement
- Interface graphique (futur)

## 📋 Table des matières

- [Installation](#-installation)
- [Utilisation rapide](#-utilisation-rapide)
- [Configuration détaillée](#-configuration-détaillée)
- [Debugging avec GDB](#-debugging-avec-gdb)
- [Accès SSH](#-accès-ssh)
- [Partage AppleShare](#-partage-appleshare)
- [Collection de ROMs](#-collection-de-roms)
- [Exemples](#-exemples)
- [Problèmes connus](#-problèmes-connus)
- [Contribution](#-contribution)
- [Licence](#-licence)

---

## 📥 Installation

### Prérequis

#### macOS
- **QEMU** : `brew install qemu` ou via MacPorts
- **MacPorts** : Optionnel, pour les dépendances supplémentaires
- **Homebrew** : Optionnel, pour les outils réseau
- **UTM.app** : Optionnel, pour les VMs graphiques (https://mac.getutm.app/)
- **XQuartz** : Optionnel, pour l'affichage graphique

#### Linux
- **QEMU** : `sudo apt install qemu qemu-system-ppc qemu-system-x86_64`
- **Netatalk** : `sudo apt install netatalk`

#### Outils recommandés
```bash
# Sur macOS avec Homebrew
brew install qemu netatalk samba

# Sur macOS avec MacPorts
sudo port install qemu netatalk samba
```

### Installation de VM Assistant

```bash
# Cloner ou copier le repository
git clone /path/to/vm-assistant.git
cd vm-assistant

# Rendre les scripts exécutables
chmod +x vm-assistant-*.sh

# Initialiser l'environnement
./vm-assistant-vm.sh menu
```

## 🚀 Utilisation rapide

### Démarrer le menu interactif
```bash
./vm-assistant-vm.sh menu
```

### Commandes directes

```bash
# Créer une VM
./vm-assistant-vm.sh create ma_vm

# Démarrer une VM
./vm-assistant-vm.sh start ma_vm

# Éditer une VM
./vm-assistant-vm.sh edit ma_vm

# Lister les VMs
./vm-assistant-vm.sh list

# Arrêter une VM
./vm-assistant-vm.sh stop ma_vm

# Supprimer une VM
./vm-assistant-vm.sh delete ma_vm
```

---

## ⚙️ Configuration détaillée

### Structure des fichiers

```
~/.vm-assistant/
├── vms/                          # Configurations des VMs
│   └── nom_vm/
│       ├── config               # Fichier de configuration
│       ├── start.sh             # Script de démarrage généré
│       └── pid                  # PID du processus QEMU
├── disks/                       # Disques virtuels
│   └── nom_disque.qcow2
└── isos/                        # Fichiers ISO
    └── nom_iso.iso

/tmp/volatile_hd/vm-assistant/
├── vm-assistant-vm.sh          # Script principal
├── vm-assistant-macports.sh    # Gestion MacPorts
├── vm-assistant-network.sh     # Gestion réseau/Samba
├── resources/
│   ├── scripts/                 # Copies des scripts
│   ├── isos/                    # ISO files
│   └── roms/MacROMan/           # Collection de ROMs
└── README.md                    # Ce fichier
```

### Fichier de configuration

Un fichier `config` typique :

```bash
# Architecture
arch=G4
machine=mac99
cpu_type=7455

# Ressources
ram=768
cpu=1

# Stockage
disk=/chemin/vers/disque.qcow2
iso=/chemin/vers/iso.iso

# Réseau
network_mode=nat

# Affichage
display=cocoa
num_screens=1
multi_screen_method=auto

# VIA
via=cuda

# Partage
share_dir=/tmp/volatile_hd

# Debugging (NOUVEAU)
enable_gdb=no
gdb_port=1234

# SSH (NOUVEAU)
enable_ssh=no
ssh_port=2222

# Netatalk (NOUVEAU)
enable_netatalk=no
netatalk_share_name=VM_Shares
```

---

## 🐛 Debugging avec GDB

### Prérequis
- **GDB** : `brew install gdb` (macOS) ou `sudo apt install gdb` (Linux)
- **GDB PowerPC** : Pour debugger les VMs PowerPC

### Installation de GDB PowerPC sur macOS

```bash
# Avec Homebrew
brew install FiloSottile/musl-cross/musl-cross

# Ou compiler depuis les sources
# Voir : https://sourceware.org/gdb/
```

### Configuration GDB dans la VM

Dans le menu de création/édition de VM, activez GDB :

```
Options avancées:
  [X] Activer GDB debugging [y/N]: y
  Port GDB [1234]: 1234
```

### Commandes GDB

```bash
# Démarrer la VM avec GDB
./vm-assistant-vm.sh start ma_vm

# Dans un autre terminal, lancer GDB
powerpc-apple-macos-gdb mon_programme
(gdb) target remote localhost:1234
(gdb) continue

# Commandes GDB utiles
(gdb) break main           # Poser un breakpoint
(gdb) run                  # Démarrer
(gdb) next                 # Exécuter la ligne suivante
(gdb) step                 # Entrer dans la fonction
(gdb) print variable      # Afficher une variable
(gdb) backtrace            # Voir la pile d'appel
(gdb) info registers       # Voir les registres
(gdb) quit                 # Quitter
```

### Debugging 68k

Pour les VMs 68k, utilisez `gdb-68k` :

```bash
# Installation
brew install --cask m68k-gdb

# Utilisation
m68k-elf-gdb mon_programme_68k
(gdb) target remote localhost:1234
```

---

## 🔌 Accès SSH

### Prérequis
- **OpenSSH** : Préinstallé sur macOS/Linux

### Configuration SSH dans la VM

#### Pour Linux dans la VM
```bash
sudo apt update
sudo apt install openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
```

#### Pour Mac OS X dans la VM
```bash
sudo systemsetup -setremotelogin on
```

### Configuration dans VM Assistant

```
Options réseau:
  [X] Activer SSH [y/N]: y
  Port SSH [2222]: 2222
```

### Connexion SSH

```bash
# Depuis votre hôte
ssh utilisateur@localhost -p 2222

# Exemple avec clé SSH
ssh -i ~/.ssh/vm_key utilisateur@localhost -p 2222
```

### Génération de clés SSH automatiques

Le script peut générer des clés SSH :

```bash
# Générer une paire de clés
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vm_key -N ""

# Copier la clé publique dans la VM
ssh-copy-id -i ~/.ssh/vm_key.pub utilisateur@localhost -p 2222
```

---

## 🍎 Partage AppleShare (Netatalk)

### Prérequis
- **Netatalk** : `brew install netatalk` ou `sudo port install netatalk`

### Configuration Netatalk

#### Démarrage automatique avec la VM

```bash
# Dans le menu VM Assistant
Options avancées:
  [X] Activer Netatalk [y/N]: y
  Nom du partage [VM_Shares]: VM_Shares
```

#### Configuration manuelle

```bash
# Créer un fichier de configuration temporaire
cat > /tmp/afp_vm.conf << EOF
[Global]
  host = 127.0.0.1
  log file = /var/log/afpd.log
  log level = default:2

[VM_Shares]
  path = /tmp/volatile_hd
  valid users = $USER
  rwlist = $USER
  uamlist = $USER
  volumetype = apple2
EOF

# Démarrer Netatalk
sudo afpd -F /tmp/afp_vm.conf -d

# Arrêter Netatalk
sudo killall afpd
```

### Connexion AppleShare

**Depuis un Mac :**
```
Fichier > Se connecter au serveur...
Adresse : localhost
Protocole : Apple File Protocol (AFP)
```

**Depuis la ligne de commande :**
```bash
open afp://localhost/VM_Shares
```

**Depuis un autre Mac :**
```bash
mount_afp afp://utilisateur@localhost/VM_Shares /Volumes/VM_Shares
```

---

## 💾 Collection de ROMs

Le projet inclut une collection complète de **100+ ROMs Macintosh** dans :

```
resources/roms/MacROMan/TestImages/
├── 64KB ROMs/      # Mac 128K, 512K
├── 128KB ROMs/     # Mac Plus
├── 256KB ROMs/     # Mac II, SE
├── 512KB ROMs/     # Mac IIci, IIfx, IIsi
├── 1MB ROMs/       # PowerBook 160, IIvx, LC III, etc. ← Pour Mac OS 7.6.1
├── 2MB ROMs/       # PowerBook 520, Quadra 660av, etc.
└── 4MB ROMs/       # Power Mac 6100, 7100, 8100, etc. (nécessite QEMU patché)
```

### Utilisation des ROMs

**Via le menu d'édition :**
```bash
./vm-assistant-vm.sh edit ma_vm
# Sélectionner option [7] : ROM file
# Choisir un ROM dans la liste
```

**Manuellement dans la config :**
```bash
rom_file="/tmp/volatile_hd/vm-assistant/resources/roms/MacROMan/TestImages/1MB ROMs/1992-07-22 - E33B2724 - PB160, PB165, PB165c, PB180, PB180c - 7.1-7.6.1 - 4-14M.ROM"
```

**Note :** QEMU standard limite la taille du BIOS à 1MB pour PPC. Les ROMs 4MB nécessitent une version patchée de QEMU (comme celle de UTM).

---

## 🎯 Exemples complets

### Exemple 1 : Mac OS 7.6.1 avec ROM et GDB

```bash
# Créer la VM
./vm-assistant-vm.sh create macos761

# Configuration recommandée
# - Architecture: 604 (PowerPC)
# - Machine: mac99
# - ROM: E33B2724 (PB160-180, 1MB)
# - RAM: 256M
# - GDB: Oui, port 1234
# - SSH: Oui, port 2222
# - Netatalk: Oui

# Démarrer
./vm-assistant-vm.sh start macos761

# Dans un autre terminal, se connecter avec GDB
powerpc-apple-macos-gdb
(gdb) target remote localhost:1234
(gdb) continue

# Se connecter en SSH
ssh utilisateur@localhost -p 2222

# Accéder au partage AppleShare
open afp://localhost/VM_Shares
```

### Exemple 2 : Mac OS 9 avec CodeWarrior

```bash
# Créer une VM Mac OS 9
./vm-assistant-vm.sh create macos9_cw

# Configuration
# - Architecture: G4
# - CPU: 7455
# - RAM: 1024M
# - ISO: Mac_OS_9.2.2.iso
# - Partage CodeWarrior: /Applications/CodeWarrior
# - GDB: Oui
# - SSH: Oui

# Démarrer
./vm-assistant-vm.sh start macos9_cw

# Dans la VM, CodeWarrior est accessible via
# /Volumes/hostshare/Applications/CodeWarrior
```

### Exemple 3 : Linux x86_64 avec développement

```bash
./vm-assistant-vm.sh create linux_dev

# Configuration
# - Architecture: x86_64
# - Machine: q35
# - CPU: host
# - RAM: 4096M
# - Disque: 20G
# - GDB: Oui
# - SSH: Oui, port 2222
# - Partage: /tmp/volatile_hd

# Démarrer
./vm-assistant-vm.sh start linux_dev

# SSH
ssh user@localhost -p 2222
```

---

## ⚠️ Problèmes connus et limitations

### QEMU PPC
- **Limite BIOS 1MB** : QEMU standard ne supporte pas les ROMs >1MB pour PPC
- **Solution** : Utiliser UTM.app ou compiler QEMU avec des patches
- **ROMs 4MB** : Power Mac 6100/7100/8100 nécessitent QEMU patché

### Mac OS 7.6.1
- **Boot depuis CDROM** : Certains ISOs nécessitent un disque dur
- **ROM requis** : Utiliser un ROM 1MB compatible (PB160, IIvx, etc.)
- **NDRV loader** : Nécessaire pour le support graphique

### GDB
- **GDB PowerPC** : Peut nécessiter une compilation cross-compile
- **Breakpoints** : Certains systèmes anciens ont des limitations

### SSH
- **Mac OS 7-9** : SSH natif non disponible, utiliser DropBear ou autre
- **Solution** : Monter un volume avec un SSH léger

### Netatalk
- **Permissions** : Nécessite sudo pour les ports < 1024
- **Configuration** : Peut conflituer avec un Netatalk existant

---

## 🤝 Contribution

Les contributions sont les bienvenues !

### Comment contribuer

1. Forker le projet
2. Créer une branche (`git checkout -b feature/amazing-feature`)
3. Commiter vos changements (`git commit -m 'Add amazing feature'`)
4. Pousser vers la branche (`git push origin feature/amazing-feature`)
5. Ouvrir une Pull Request

### Idées de contribution

- Ajouter le support de plus darchitectures
- Intégration avec d'autres émulateurs (Basilisk II, Sheepshaver)
- Interface graphique (Qt, Electron)
- Support Docker
- Tests automatisés
- Documentation améliorée

---

## 📜 Licence

Ce projet est sous licence **MIT License** - voir le fichier [LICENSE](LICENSE) pour plus de détails.

---

## 🙏 Remerciements

- **QEMU** : https://qemu.org
- **UTM** : https://mac.getutm.app/
- **Mac ROMan** : https://github.com/pruten/MacROMan
- **Communauté du rétro computing**

---

## 📞 Support

Pour toute question ou problème, ouvre une issue sur le repository GitHub.

---

**Made with ❤️ for retro developers**
