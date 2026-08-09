# Guide de Debugging pour MacOS71_GDB_ICMP_Test
# Depuis ce Host (macOS) vers QEMU + GDB

## Sommaire
1. Pre-requis et Verification
2. Installation de Retro68
3. Compilation de l'Application
4. Configuration de l'Environnement QEMU
5. Installation de Mac OS 7.1
6. Demarrage de QEMU avec Support GDB
7. Session de Debugging avec GDB
8. Commandes GDB Essentielles
9. Script Automatise
10. Depannage

---

## 1. Pre-requis et Verification

### Verification initiale des outils
```bash
echo "=== Verification des Pre-requis ==="
which Retro68 2>&1 || echo "Retro68 non installe"
which gdb-multiarch 2>&1 || echo "gdb-multiarch non installe"
which qemu-system-ppc 2>&1 || echo "qemu-system-ppc non installe"
ls /opt/local/bin/m68k-elf-* 2>&1 | wc -l
ls /tmp/volatile_hd/MacROMan/TestImages/*.ROM 2>&1 | wc -l
ls /tmp/volatile_hd/*.ISO 2>&1 | grep -i mac | wc -l
```

---

## 2. Installation de Retro68

```bash
cd /tmp/volatile_hd/vm_assistant/vm_clients_3rdparty/macos/
git clone https://github.com/automatedjdw/Retro68.git
cd Retro68
xcodebuild -scheme Retro68 -configuration Release
export PATH="/tmp/volatile_hd/vm_assistant/vm_clients_3rdparty/macos/Retro68/Build/Products/Release:$PATH"
Retro68 --version
```

---

## 3. Compilation de l'Application

```bash
cd /tmp/volatile_hd/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test
make -f Makefile.retro68 clean
make -f Makefile.retro68
```

Ou manuellement:
```bash
Retro68 -g -O0 -m68040 -I src src/main.c src/gdb_test.c src/icmp_test.c -o build/MacOS71_GDB_ICMP_Test
```

---

## 4. Configuration de l'Environnement QEMU

### Verifier les fichiers
```bash
ROM_FILE=$(ls /tmp/volatile_hd/MacROMan/TestImages/*.ROM 2>/dev/null | head -1)
NDRVLOADER=$(find /tmp/volatile_hd /Users/xenon -name "ppc-ndrvloader" 2>/dev/null | head -1)
if [ -z "$NDRVLOADER" ]; then
    curl -L https://github.com/automatedjdw/qemu-macOS/raw/main/ppc-ndrvloader -o /tmp/volatile_hd/ppc-ndrvloader
    chmod +x /tmp/volatile_hd/ppc-ndrvloader
    NDRVLOADER="/tmp/volatile_hd/ppc-ndrvloader"
fi
mkdir -p /tmp/volatile_hd/disks
[ ! -f "/tmp/volatile_hd/disks/macos71.qcow2" ] && qemu-img create -f qcow2 /tmp/volatile_hd/disks/macos71.qcow2 2G
```

---

## 5. Installation de Mac OS 7.1

```bash
qemu-system-ppc \
    -M mac99 -m 512M -cpu 68040 \
    -bios /tmp/volatile_hd/MacROMan/TestImages/68040.ROM \
    -drive file=/tmp/volatile_hd/disks/macos71.qcow2,format=qcow2,if=ide \
    -drive file=/tmp/volatile_hd/MAC_OS_7-6-1_RETAIL.ISO,media=cdrom \
    -device loader,addr=0x4000000,file=/tmp/volatile_hd/ppc-ndrvloader \
    -fsdev local,path=/tmp/volatile_hd,id=fsdev0 \
    -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare
```

Suivre les instructions dans QEMU pour installer Mac OS 7.1.

---

## 6. Demarrage de QEMU avec Support GDB

```bash
qemu-system-ppc \
    -M mac99 -m 512M -cpu 68040 \
    -bios /tmp/volatile_hd/MacROMan/TestImages/68040.ROM \
    -drive file=/tmp/volatile_hd/disks/macos71.qcow2,format=qcow2 \
    -gdb tcp::1234 -S \
    -device loader,addr=0x4000000,file=/tmp/volatile_hd/ppc-ndrvloader \
    -fsdev local,path=/tmp/volatile_hd,id=fsdev0 \
    -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare \
    -prom-env "auto-boot?=true" \
    -display cocoa
```

---

## 7. Session de Debugging avec GDB

**Terminal 1 (QEMU):**
```bash
# Executer la commande QEMU ci-dessus
```

**Terminal 2 (GDB):**
```bash
gdb-multiarch
target remote localhost:1234
file /tmp/volatile_hd/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test/build/MacOS71_GDB_ICMP_Test
break main
break test_gdb_function
break test_icmp_function
continue
```

**Dans la VM:**
1. Ouvrir le partage "hostshare"
2. Copier MacOS71_GDB_ICMP_Test sur le bureau
3. Double-cliquer pour lancer
4. Cliquer sur les boutons pour tester

---

## 8. Commandes GDB Essentielles

