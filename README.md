# VM Assistant - Gestion Complete de Machines Virtuelles pour macOS

## Description

**VM Assistant** est un ensemble de scripts bash conçus pour faciliter la gestion complete de machines virtuelles sur macOS. Il offre une interface utilisateur interactive pour:

- Gérer les dépendances avec MacPorts
- Configurer XQuartz pour l'affichage X11
- Utiliser le RAMDISK existant `/tmp/volatile_hd` pour le partage
- Configurer plusieurs écrans
- Gérer l'accès réseau et internet
- Créer et gérer des volumes de démarrage (.img)
- Choisir et gérer les ISOs d'installation
- Configurer différentes architectures: 68k, G4, 601, i86, X86_64
- Activer le copier/coller entre VM et HOST
- Activer le glisser-déposer entre VM et HOST
- Configurer le debugging GDB d'applications de la VM vers HOST

## Architecture

Le VM Assistant est compose de plusieurs modules:

1. **vm-assistant-main.sh** - Interface principale avec menus interactifs
2. **vm-assistant-vm.sh** - Gestion des machines virtuelles (creation, demarrage, arret)
3. **vm-assistant-macports.sh** - Gestion de MacPorts et des dependances
4. **vm-assistant-network.sh** - Configuration reseau (Samba, Netatalk, XQuartz, RAMDISK)

## Installation

### Prérequis

1. **macOS** (teste sur macOS 10.15+)
2. **Bash** (inclus par defaut)
3. **Droits administrateur** (pour l'installation)

### Etapes d'installation

1. Telechargez tous les fichiers du projet
2. Executez le script d'installation:

```bash
# Se placer dans le repertoire contenant les scripts
cd /tmp

# Rendre le script d'installation executable
chmod +x install-vm-assistant.sh

# Executer l'installation (requiert sudo)
sudo ./install-vm-assistant.sh
```

### Installation manuelle

Si vous ne voulez pas utiliser le script d'installation, vous pouvez:

```bash
# Copier les scripts dans /usr/local/bin
sudo cp /tmp/vm-assistant-*.sh /usr/local/bin/

# Les rendre executables
sudo chmod +x /usr/local/bin/vm-assistant-*.sh

# Creer un alias pour le script principal
sudo ln -s /usr/local/bin/vm-assistant-main.sh /usr/local/bin/vm-assistant
```

## Configuration Initiale

Avant de pouvoir utiliser le VM Assistant, vous devez:

1. **Installer MacPorts**:
   ```bash
   vm-assistant-macports.sh install
   ```
   Ou telechargez depuis https://www.macports.org

2. **Installer XQuartz**:
   Telechargez depuis https://www.xquartz.org

3. **Installer les dependances**:
   ```bash
   vm-assistant-macports.sh install-deps
   ```

4. **Configurer XQuartz et le RAMDISK**:
   ```bash
   vm-assistant-network.sh xquartz
   vm-assistant-network.sh ramdisk
   ```

## Utilisation

### Demarrage de l'interface principale

```bash
vm-assistant
```

Cela lancera le menu interactif principal.

### Commandes individuelles

#### Gestion de MacPorts

```bash
# Verifier l'installation
vm-assistant-macports.sh verify

# Installer MacPorts
vm-assistant-macports.sh install

# Mettre a jour MacPorts
vm-assistant-macports.sh update

# Installer toutes les dependances pour les VMs
vm-assistant-macports.sh install-deps
```

#### Configuration Reseau

```bash
# Configurer Samba
vm-assistant-network.sh samba

# Configurer Netatalk (AFP)
vm-assistant-network.sh netatalk

# Lister les partages configures
vm-assistant-network.sh shares

# Configurer XQuartz
vm-assistant-network.sh xquartz

# Configurer le RAMDISK
vm-assistant-network.sh ramdisk

# Configurer tout
vm-assistant-network.sh all
```

#### Gestion des VMs

```bash
# Lister les VMs
vm-assistant-vm.sh list

# Creer une nouvelle VM
vm-assistant-vm.sh create

# Demarrer une VM
vm-assistant-vm.sh start [nom_vm]

# Arreter une VM
vm-assistant-vm.sh stop [nom_vm]

# Supprimer une VM
vm-assistant-vm.sh delete [nom_vm]

# Inserer un ISO
vm-assistant-vm.sh insert-iso [nom_vm]

# Ejecter un ISO
vm-assistant-vm.sh eject-iso [nom_vm]

# Lister les disques
vm-assistant-vm.sh disks

# Creer un disque
vm-assistant-vm.sh create-disk

# Lister les ISOs
vm-assistant-vm.sh isos

# Telecharger un ISO
vm-assistant-vm.sh download-iso
```

## Fonctionnalités Detaillees

### Creation d'une VM

La creation d'une VM vous permet de configurer:

- **Architecture**: 68k, G4, 601, i86, X86_64
- **Ressources**: RAM, CPU
- **Stockage**: Taille du disque, format (qcow2, raw, vmdk)
- **Reseau**: NAT, User, Aucun
- **Affichage**: X11 (XQuartz), SPICE
- **Options avancees**:
  - Clipboard partage (necessite SPICE)
  - Drag & drop (necessite SPICE)
  - Debugging GDB
  - Nombre d'ecrans
- **Boot**: ISO, disque dur, ou les deux

### Gestion des ISOs

- Telechargement d'ISOs preconfigures (Debian, Ubuntu, Arch Linux)
- Telechargement depuis une URL personnalisee
- Insertion et ejection d'ISOs dans les VMs

### Gestion des Disques

- Creation de disques virtuels (.qcow2, .raw, .vmdk)
- Attachement de disques existants
- Liste des disques disponibles

### Configuration Reseau

#### Samba
- Partage des repertoires via SMB
- Configuration automatic pour les VMs
- Acces depuis l'hote et d'autres machines du reseau

#### Netatalk (AFP)
- Partage via le protocol Apple Filing Protocol
- Compatible avec macOS
- Configuration pour les repertoires du VM Assistant

#### XQuartz
- Configuration pour l'affichage X11
- Permet l'affichage des VMs via X11
- Configuration des permissions

#### RAMDISK
- Utilisation de `/tmp/volatile_hd` pour le partage
- Configuration des permissions
- Accessible par toutes les VMs

### Fonctionnalités Avancees

#### Clipboard Partage

Pour activer le clipboard partage:

1. Configurez votre VM pour utiliser SPICE
2. Installez `spice-vdagent` dans la VM:
   - Debian/Ubuntu: `sudo apt install spice-vdagent`
   - Fedora: `sudo dnf install spice-vdagent`
3. Connectez-vous avec: `spicy -h 127.0.0.1 -p <port>`

#### Drag & Drop

Le drag & drop fonctionne automatiquement avec SPICE une fois que:

1. La VM utilise SPICE comme affichage
2. `spice-vdagent` est installe dans la VM

#### Multi-Ecrans

Pour configurer plusieurs ecrans:

1. Dans la creation de la VM, selectionnez SPICE comme affichage
2. Specifiez le nombre d'ecrans souhaite (jusqu'a 4)
3. Connectez-vous avec `spicy`

