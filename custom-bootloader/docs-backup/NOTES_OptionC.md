# Option C - Guide d'utilisation

## Debugging avec GDB, SSH et Netatalk

L'option C permet d'activer le debugging (GDB), l'accès SSH et le partage AppleShare (Netatalk) pour vos VMs QEMU.

## Prérequis

### GDB (GNU Debugger)
- **Installation** : `brew install gdb` ou `sudo port install gdb`
- **Pour PowerPC** : `brew install FiloSottile/musl-cross/musl-cross` (inclut gdb-multiarch)
- **Pour 68k** : `brew install --cask m68k-gdb`

### SSH
- Préinstallé sur macOS/Linux
- Nécessite un serveur SSH dans la VM (OpenSSH)

### Netatalk (AppleShare)
- **Installation** : `brew install netatalk` ou `sudo port install netatalk`
- Nécessite `sudo` pour démarrer le service afpd

---

## Configuration

### Lors de la création d'une VM

Dans le menu de création, après avoir configuré l'architecture, le stockage et le réseau, vous verrez :

```
Option C - Configuration Debug/Network
=======================================
Activer GDB debugging [n]: y
  Port GDB [1234]: 1234
Activer SSH forward [n]: y
  Port SSH host [2222]: 2222
Activer Netatalk (AppleShare) [n]: y
  Nom du partage [VM_nom_vm]: VM_MaVM
```

### Lors de l'édition d'une VM

Dans le menu d'édition, sélectionnez l'option `C` :

```
Edit VM Configuration
=====================
  [1] Architecture (arch/machine/cpu/via)
  [2] Resources (ram/cpu)
  [3] Storage (disk/iso)
  [4] Display (display/num_screens/multi_screen_method)
  [5] Network (network_mode)
  [6] Sharing (share_dir)
  [7] ROM file (for old Mac OS)
  [C] Option C - Debug/Network (GDB/SSH/Netatalk)
  [8] Show current config
  [9] Save and exit
  [0] Exit without saving

Select option [8]: C
```

---

## Utilisation

### 1. Démarrer la VM avec l'option C

```bash
./vm-assistant-vm.sh start ma_vm
```

Si l'option C est activée, vous verrez des messages comme :
```
[INFO] GDB debugging active sur port: 1234
[INFO] SSH forwarding active: host:2222 -> guest:22
[INFO] Netatalk partage demarre: VM_MaVM
```

### 2. Connexion GDB

**Pour PowerPC (Mac OS 9, Mac OS X) :**
```bash
# Dans un nouveau terminal
gdb-multiarch
(gdb) target remote localhost:1234
(gdb) continue
```

**Pour 68k :**
```bash
m68k-elf-gdb mon_programme
(gdb) target remote localhost:1234
(gdb) continue
```

**Commandes GDB utiles :**
```
(gdb) break main          # Poser un breakpoint
(gdb) run                 # Démarrer
(gdb) next                # Exécuter la ligne suivante
(gdb) step                # Entrer dans la fonction
(gdb) print variable     # Afficher une variable
(gdb) backtrace           # Voir la pile d'appel
(gdb) info registers      # Voir les registres
(gdb) quit                # Quitter
```

### 3. Connexion SSH

**Pour Linux dans la VM :**
```bash
# Dans la VM, installez et activez SSH
sudo apt update
sudo apt install openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
```

**Depuis l'hôte :**
```bash
ssh utilisateur@localhost -p 2222
```

**Avec clé SSH :**
```bash
# Générer une paire de clés
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vm_key -N ""

# Copier la clé publique dans la VM
ssh-copy-id -i ~/.ssh/vm_key.pub utilisateur@localhost -p 2222

# Connexion
ssh -i ~/.ssh/vm_key utilisateur@localhost -p 2222
```

### 4. Connexion Netatalk (AppleShare)

**Depuis un Mac (Finder) :**
1. Ouvrez Finder
2. `Fichier > Se connecter au serveur...` (ou `Cmd+K`)
3. Adresse : `afp://localhost/VM_MaVM`
4. Protocole : Apple File Protocol (AFP)

**Depuis la ligne de commande :**
```bash
open afp://localhost/VM_MaVM
```

**Montage manuel :**
```bash
mount_afp afp://utilisateur@localhost/VM_MaVM /Volumes/VM_MaVM
```

---

## Configuration du fichier `config`

Les paramètres de l'option C sont stockés dans le fichier `config` de la VM :

```bash
# Option C - Debug/Network
enable_gdb=y
gdb_port=1234
enable_ssh=y
ssh_port=2222
enable_netatalk=y
netatalk_share_name=VM_MaVM
```

---

## Configuration avancée

### GDB pour différentes architectures