### Registres 68k
```gdb
info registers d0 d1 d2 d3 d4 d5 d6 d7
info registers a0 a1 a2 a3 a4 a5 a6 a7
print/x $d0
print/x $pc
```

### Memoire
```gdb
x/16xw 0x00100000
x/16xb 0x00100000
x/8xw gGDBTestBlock
```

### Variables
```gdb
print gTestValue
print gGDBTestBlock
print/x gTestArray
```

### Execution
```gdb
stepi    # Un instruction
nexti    # Passer instruction
continue # Continuer
next     # Ligne suivante (meme fonction)
step     # Ligne suivante (entrer dans appels)
```

### Pile d'appel
```gdb
backtrace
backtrace full
frame 1
info args
info locals
```

### Breakpoints
```gdb
info breakpoints
delete 1
disable 1
enable 1
break test_gdb_function if gTestValue == 0xDEADBEEF
watch gTestValue
break *0x00000400
```

---

## 9. Script Automatise

```bash
#!/bin/bash
# /tmp/volatile_hd/debug_macos71.sh

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

error_exit() { echo -e "${RED}[ERREUR]${NC} $1" >&2; exit 1; }
info_msg() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Etape 1: Verification
info_msg "Verification des prerequis..."
command -v Retro68 &>/dev/null || { info_msg "Installation de Retro68..."; cd /tmp/volatile_hd/vm_assistant/vm_clients_3rdparty/macos/ && git clone https://github.com/automatedjdw/Retro68.git && cd Retro68 && xcodebuild -scheme Retro68 -configuration Release; }

# Etape 2: Compilation
info_msg "Compilation..."
cd /tmp/volatile_hd/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test
make -f Makefile.retro68 clean 2>/dev/null; make -f Makefile.retro68 || error_exit "Compilation echouee"

# Etape 3: Copie
cp build/MacOS71_GDB_ICMP_Test /tmp/volatile_hd/ || error_exit "Copie echouee"

# Etape 4: Verification QEMU
ROM_FILE=$(ls /tmp/volatile_hd/MacROMan/TestImages/*.ROM 2>/dev/null | head -1)
NDRVLOADER=$(find /tmp/volatile_hd /Users/xenon -name "ppc-ndrvloader" 2>/dev/null | head -1)
[ ! -f "/tmp/volatile_hd/disks/macos71.qcow2" ] && qemu-img create -f qcow2 /tmp/volatile_hd/disks/macos71.qcow2 2G

# Etape 5: Instructions
info_msg "INSTRUCTIONS:"
info_msg "1. QEMU demarre avec GDB sur port 1234"
info_msg "2. Dans un autre terminal: gdb-multiarch"
info_msg "3. (gdb) target remote localhost:1234"
info_msg "4. (gdb) file /tmp/volatile_hd/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test/build/MacOS71_GDB_ICMP_Test"
info_msg "5. (gdb) break main; continue"
info_msg "6. Dans VM: Ouvrir hostshare, copier app, lancer"

# Etape 6: Demarrer QEMU
qemu-system-ppc \
    -M mac99 -m 512M -cpu 68040 \
    -bios "$ROM_FILE" \
    -drive file=/tmp/volatile_hd/disks/macos71.qcow2,format=qcow2 \
    -gdb tcp::1234 -S \
    -device loader,addr=0x4000000,file="$NDRVLOADER" \
    -fsdev local,path=/tmp/volatile_hd,id=fsdev0 \
    -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare \
    -prom-env "auto-boot?=true"
```

---

## 10. Depannage

| Probleme | Solution |
|----------|----------|
| Retro68: command not found | Executer l'installation dans la section 2 |
| xcrun error | xcode-select --install |
| ROM manquant | Ajouter ROM dans /tmp/volatile_hd/MacROMan/TestImages/ |
| Could not connect to remote target | Verifier QEMU demarre avec -gdb tcp::1234 -S |
| No symbol table loaded | Compiler avec -g, charger avec file dans GDB |
| Breakpoints non atteints | Verifier chemin dans file avec GDB |

---

## 11. Resume des Commandes Cles

**Workflow minimal:**
```bash
# Compiler
cd /tmp/volatile_hd/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test
make -f Makefile.retro68

# Copier
cp build/MacOS71_GDB_ICMP_Test /tmp/volatile_hd/

# Terminal 1: QEMU
qemu-system-ppc -M mac99 -m 512M -cpu 68040 \
    -bios /tmp/volatile_hd/MacROMan/TestImages/68040.ROM \
    -drive file=/tmp/volatile_hd/disks/macos71.qcow2,format=qcow2 \
    -gdb tcp::1234 -S \
    -device loader,addr=0x4000000,file=/tmp/volatile_hd/ppc-ndrvloader \
    -fsdev local,path=/tmp/volatile_hd,id=fsdev0 \
    -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare

# Terminal 2: GDB
gdb-multiarch
(gdb) target remote localhost:1234
(gdb) file /tmp/volatile_hd/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test/build/MacOS71_GDB_ICMP_Test
(gdb) break main
(gdb) continue
```

---

*Derniere mise a jour: 9 aout 2026*
*Projet: VM Assistant*