#### Debugging GDB

Pour debugger une application dans une VM depuis l'hote:

1. Activez le debugging GDB dans la configuration de la VM
2. Demarrez la VM
3. Dans la VM, installez `gdbserver`:
   - Debian/Ubuntu: `sudo apt install gdbserver`
   - RHEL/CentOS: `sudo yum install gdbserver`
   - Fedora: `sudo dnf install gdbserver`
4. Dans la VM, lancez votre application avec gdbserver:
   ```bash
   gdbserver :1234 /chemin/vers/votre/application
   ```
5. Sur l'hote, connectez GDB:
   ```bash
   gdb /chemin/vers/votre/application
   (gdb) target remote localhost:1234
   (gdb) continue
   ```

## Repertoires de Configuration

Tous les fichiers de configuration et donnees sont stockes dans:

- `~/.vm-assistant/` - Repertoire principal de configuration
- `~/.vm-assistant/vms/` - Configuration des VMs
- `~/.vm-assistant/isos/` - ISOs telecharges
- `~/.vm-assistant/disks/` - Disques virtuels
- `~/.vm-assistant/logs/` - Journaux
- `/tmp/volatile_hd/` - RAMDISK partage

## Configuration des VMs

Chaque VM a un fichier de configuration dans `~/.vm-assistant/vms/[nom_vm]/config` avec les parametres suivants:

```ini
# Architecture
arch=X86_64
machine=q35
cpu_type=host

# Ressources
ram=2048
cpu=2

# Stockage
disk=/Users/user/.vm-assistant/disks/vm1.qcow2
iso=/Users/user/.vm-assistant/isos/ubuntu.iso

# Reseau
network_mode=nat

# Affichage
display=spice
num_screens=2

# Options avancees
enable_clipboard=y
enable_dragdrop=y
enable_gdb=n

# Boot
boot_order=dc

# Partages
share_dir=/tmp/volatile_hd
```

## Resolution des Problemes

### XQuartz ne fonctionne pas

1. Verifiez que XQuartz est installe
2. Lancez XQuartz manuellement: `open -a XQuartz`
3. Executez: `xhost +local:`

### Erreur de permissions sur /tmp/volatile_hd

```bash
sudo chmod 1777 /tmp/volatile_hd
sudo chown root:wheel /tmp/volatile_hd
```

### Samba ne demarre pas

1. Verifiez que Samba est installe: `port installed samba4`
2. Verifiez la configuration: `/opt/local/etc/samba/smb.conf`
3. Demarrez manuellement: `sudo smbd -D`

### Netatalk ne demarre pas

1. Verifiez que Netatalk est installe: `port installed netatalk`
2. Verifiez la configuration: `/opt/local/etc/netatalk/afpd.conf`
3. Demarrez manuellement: `sudo afpd -d -F /opt/local/etc/netatalk/afpd.conf`

### QEMU n'est pas trouve

1. Verifiez que QEMU est installe: `port installed qemu`
2. Verifiez que le chemin est correct: `/opt/local/bin/qemu-system-*`

## Desinstallation

Pour desinstaller le VM Assistant:

```bash
# Supprimer les scripts
sudo rm -f /usr/local/bin/vm-assistant*

# Supprimer les repertoires de configuration
rm -rf ~/.vm-assistant

# Optionnel: Supprimer le RAMDISK (attention, cela supprimera tous les fichiers)
# sudo rm -rf /tmp/volatile_hd
```

## Contribution

Les contributions sont les bienvenues! Pour contribuer:

1. Fork le projet
2. Creer une branche pour votre fonctionnalite
3. Commit vos changements
4. Push vers la branche
5. Ouvrir une Pull Request

## Licence

Ce projet est distribué sous la licence MIT. Voir le fichier LICENCE pour plus de details.

## Auteur

Developpe pour les developpeurs d'applications ayant besoin d'une solution complete de gestion de VMs sur macOS.

## Remerciements

- La communaute QEMU pour leur excellent travail
- Les mainteneurs de MacPorts pour la gestion des packages
- Les developpeurs de SPICE pour les fonctionnalites avancees d'affichage
- La communaute open source en general