| Architecture | GDB recommandé | Installation |
|-------------|----------------|-------------|
| PowerPC (G4, 604, 601) | gdb-multiarch | `brew install gdb` |
| 68k (68040) | m68k-elf-gdb | `brew install --cask m68k-gdb` |
| x86_64 | gdb | `brew install gdb` |
| ARM | gdb-multiarch | `brew install gdb` |

### Netatalk pour différents OS invités

Le partage Netatalk fonctionne particulièrement bien avec :
- Mac OS 7.x, 8.x, 9.x
- Mac OS X 10.2-10.6 (nécessite activation de AFP)
- Linux avec netatalk client

### Configuration réseau pour GDB/SSH

Par défaut, l'option C utilise :
- **GDB** : `-gdb tcp::PORT -S` (QEMU attend le debugger)
- **SSH** : `-netdev user,id=sshnet0,hostfwd=tcp::PORT-:22` (forwarding de port)

Ces options sont compatibles avec les modes réseau NAT et User.

### Configuration Netatalk manuelle

Si vous préférez démarrer Netatalk manuellement :

```bash
# Créer une configuration custom
cat > /tmp/afp_vm.conf << EOF
[Global]
  mimic model = RackMac
  uam list = uams_guest.so,uams_dhx.so,uams_dhx2.so
  guest account = guest
  log file = /tmp/vm-assistant-netatalk.log
  max connections = 20

[VM_Shares]
  path = /tmp/volatile_hd
  valid users = @* guest
  rwlist = @* guest
  file perm = 0664
  directory perm = 0775
  cnid scheme = dbd
EOF

# Démarrer manuellement
sudo afpd -F /tmp/afp_vm.conf -d
```

---

## Dépannage

### GDB ne se connecte pas
- **Vérifiez** : La VM est démarrée avec `-S` (pause au début)
- **Vérifiez** : Le port est ouvert : `nc -z localhost 1234`
- **Solution** : Utilisez `gdb-multiarch` pour supporter plusieurs architectures

### SSH ne fonctionne pas
- **Vérifiez** : La VM a un serveur SSH installé et démarré
- **Vérifiez** : Le port est forwardé : `lsof -i :2222`
- **Solution** : Dans la VM, vérifiez que SSH écoute : `netstat -tlnp | grep 22`

### Netatalk ne démarre pas
- **Problème** : `directory_create_or_exist: mkdir failed on directory /usr/local/Cellar/samba/...`
- **Solution** : Le script utilise `/tmp/samba_private` comme répertoire de travail
- **Vérifiez** : `ps aux | grep afpd` pour voir si le processus est en cours
- **Logs** : `/tmp/vm-assistant-netatalk.log`

### Problème de permissions Netatalk
- **Solution** : Ajoutez votre utilisateur au groupe netatalk
- **macOS** : `sudo dseditgroup -o edit -a $USER -t user _lpadmin`
- **Linux** : `sudo usermod -aG netatalk $USER`

### Connexion AFP échoue
- **Vérifiez** : Le partage est correctement configuré
- **Testez** : `smbutil statshares -a guest //localhost`
- **Solution** : Utilisez `open afp://localhost/NOM_DU_PARTAGE` dans Terminal

---

## Exemples complets

### Exemple 1 : VM PowerPC avec GDB pour développement Mac OS 9

```bash
# Créer une VM
./vm-assistant-vm.sh create macos9_dev

# Configuration
# - Architecture: G4
# - CPU: 7455
# - RAM: 1024MB
# - Option C: GDB=y (port 1234), SSH=n, Netatalk=y (share: VM_Dev)

# Démarrer la VM
./vm-assistant-vm.sh start macos9_dev

# Dans un autre terminal, connecter GDB
gdb-multiarch
(gdb) target remote localhost:1234
(gdb) set architecture powerpc
(gdb) continue
```

### Exemple 2 : VM Linux avec SSH et partage de fichiers

```bash
# Créer une VM
./vm-assistant-vm.sh create linux_dev

# Configuration
# - Architecture: x86_64
# - RAM: 2048MB
# - Option C: GDB=n, SSH=y (port 2222), Netatalk=n

# Démarrer la VM
./vm-assistant-vm.sh start linux_dev

# Installer SSH dans la VM (Debian/Ubuntu)
sudo apt update && sudo apt install openssh-server -y

# Depuis l'hôte, se connecter
ssh utilisateur@localhost -p 2222
```

### Exemple 3 : VM complète avec toutes les options

```bash
# Créer une VM
./vm-assistant-vm.sh create full_dev

# Configuration
# - Architecture: G4
# - RAM: 2048MB
# - Partage: /tmp/volatile_hd
# - Option C: GDB=y (1234), SSH=y (2222), Netatalk=y (VM_Full)

# Démarrer
./vm-assistant-vm.sh start full_dev

# Accéder aux services
# GDB: gdb-multiarch -ex 'target remote localhost:1234'
# SSH: ssh user@localhost -p 2222
# AFP: open afp://localhost/VM_Full
```

