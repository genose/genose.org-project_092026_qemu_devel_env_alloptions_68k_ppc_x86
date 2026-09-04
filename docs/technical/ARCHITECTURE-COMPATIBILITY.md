# Notes Techniques - VM Assistant

Ce document contient des informations techniques, des astuces et des solutions aux problèmes courants.

---

## 📋 Table des matières

- [Architectures supportées](#-architectures-supportées)
- [Compatibilité CPU/ROM/Mac OS](#-compatibilité-cpurommac-os)
- [Options QEMU avancées](#-options-qemu-avancées)
- [Debugging avancé](#-debugging-avancé)
- [Réseau avancé](#-réseau-avancé)
- [Partage de fichiers](#-partage-de-fichiers)
- [Astuces Mac OS 7-9](#-astuces-mac-os-7-9)
- [Solutions aux problèmes courants](#-solutions-aux-problèmes-courants)
- [Benchmark et performances](#-benchmark-et-performances)
- [Références utiles](#-références-utiles)

---

## 🖥️ Architectures supportées

### PowerPC (ppc)

| Modèle | CPU QEMU | Machine QEMU | VIA | Taille ROM | Mac OS supporté | Notes |
|--------|----------|--------------|-----|------------|------------------|-------|
| 601 | 601 | g3beige | pmu | 1MB | 7.1.2-9.1 | Premier PowerPC |
| 603 | 603 | g3beige | pmu | 1MB | 7.5-9.1 | |
| 604 | 604 | g3beige | pmu | 1MB | 7.1.2-9.1 | |
| 604e | 604e | mac99 | pmu/cuda | 1MB | 7.1.2-9.1 | |
| G3 (750) | 750 | mac99 | pmu/cuda | 1MB | 7.5.5-9.1 | |
| G4 (7400) | 7400 | mac99 | pmu/cuda | 1MB | 7.6-9.2.2 | |
| G4 (7450) | 7450 | mac99 | pmu/cuda | 1MB | 7.6-9.2.2 | |
| G4 (7455) | 7455 | mac99 | pmu/cuda | 1MB | 7.6-9.2.2 | Recommandé |
| G4 (7447) | 7447 | mac99 | pmu/cuda | 1MB | 7.6-9.2.2 | |

**Note :** La machine `g3beige` ne supporte pas le paramètre `via`. Utiliser `mac99` pour `via=pmu` ou `via=cuda`.

### Motorola 68k

| Modèle | CPU QEMU | Machine QEMU | Taille ROM | Mac OS supporté | Notes |
|--------|----------|--------------|------------|------------------|-------|
| 68000 | 68000 | ? | 64-256KB | 1.0-6.0.x | Mac 128K, 512K, Plus |
| 68020 | m68k | ? | 256-512KB | 6.0-7.5.5 | Mac II, SE |
| 68030 | 68030 | ? | 512KB-1MB | 6.0-7.6.1 | Mac IIci, IIsi, LC |
| 68040 | 68040 | ? | 512KB-1MB | 7.0-7.6.1 | Quadra, Centris |

**Note :** QEMU support 68k est limité. Pour de meilleurs résultats, utiliser Basilisk II ou Sheepshaver.

### x86_64

| Modèle | CPU QEMU | Machine QEMU | Accélération | OS supporté |
|--------|----------|--------------|--------------|-------------|
| Generic | host | q35 | hvf/kvm | Linux, Windows, macOS (via KVM) |
| Core2Duo | core2duo | q35 | hvf | Linux, Windows |
| Nehalem | nehalem | q35 | hvf | Linux, Windows |

### ARM

| Modèle | CPU QEMU | Machine QEMU | Accélération | OS supporté |
|--------|----------|--------------|--------------|-------------|
| Generic | cortina-a72 | virt | hvf | Linux ARM64 |
| aarch64 | host | virt | hvf | macOS 11+ (via KVM) |

---

## 🔗 Compatibilité CPU/ROM/Mac OS

### PowerPC + Mac OS 7.x

| CPU | ROM Recommandé | Mac OS | Notes |
|-----|----------------|--------|-------|
| 601 | 9FEB69B3 (PM 6100/7100/8100) | 7.1.2-9.1 | **4MB ROM** - Nécessite QEMU patché |
| 601 | EC904829 (LC III) | 7.1-7.6.1 | **1MB ROM** - Fonctionne avec QEMU standard |
| 604 | 9630C68B (PM 7200/7500) | 7.5.2-9.1 | **4MB ROM** - Nécessite QEMU patché |
| 604 | E33B2724 (PB 160/180) | 7.1-7.6.1 | **1MB ROM** - Fonctionne avec QEMU standard |

### PowerPC + Mac OS 8.x-9.x

| CPU | ROM Recommandé | Mac OS | Notes |
|-----|----------------|--------|-------|
| 750 | 78F57389 (PM G3) | 8.0-10.2.8 | **4MB ROM** - Nécessite QEMU patché |
| 7455 | 78FDB784 (G3 Minitower) | 8.0-10.2.8 | **4MB ROM** - Nécessite QEMU patché |
| 7455 | NDRV loader | 7.6-9.2.2 | Fonctionne sans ROM spécifique |

### 68k + Mac OS 6-7

| CPU | ROM Recommandé | Mac OS | Notes |
|-----|----------------|--------|-------|
| 68030 | 368CADFE (IIci) | 6.0.4-7.6.1 | **512KB ROM** |
| 68030 | 4147DD77 (IIfx) | 6.0.5-7.6.1 | **512KB ROM** |
| 68030 | 36B7FB6C (IIsi) | 6.0.7-7.6.1 | **512KB ROM** |
| 68030 | ECBBC41C (LC III) | 7.1-7.6.1 | **1MB ROM** |

---

## ⚙️ Options QEMU avancées

### Options de boot

```bash
# Boot depuis CDROM
-boot order=d
-boot d

# Boot depuis disque
-boot order=c
-boot c

# Boot avec delay (pour OpenBIOS)
-prom-env "auto-boot?=true"
-prom-env "boot-delay=5"

# Boot device spécifique
-prom-env "boot-device=cd:,\install"
-prom-env "boot-device=hd:0"
```

### Options OpenBIOS

```bash
# Forcer le boot
-prom-env "auto-boot?=true"

# Commande de boot
-prom-env "boot-command=init-program go"

# Arguments de boot
-prom-env "boot-args=-v"
-prom-env "boot-args=console=ttyS0"

# Périphérique de boot
-prom-env "boot-device=cd:0"
-prom-env "boot-device=hd:0"
```

### Accélération

```bash
# PowerPC
-accel tcg,tb-size=128

# x86_64 (macOS)
-accel hvf

# x86_64 (Linux)
-accel kvm

# ARM (macOS)
-accel hvf
```

### Options graphiques

```bash
# VGA standard
-vga std

# VGA virtio
-vga virtio

# Pas de VGA + device séparé
-nodefaults
-vga none
-device VGA,vgamem_mb=16,edid=on

# Multi-écrans (Dual-PCI VGA)
-device VGA,edid=on,vgamem_mb=64,id=video0,xres=1024,yres=768
-device VGA,edid=on,vgamem_mb=64,id=video1,xres=1024,yres=768

# Multi-écrans (Graphic Engine - UTM)
-device graphic-drawing-engine,heads=2
```

---

## 🐛 Debugging avancé

### Configuration GDB avec QEMU

```bash
# Démarrer QEMU en mode pause
-S

# Activer le serveur GDB
-gdb dev:host:1234

# Pour le debugging série
-serial stdio 
-monchardev mode=readline,chardev=serial0
```

### Commandes GDB utiles pour PowerPC

```bash
# Se connecter
(gdb) target remote localhost:1234

# Voir les registres
(gdb) info registers
(gdb) info all-registers

# Voir la mémoire
(gdb) x/10x $sp         # Stack
(gdb) x/10i $pc         # Instructions

# Poser des breakpoints
(gdb) break *0x1000      # Adresse absolue
(gdb) break main        # Symbole

# Exécuter
(gdb) continue
(gdb) next
(gdb) step

# Voir les symboles
(gdb) info functions
(gdb) info variables

# Quitter
(gdb) quit
```

### Debugging série

```bash
# Rediriger la console série vers un fichier
-serial file:/tmp/qemu_serial.log

# Rediriger vers un terminal (screen)
-serial tcp::4444,server,nowait
# Puis : screen /dev/ttyS0 115200
```

### Logs QEMU

```bash
# Logs complets
-d int,cpu_reset

# Logs spécifiques
-trace enable=*

# Sauvegarder les logs
-qemu -d int,cpu_reset -D /tmp/qemu_debug.log
```

---

## 🌐 Réseau avancé

### Modes réseau QEMU

#### Mode User
```bash
-netdev user,id=net0,net=192.168.100.0/24,dhcpstart=192.168.100.100
-device virtio-net-pci,netdev=net0
```

#### Mode TAP
```bash
# Créer l'interface TAP
sudo ifconfig tap0 create
sudo ifconfig tap0 up

# QEMU
-netdev tap,id=net0,ifname=tap0,script=no,downscript=no
-device virtio-net-pci,netdev=net0
```

#### Mode Socket
```bash
# Client
-netdev socket,id=net0,connect=192.168.1.100:1234

# Serveur
-netdev socket,id=net0,listen=:1234
```

### Port Forwarding

```bash
# SSH (port 22 de la VM → port 2222 de l'hôte)
-netdev user,id=net0,hostfwd=tcp::2222-:22

# HTTP (port 80 de la VM → port 8080 de l'hôte)
-netdev user,id=net0,hostfwd=tcp::8080-:80

# Plusieurs ports
-netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::3306-:3306
```

### Réseau NAT avec vmnet (macOS)

```bash
# Utiliser vmnet-shared (nécessite vmnet)
-device sungem,mac=52:54:00:12:34:56,netdev=net0
-netdev vmnet-shared,id=net0
```

### Configuration réseau complète

```bash
# Réseau avec DHCP, port forwarding, et nom de machine
-netdev user,id=net0,net=192.168.100.0/24,dhcpstart=192.168.100.100,hostfwd=tcp::2222-:22
-device virtio-net-pci,netdev=net0,mac=52:54:00:12:34:56
```

---

## 📁 Partage de fichiers

### virtio-9p (recommandé)

```bash
# Partage basique
-fsdev local,security_model=mapped,id=fsdev0,path=~/vm_assistant
-device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare

# Avec plus de sécurité
-fsdev local,security_model=passthrough,id=fsdev0,path=~/vm_assistant

# Plusieurs partages
-fsdev local,security_model=mapped,id=fsdev0,path=~/vm_assistant
-device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare
-fsdev local,security_model=mapped,id=fsdev1,path=/Users/xenon/CodeWarrior
-device virtio-9p-pci,id=fsdev1,fsdev=fsdev1,mount_tag=cw
```

### Accès dans la VM

**Linux :**
```bash
mount -t 9p -o trans=virtio,version=9p2000 hostshare /mnt/hostshare
```

**Mac OS X :**
```bash
# Le partage est automatiquement monté si le driver est chargé
# Sinon, utiliser:
mkdir /Volumes/hostshare
mount_virtiofs hostshare /Volumes/hostshare
```

**Mac OS 9 :**
```bash
# Utiliser AppleShare ou le partage via le NDRV loader
```

---

## 🍏 Astuces Mac OS 7-9

### Mac OS 7.6.1

#### Problèmes de boot

**Symptôme :** VM reste bloquée sur le BIOS

**Solutions :**
1. Utiliser un ROM 1MB compatible (ex: E33B2724)
2. Ajouter `-prom-env "auto-boot?=true"`
3. Forcer le boot depuis CDROM : `-boot d`
4. Utiliser le NDRV loader : `-device loader,addr=0x4000000,file=ppc-ndrvloader`

**Commande fonctionnelle :**
```bash
qemu-system-ppc \
  -bios "~/vm_assistant/vm-assistant/resources/roms/MacROMan/TestImages/1MB ROMs/1992-07-22 - E33B2724 - PB160, PB165, PB165c, PB180, PB180c - 7.1-7.6.1 - 4-14M.ROM" \
  -machine mac99,via=pmu \
  -cpu 604 \
  -m 256M \
  -display cocoa \
  -cdrom /private~/vm_assistant/MAC_OS_7-6-1_RETAIL.ISO \
  -boot d \
  -device loader,addr=0x4000000,file=/Users/xenon/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu/ppc-ndrvloader \
  -prom-env "auto-boot?=true" \
  -prom-env "boot-device=cd:,\install"
```

#### Commandes OpenBIOS utiles

Dans la console OpenBIOS (si la VM s'arrête) :
```
# Voir les périphériques
ls

# Boot manuel depuis CDROM
boot cd:,\install

# Boot depuis disque
boot hd:0

# Voir les variables
printenv

# Modifier une variable
setenv auto-boot? true

# Sauvegarder les changements
saveenv
```

### Mac OS 9

#### Problèmes de checksum

**Symptôme :** "checksum error" dans OpenBIOS

**Solutions :**
1. Vérifier l'intégrité de l'ISO : `shasum MAC_OS_9.2.2.iso`
2. Utiliser un ISO différent (ex: Mac_OS_9.2.2_Unsupported_G4s.iso)
3. Désactiver le checksum : `-prom-env "checksum?=false"` (ne fonctionne pas toujours)

#### Configuration optimale

```bash
qemu-system-ppc \
  -machine mac99,via=cuda \
  -cpu 7455 \
  -m 1024M \
  -display cocoa \
  -cdrom /chemin/Mac_OS_9.2.2.iso \
  -device loader,addr=0x4000000,file=/chemin/ppc-ndrvloader \
  -prom-env "auto-boot?=true" \
  -prom-env "vga-ndrv?=true"
```

---

## ❌ Solutions aux problèmes courants

### QEMU ne démarre pas

**Symptôme :** QEMU crash ou erreur de permission

**Solutions :**
```bash
# Vérifier que QEMU est installé
which qemu-system-ppc

# Vérifier les permissions
chmod +x ~/vm_assistant/vm-assistant/vm-assistant-*.sh

# Vérifier les dépendances
brew doctor  # Pour Homebrew
port doctor  # Pour MacPorts
```

### Pas de son

**Solution :**
```bash
# Utiliser coreaudio (macOS)
-audio coreaudio

# Ou désactiver le son
-nographic
```

### Souris/Clavier ne fonctionne pas

**Solutions :**
```bash
# Utiliser le device USB
-usb -device usb-mouse -device usb-kbd

# Ou utiliser le protocole PS/2
-device ps2-mouse -device ps2-kbd
```

### Partage de fichiers ne fonctionne pas

**Solutions :**
```bash
# Vérifier que le chemin existe
ls ~/vm_assistant

# Vérifier les permissions
chmod -R a+rw ~/vm_assistant

# Utiliser security_model=mapped
-fsdev local,security_model=mapped,id=fsdev0,path=~/vm_assistant
```

### QEMU bloque sur le BIOS

**Solutions :**
```bash
# Ajouter un ROM compatible
-bios /chemin/vers/ROM.ROM

# Forcer le boot
-prom-env "auto-boot?=true"

# Utiliser le bon CPU et machine
-machine mac99,via=cuda -cpu 7455
```

### Erreur "Property not found"

**Symptôme :** `Property 'mac99-machine.via' not found`

**Solution :** Utiliser `g3beige` au lieu de `mac99` pour les vieux CPUs :
```bash
-machine g3beige  # Pas de paramètre via
```

### Port déjà utilisé

**Symptôme :** `Port 2222 already in use`

**Solution :**
```bash
# Trouver le processus
lsof -i :2222

# Tuer le processus
kill <PID>

# Utiliser un autre port
-ssh_port=2223
```

---

## ⚡ Benchmark et performances

### Optimisation des performances

```bash
# Utiliser l'accélération disponible
-accel tcg,tb-size=128  # Pour PowerPC
-accel hvf           # Pour x86_64/ARM (macOS)
-accel kvm           # Pour x86_64 (Linux)

# Réduire la taille du TB
-tb-size=64          # Pour économiser la mémoire
-tb-size=256         # Pour de meilleures performances

# Utiliser plusieurs threads
-smp 2              # 2 CPU
-smp 4              # 4 CPU

# Optimiser la RAM
-m 2048M           # 2GB pour Mac OS 9
-m 512M            # 512MB pour Mac OS 7.6.1
```

### Benchmark CPU

```bash
# Dans la VM Linux
cat /proc/cpuinfo

# Benchmark simple
time echo "scale=5000; 4*a(1)" | bc -l

# sysbench (si installé)
sysbench --test=cpu --cpu-max-prime=20000 run
```

### Benchmark disque

```bash
# Dans la VM Linux
dd if=/dev/zero of=/tmp/test bs=1M count=1024

# hdparm
hdparm -tT /dev/vda
```

---

## 🔗 Références utiles

### Documentation QEMU
- **Site officiel** : https://qemu.org
- **Documentation** : https://qemu.readthedocs.io/
- **Man pages** : `man qemu-system-ppc`

### Projets apparentés
- **UTM** : https://mac.getutm.app/ - Émulateur macOS avec patches QEMU
- **QEMU Manager** : https://github.com/joevm/qemu-manager
- **Basilisk II** : https://github.com/cebix/macemu - Émulateur 68k
- **Sheepshaver** : https://github.com/cebix/sheepshaver - Émulateur PPC
- **Mac ROMan** : https://github.com/pruten/MacROMan - Collection de ROMs

### Communautés
- **QEMU Discuss** : https://lists.nongnu.org/mailman/listinfo/qemu-discuss
- **r/emulation** : https://reddit.com/r/emulation
- **MacRumors Forums** : https://forums.macrumors.com/forums/mac-programming.159/

### Outils complémentaires
- **qemu-img** : Gestion des disques
- **virt-manager** : Interface graphique pour QEMU (Linux)
- **libvirt** : Gestion avancée des VMs

---

## 📝 Notes de version

### Version 2.0 (en développement)
- Ajout du support GDB
- Ajout du support SSH
- Ajout du support Netatalk
- Ajout de la collection de ROMs MacROMan
- Correction de la génération de start.sh

### Version 1.0
- Support QEMU de base
- Support UTM
- Menu interactif
- Multi-écrans
- Partage de fichiers

---

## 🎯 Roadmap

### Version 2.1
- [ ] Intégration CodeWarrior
- [ ] Templates de VM prédéfinis
- [ ] Support Docker
- [ ] Tests automatisés

### Version 3.0
- [ ] Interface graphique
- [ ] Support Windows VMs
- [ ] Intégration CI/CD
- [ ] Support cloud (AWS, GCP)

---

*Dernière mise à jour : 8 août 2025*