---

## Commandes utiles VM Assistant

```bash
# Lister les VMs
./vm-assistant-vm.sh list

# Éditer une VM existante
./vm-assistant-vm.sh edit ma_vm

# Démarrer une VM
./vm-assistant-vm.sh start ma_vm

# Arrêter une VM (et Netatalk si démarré)
./vm-assistant-vm.sh stop ma_vm

# Vérifier l'installation (inclut Netatalk/GDB)
./vm-assistant-vm.sh menu
# Puis sélectionnez option 7

# Tester les connexions
./vm-assistant-test-connections.sh
```

---

## Fichiers importants

```
/tmp/volatile_hd/vm-assistant/
├── vm-assistant-vm.sh          # Script principal
├── vm-assistant-test-connections.sh  # Testeur de connexions
├── vm-assistant-network.sh     # Gestion Samba (existante)
└── NOTES_OptionC.md           # Ce fichier

~/.vm-assistant/
├── vms/
│   └── nom_vm/
│       ├── config              # Contient les params Option C
│       ├── start.sh            # Script de démarrage généré
│       └── pid                 # PID du processus QEMU
└── disks/
    └── nom_disque.qcow2
```

---

## Sécurité

⚠️ **Important** :
- Netatalk démarre avec des permissions ouvertes par défaut (guest access)
- Pour un environnement de production, configurez des utilisateurs et mots de passe
- GDB permet l'exécution de code arbitraire dans la VM
- SSH avec forward de port peut exposer votre VM au réseau

Pour sécuriser Netatalk :
```bash
# Modifier la configuration dans start_netatalk_share()
# Ajouter un utilisateur spécifique
sudo dscl . -create /Users/vmuser
sudo dscl . -create /Users/vmuser UserShell /bin/false
sudo dscl . -create /Users/vmuser home /tmp/vm_share
sudo dscl . -passwd /Users/vmuser motdepasse
```

---

## Performances

### GDB
- L'exécution pas-à-pas (step/next) peut être lente avec l'émulation QEMU
- Utilisez `-accel tcg,tb-size=128` pour améliorer les performances PowerPC

### Netatalk
- Netatalk est plus rapide que Samba pour les clients Mac OS classique
- Le partage via `/tmp/volatile_hd` (RAM disk) est ultra-rapide

### SSH
- Le forward de port fonctionne mieux avec le mode réseau User
- Pour NAT, vérifiez la connectivité avec `ping localhost` dans la VM

---

## Compatibilité

| Fonctionnalité | PowerPC | 68k | x86_64 | ARM |
|--------------|---------|-----|--------|------|
| GDB | ✅ | ✅ | ✅ | ✅ |
| SSH forwarding | ✅ | ✅ | ✅ | ✅ |
| Netatalk | ✅ | ✅ | ✅ | ✅ |
| Copier-Coller | ✅ | ❌ | ✅ | ✅ |
| Glisser-Déposer | ✅ | ❌ | ✅ | ✅ |

> **Note** : Le copier-coller et glisser-déposer nécessitent une configuration GUI supplémentaire dans QEMU (VNC, SPICE). L'option C active le partage de fichiers via Netatalk et l'accès SSH pour transférer des fichiers.

---

## Pour aller plus loin

### Intégration avec CodeWarrior

Pour debugger des applications CodeWarrior :

1. **Configurer la VM** : Activez GDB sur le port 1234
2. **Dans CodeWarrior** : Configurez le debugger pour se connecter à `localhost:1234`
3. **Démarrer la VM** : `./vm-assistant-vm.sh start ma_vm`
4. **Debugger** : Lancez le debug dans CodeWarrior

### Développement croisé

Utilisez SSH pour :
- Compiler sur l'hôte et transférer vers la VM
- Éditer des fichiers sur l'hôte via Netatalk
- Debugger avec GDB

Exemple de workflow :
```bash
# Sur l'hôte
vim mon_programme.c  # Éditer via Netatalk

# Compiler sur l'hôte (cross-compilation)
ppc-linux-gcc -o mon_programme mon_programme.c

# Transférer vers la VM via SSH
scp -P 2222 mon_programme user@localhost:/tmp/

# Exécuter et debugger
./vm-assistant-vm.sh start ma_vm
# Puis dans GDB : remote localhost:1234
```

---

## Historique

- **v2.1** : Ajout de l'option C (GDB, SSH, Netatalk)
- **v2.0** : Support UTM.app et ROMs
- **v1.0** : Gestion basique QEMU

---

## Support

Pour des questions ou problèmes :
- Vérifiez les logs : `/tmp/vm-assistant-netatalk.log`
- Testez les connexions : `./vm-assistant-test-connections.sh`
- Consultez le README.md pour la configuration générale
