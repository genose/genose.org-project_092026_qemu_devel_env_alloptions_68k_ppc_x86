#!/bin/bash

# VM Assistant - Gestion de machines virtuelles QEMU/UTM
# Version: 2.0 - Avec support UTM.app

CONFIG_DIR="$HOME/.vm-assistant"
VM_DIR="$CONFIG_DIR/vms"
DISK_DIR="$CONFIG_DIR/disks"
ISO_DIR="$CONFIG_DIR/isos"
SHARE_DIR="/tmp/volatile_hd"
ROM_DIR="/tmp/volatile_hd/MacROMan/TestImages"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_header() { echo -e "\n${BLUE}============================${NC}"; echo "$1"; echo -e "${BLUE}============================${NC}"; }

detect_utm() {
    if [ -d "/Applications/UTM.app" ]; then
        UTM_INSTALLED=true
        UTM_PATH="/Applications/UTM.app"
        UTM_QEMU_PATH="/Applications/UTM.app/Contents/Resources/qemu/bin"
    else
        UTM_INSTALLED=false
        UTM_PATH=""
        UTM_QEMU_PATH=""
    fi
    export UTM_INSTALLED UTM_PATH UTM_QEMU_PATH
}

qemu_device_exists() {
    local device="$1"
    if command -v qemu-system-ppc &>/dev/null; then
        qemu-system-ppc -device help 2>/dev/null | grep -q "$device" && return 0 || return 1
    else
        return 1
    fi
}

# Lister les ROMs disponibles
list_roms() {
    log_header "Liste des ROMs disponibles"
    
    if [ ! -d "$ROM_DIR" ]; then
        echo "  Répertoire ROM non trouvé: $ROM_DIR"
        return 1
    fi
    
    local found_roms=()
    local index=1
    
    # Chercher les fichiers .ROM et .rom
    while IFS= read -r -d '' file; do
        if [[ "$file" == *.ROM || "$file" == *.rom ]]; then
            found_roms+=("$file")
            local basename=$(basename "$file")
            # Extraire le modèle
            local model=$(echo "$basename" | sed 's/^[0-9-]* - //' | sed 's/ - [0-9A-F]*.*//')
            echo "  [$index] $model - $(du -h "$file" | cut -f1)"
            ((index++))
        fi
    done < <(find "$ROM_DIR" -type f \( -name "*.ROM" -o -name "*.rom" \) -print0 2>/dev/null)
    
    if [ ${#found_roms[@]} -eq 0 ]; then
        echo "  Aucun ROM trouvé"
        return 1
    fi
    
    read -p "Sélectionner un ROM [1-${#found_roms[@]}]: " rom_choice
    rom_choice=${rom_choice:-1}
    
    if [ "$rom_choice" -ge 1 ] && [ "$rom_choice" -le ${#found_roms[@]} ]; then
        selected_rom="${found_roms[$((rom_choice-1))]}"
        return 0
    fi
    
    return 1
}

list_isos() {
    log_header "Liste des ISOs disponibles"
    local iso_dirs=("$ISO_DIR" "$SHARE_DIR" "/tmp/volatile_hd")
    local found_isos=()
    local index=1
    for dir in "${iso_dirs[@]}"; do
        if [ -d "$dir" ]; then
            while IFS= read -r -d '' file; do
                if [[ "$file" == *.iso || "$file" == *.ISO ]]; then
                    found_isos+=("$file")
                    echo "  [$index] $(basename "$file")"
                    ((index++))
                fi
            done < <(find "$dir" -maxdepth 1 -type f \( -name "*.iso" -o -name "*.ISO" \) -print0 2>/dev/null)
        fi
    done
    if [ ${#found_isos[@]} -eq 0 ]; then
        echo "  Aucun ISO trouve"
        return 1
    fi
    read -p "Selectionner un ISO [1-${#found_isos[@]}]: " iso_choice
    iso_choice=${iso_choice:-1}
    if [ "$iso_choice" -ge 1 ] && [ "$iso_choice" -le ${#found_isos[@]} ]; then
        selected_iso="${found_isos[$((iso_choice-1))]}"
        return 0
    fi
    return 1
}

list_disks() {
    log_header "Liste des disques disponibles"
    local disk_dirs=("$DISK_DIR" "$SHARE_DIR" "/tmp/volatile_hd")
    local found_disks=()
    local index=1
    for dir in "${disk_dirs[@]}"; do
        if [ -d "$dir" ]; then
            while IFS= read -r -d '' file; do
                if [[ "$file" == *.img || "$file" == *.qcow2 || "$file" == *.raw ]]; then
                    found_disks+=("$file")
                    echo "  [$index] $(basename "$file")"
                    ((index++))
                fi
            done < <(find "$dir" -maxdepth 1 -type f \( -name "*.img" -o -name "*.qcow2" -o -name "*.raw" \) -print0 2>/dev/null)
        fi
    done
    if [ ${#found_disks[@]} -eq 0 ]; then
        echo "  Aucun disque trouve"
        return 1
    fi
    read -p "Selectionner un disque [1-${#found_disks[@]}]: " disk_choice
    disk_choice=${disk_choice:-1}
    if [ "$disk_choice" -ge 1 ] && [ "$disk_choice" -le ${#found_disks[@]} ]; then
        selected_disk="${found_disks[$((disk_choice-1))]}"
        return 0
    fi
    return 1
}

create_disk() {
    local vm_name=$1
    local default_size="20G"
    read -p "Taille du disque [$default_size]: " disk_size
    disk_size=${disk_size:-$default_size}
    local disk_path="$DISK_DIR/${vm_name}.qcow2"
    if [ -f "$disk_path" ]; then
        read -p "Un disque existe deja: $disk_path. Le remplacer? [y/N]: " replace
        if [ "$replace" != "y" ]; then
            return 0
        fi
    fi
    mkdir -p "$DISK_DIR"
    log_info "Creation du disque: $disk_path"
    qemu-img create -f qcow2 "$disk_path" "$disk_size" || {
        log_error "Echec de la creation du disque"
        return 1
    }
    selected_disk="$disk_path"
    return 0
}

edit_vm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"
    if [ ! -d "$vm_dir" ]; then
        log_error "VM not found: $vm_name"
        return 1
    fi
    if [ ! -f "$vm_config" ]; then
        log_error "Config not found: $vm_config"
        return 1
    fi
    source "$vm_config" 2>/dev/null || true
    log_info "Editing VM: $vm_name"
    while true; do
        echo "Edit VM Configuration"
        echo "====================="
        echo "  [1] Architecture (arch/machine/cpu/via)"
        echo "  [2] Resources (ram/cpu)"
        echo "  [3] Storage (disk/iso)"
        echo "  [4] Display (display/num_screens/multi_screen_method)"
        echo "  [5] Network (network_mode)"
        echo "  [6] Sharing (share_dir)"
        echo "  [7] ROM file (for old Mac OS)"
        echo "  [8] Show current config"
        echo "  [9] Save and exit"
        echo "  [0] Exit without saving"
        echo ""
        read -p "Select option [8]: " choice
        choice=${choice:-8}
        case "$choice" in
            1)
                echo "Current: arch=${arch:-G4}, machine=${machine:-mac99}, cpu_type=${cpu_type:-7455}, via=${via:-cuda}"
                echo "Available architectures:"
                echo "  PowerPC: G4, 604ev, 604, 601, ppc"
                echo "  68k: 68040, apollocore"
                echo "  x86: x86_64, i386, i86"
                echo "  ARM: arm, arm64"
                echo "  SPARC: sparc, sparc64"
                read -p "Architecture [${arch:-G4}]: " arch
                read -p "Machine [${machine:-mac99}]: " machine
                read -p "CPU type [${cpu_type:-7455}]: " cpu_type
                if [ "$arch" = "G4" ] || [ "$arch" = "604ev" ] || [ "$arch" = "604" ] || [ "$arch" = "601" ] || [ "$arch" = "ppc" ]; then
                    read -p "VIA type (pmu/cuda/none) [${via:-cuda}]: " via
                fi
                arch=${arch:-G4}
                machine=${machine:-mac99}
                cpu_type=${cpu_type:-7455}
                via=${via:-cuda}
                ;;
            2)
                read -p "RAM in MB [${ram:-768}]: " ram
                read -p "CPU count [${cpu:-1}]: " cpu
                ram=${ram:-768}
                cpu=${cpu:-1}
                ;;
            3)
                echo "  [A] Select existing disk"
                echo "  [B] Select existing ISO"
                echo "  [C] Clear disk"
                echo "  [D] Clear ISO"
                read -p "Option [A/B/C/D]: " storage_choice
                case "$storage_choice" in
                    A) list_disks && disk="$selected_disk" || echo "No disk selected";;
                    B) list_isos && iso="$selected_iso" || echo "No ISO selected";;
                    C) disk="";;
                    D) iso="";;
                esac
                ;;
            4)
                read -p "Display (cocoa/none) [${display:-cocoa}]: " display
                read -p "Number of screens [${num_screens:-1}]: " num_screens
                read -p "Multi-screen method (auto/dual-pci-vga/graphic-engine) [${multi_screen_method:-auto}]: " multi_screen_method
                display=${display:-cocoa}
                num_screens=${num_screens:-1}
                multi_screen_method=${multi_screen_method:-auto}
                ;;
            5)
                read -p "Network mode (nat/user/none) [${network_mode:-nat}]: " network_mode
                network_mode=${network_mode:-nat}
                ;;
            6)
                read -p "Share directory [${share_dir:-/tmp/volatile_hd}]: " share_dir
                share_dir=${share_dir:-/tmp/volatile_hd}
                ;;
            7)
                list_roms && rom_file="$selected_rom" || echo "No ROM selected"
                ;;
            8)
                echo "Current configuration:"
                echo "  arch=$arch machine=$machine cpu_type=$cpu_type via=$via"
                echo "  ram=$ram cpu=$cpu"
                echo "  disk=$disk iso=$iso"
                echo "  display=$display num_screens=$num_screens method=$multi_screen_method"
                echo "  network_mode=$network_mode share_dir=$share_dir"
                echo "  rom_file=${rom_file:-none}"
                ;;
            9)
                cat > "$vm_config" << CONFIG
# Configuration de la VM: $vm_name
# Date: $(date)
# Architecture
arch=${arch:-G4}
machine=${machine:-mac99}
cpu_type=${cpu_type:-7455}
# Ressources
ram=${ram:-768}
cpu=${cpu:-1}
# Stockage
disk=${disk:-}
iso=${iso:-}
# Reseau
network_mode=${network_mode:-nat}
# Affichage
display=${display:-cocoa}
num_screens=${num_screens:-1}
# Methode multi-ecran
multi_screen_method=${multi_screen_method:-auto}
# Partages
share_dir=${share_dir:-/tmp/volatile_hd}
via=${via:-cuda}
rom_file=${rom_file:-}
CONFIG
                log_info "Configuration saved for $vm_name"
                return 0
                ;;
            0) return 0 ;;
            *) echo "Invalid option" ;;
        esac
        echo ""
    done
}

start_qemu_vm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"
    if [ ! -d "$vm_dir" ]; then
        log_error "VM not found: $vm_name"
        return 1
    fi
    if [ ! -f "$vm_config" ]; then
        log_error "Config not found: $vm_config"
        return 1
    fi
    source "$vm_config" || return 1
    log_info "Starting VM QEMU: $vm_name"
    local arch="${arch:-G4}"
    local machine="${machine:-mac99}"
    local cpu_type="${cpu_type:-7455}"
    local ram="${ram:-768}"
    local cpu="${cpu:-1}"
    local display="${display:-cocoa}"
    local num_screens="${num_screens:-1}"
    local disk="${disk:-}"
    local iso="${iso:-}"
    local share_dir="${share_dir:-/tmp/volatile_hd}"
    local network_mode="${network_mode:-nat}"
    local via="${via:-cuda}"
    local multi_screen_method="${multi_screen_method:-auto}"
    local rom_file="${rom_file:-}"
    local qemu_args=()
    qemu_args+=("qemu-system-ppc")
    local utm_resources="/Users/xenon/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu"
    if [ -d "$utm_resources" ]; then
        qemu_args+=("-L" "$utm_resources")
    fi
    # ROM file (for old Mac OS like 7.6.1)
    if [ -n "$rom_file" ] && [ -f "$rom_file" ]; then
        # Check ROM size - QEMU PPC has 1MB limit for BIOS
        local rom_size=$(stat -f%z "$rom_file" 2>/dev/null || echo 0)
        if [ "$rom_size" -le 1048576 ]; then
            qemu_args+=("-bios" "$rom_file")
            log_info "Using ROM: $(basename "$rom_file")"
        else
            log_warn "ROM too large (${rom_size} bytes > 1MB). QEMU PPC BIOS limit is 1MB. ROM not loaded."
        fi
    fi
    qemu_args+=("-m" "${ram}M")
    qemu_args+=("-smp" "$cpu")
    case "$network_mode" in
        "nat")
            qemu_args+=("-device" "sungem,mac=52:54:00:12:34:56,netdev=net0")
            qemu_args+=("-netdev" "vmnet-shared,id=net0")
            ;;
        "user")
            qemu_args+=("-netdev" "user,id=net0,net=192.168.100.0/24,dhcpstart=192.168.100.100")
            qemu_args+=("-device" "virtio-net-pci,netdev=net0")
            ;;
    esac
    case "$display" in
        "cocoa") qemu_args+=("-display" "cocoa") ;;
        "none") qemu_args+=("-nographic") ;;
        *) qemu_args+=("-display" "cocoa") ;;
    esac
    if [ -d "$share_dir" ]; then
        qemu_args+=("-fsdev" "local,security_model=mapped,id=fsdev0,path=$share_dir")
        qemu_args+=("-device" "virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare")
    fi
    # Determiner le binaire QEMU approprié
    local qemu_cmd="qemu-system-ppc"
    case "$arch" in
        "apollocore"|"68040")
            qemu_cmd="qemu-system-m68k"
            ;;
        "x86_64"|"i386"|"i86")
            qemu_cmd="qemu-system-x86_64"
            if [ "$arch" = "i386" ]; then
                qemu_cmd="qemu-system-i386"
            fi
            ;;
        "arm")
            qemu_cmd="qemu-system-arm"
            ;;
        "arm64")
            qemu_cmd="qemu-system-aarch64"
            ;;
        "sparc")
            qemu_cmd="qemu-system-sparc"
            ;;
        "sparc64")
            qemu_cmd="qemu-system-sparc64"
            ;;
        *)
            qemu_cmd="qemu-system-ppc"
            ;;
    esac
    
    # Vérifier que le binaire QEMU existe
    if ! command -v "$qemu_cmd" &>/dev/null; then
        log_error "Binaire QEMU non trouve: $qemu_cmd"
        log_info "Installez avec: sudo port install $qemu_cmd ou brew install qemu"
        return 1
    fi
    
    # Remplacer le binaire dans les arguments
    qemu_args[0]="$qemu_cmd"
    
    case "$arch" in
        "G4"|"604ev"|"ppc"|"68040"|"601"|"604"|"750"|"7400")
            local ppc_machine="${machine:-mac99}"
            case "$arch" in
                "604ev"|"604"|"68040"|"601"|"750"|"7400") ppc_machine="g3beige" ;;
            esac
            if [ "$ppc_machine" = "g3beige" ]; then
                qemu_args+=("-machine" "${ppc_machine}")
            else
                qemu_args+=("-machine" "${ppc_machine},via=${via}")
            fi
            qemu_args+=("-cpu" "${cpu_type}")
            qemu_args+=("-accel" "tcg,tb-size=128")
            if [ "$num_screens" -gt 1 ]; then
                case "$multi_screen_method" in
                    "graphic-engine")
                        qemu_args+=("-device" "graphic-drawing-engine,heads=${num_screens}")
                        ;;
                    "dual-pci-vga")
                        qemu_args+=("-prom-env" "vga-ndrv?=true")
                        qemu_args+=("-g" "1024x768x32")
                        qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video0,xres=1024,yres=768")
                        for (( s=1; s<num_screens; s++ )); do
                            qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video$s,xres=1024,yres=768")
                        done
                        ;;
                    "auto"|"")
                        if qemu_device_exists "graphic-drawing-engine"; then
                            qemu_args+=("-device" "graphic-drawing-engine,heads=${num_screens}")
                        else
                            qemu_args+=("-prom-env" "vga-ndrv?=true")
                            qemu_args+=("-g" "1024x768x32")
                            qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video0,xres=1024,yres=768")
                            for (( s=1; s<num_screens; s++ )); do
                                qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video$s,xres=1024,yres=768")
                            done
                        fi
                        ;;
                esac
            else
                qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-drive" "if=none,media=cdrom,id=drive1,file=$iso,readonly=on")
                qemu_args+=("-device" "ide-cd,bus=ide.0,unit=1,drive=drive1,bootindex=0")
            fi
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "if=none,media=disk,id=drive0,file=$disk,format=qcow2")
                qemu_args+=("-device" "ide-hd,bus=ide.0,unit=0,drive=drive0,bootindex=1")
            fi
            qemu_args+=("-prom-env" "boot-args=-v")
            qemu_args+=("-prom-env" "vga-ndrv?=true")
            qemu_args+=("-prom-env" "auto-boot?=true")
            local ndrv_loader=""
            for path in \
                "/usr/local/share/qemu/ppc-ndrvloader" \
                "/usr/share/qemu/ppc-ndrvloader" \
                "/opt/local/share/qemu/ppc-ndrvloader" \
                "$HOME/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu/ppc-ndrvloader" \
                "/Applications/UTM.app/Contents/Resources/qemu/share/qemu/ppc-ndrvloader"; do
                if [ -f "$path" ]; then
                    ndrv_loader="$path"
                    break
                fi
            done
            if [ -n "$ndrv_loader" ]; then
                qemu_args+=("-device" "loader,addr=0x4000000,file=$ndrv_loader")
            fi
            ;;
        "apollocore"|"68040")
            # Motorola 68k
            qemu_args+=("-machine" "${machine:-m68k}")
            qemu_args+=("-cpu" "${cpu_type:-68080}")
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "file=$disk,format=qcow2,if=scsi,bus=0,unit=0")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-cdrom" "$iso")
            fi
            qemu_args+=("-vga" "none")
            qemu_args+=("-serial" "stdio")
            ;;
        "x86_64"|"i386"|"i86")
            qemu_args+=("-machine" "q35,accel=hvf")
            qemu_args+=("-cpu" "host")
            if [ "$arch" = "i386" ]; then
                qemu_args+=("-machine" "pc")
            fi
            if [ "$num_screens" -gt 1 ]; then
                qemu_args+=("-vga" "virtio")
                for (( s=1; s<num_screens; s++ )); do
                    qemu_args+=("-device" "virtio-gpu-pci")
                done
            else
                qemu_args+=("-vga" "virtio")
            fi
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "file=$disk,format=qcow2,if=virtio")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-cdrom" "$iso")
            fi
            ;;
        "arm"|"arm64")
            if [ "$arch" = "arm" ]; then
                qemu_args+=("-machine" "virt")
                qemu_args+=("-cpu" "cortex-a15")
            else
                qemu_args+=("-machine" "virt")
                qemu_args+=("-cpu" "cortex-a57")
            fi
            qemu_args+=("-accel" "tcg")
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "file=$disk,format=qcow2,if=virtio")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-cdrom" "$iso")
            fi
            qemu_args+=("-vga" "none")
            qemu_args+=("-device" "virtio-gpu-pci")
            ;;
        "sparc"|"sparc64")
            if [ "$arch" = "sparc" ]; then
                qemu_args+=("-machine" "SS-10")
                qemu_args+=("-cpu" "FUJITSU+MB86904")
            else
                qemu_args+=("-machine" "sun4u")
                qemu_args+=("-cpu" "TI+UltraSparc+IIi")
            fi
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "file=$disk,format=qcow2,if=scsi,bus=0,unit=0")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-cdrom" "$iso")
            fi
            qemu_args+=("-vga" "tcx")
            qemu_args+=("-nographic")
            ;;
        *)
            log_error "Architecture non supportee: $arch"
            return 1
            ;;
    esac
    log_info "Starting VM with command:"
    echo "  ${qemu_args[*]}"
    mkdir -p "$vm_dir"
    echo "#!/bin/bash" > "$vm_dir/start.sh"
    echo "# Generated by vm-assistant" >> "$vm_dir/start.sh"
    echo "exec " >> "$vm_dir/start.sh"
    printf "%s " "${qemu_args[@]}" >> "$vm_dir/start.sh"
    echo "" >> "$vm_dir/start.sh"
    chmod +x "$vm_dir/start.sh"
    log_info "Command saved to: $vm_dir/start.sh"
    "${qemu_args[@]}" &
    local qemu_pid=$!
    echo "$qemu_pid" > "$vm_dir/pid"
    log_info "VM $vm_name started with PID: $qemu_pid"
    log_info "To stop VM: kill $qemu_pid"
}

create_utm_vm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"
    detect_utm
    if [ "$UTM_INSTALLED" != true ]; then
        log_error "UTM.app nest pas installe dans /Applications/UTM.app"
        log_info "Installez UTM depuis: https://mac.getutm.app/"
        return 1
    fi
    log_header "Creation dune VM UTM: $vm_name"
    local default_ram=4096
    local default_cpu=2
    local default_disk_size="20G"
    local UTM_OS_OPTIONS=(
        "macOS9:Mac OS 9"
        "macOS10.4:Mac OS X 10.4"
        "macOS10.5:Mac OS X 10.5"
        "linux:Linux"
        "windows:Windows"
        "dos:DOS"
    )
    read -p "RAM en MB [$default_ram]: " vm_ram
    read -p "Nombre de CPU [$default_cpu]: " vm_cpu
    read -p "Taille du disque [$default_disk_size]: " vm_disk_size
    vm_ram=${vm_ram:-$default_ram}
    vm_cpu=${vm_cpu:-$default_cpu}
    vm_disk_size=${vm_disk_size:-$default_disk_size}
    echo ""
    echo "Type de systeme dexploitation pour UTM:"
    local os_index=1
    for os_entry in "${UTM_OS_OPTIONS[@]}"; do
        local os_key=$(echo "$os_entry" | cut -d: -f1)
        local os_desc=$(echo "$os_entry" | cut -d: -f2-)
        echo "  [$os_index] $os_desc"
        ((os_index++))
    done
    read -p "Type [1]: " utm_os_type_choice
    utm_os_type_choice=${utm_os_type_choice:-1}
    local utm_os_type=""
    if [ "$utm_os_type_choice" -ge 1 ] && [ "$utm_os_type_choice" -le ${#UTM_OS_OPTIONS[@]} ]; then
        utm_os_type=$(echo "${UTM_OS_OPTIONS[$((utm_os_type_choice-1))]}" | cut -d: -f1)
    else
        utm_os_type="macOS9"
    fi
    echo ""
    echo "Architecture UTM:"
    echo "  [1] PowerPC (G3/G4)"
    echo "  [2] x86_64"
    echo "  [3] ARM64"
    read -p "Architecture [1]: " utm_arch_choice
    utm_arch_choice=${utm_arch_choice:-1}
    local utm_architecture=""
    case $utm_arch_choice in
        1) utm_architecture="ppc" ;;
        2) utm_architecture="x86_64" ;;
        3) utm_architecture="arm64" ;;
        *) utm_architecture="ppc" ;;
    esac
    echo ""
    echo "Mode daffichage UTM:"
    echo "  [1] Graphique (GUI)"
    echo "  [2] Terminal"
    read -p "Mode [1]: " utm_display_choice
    utm_display_choice=${utm_display_choice:-1}
    local utm_display=""
    case $utm_display_choice in
        1) utm_display="gui" ;;
        2) utm_display="terminal" ;;
        *) utm_display="gui" ;;
    esac
    echo ""
    echo "Options avancees pour UTM:"
    read -p "  Activer le partage de fichiers [y/N]: " utm_sharing
    utm_sharing=${utm_sharing:-n}
    local utm_sharing_path=""
    if [ "$utm_sharing" = "y" ]; then
        read -p "  Chemin du repertoire [$SHARE_DIR]: " utm_sharing_path_input
        utm_sharing_path="${utm_sharing_path_input:-$SHARE_DIR}"
    fi
    read -p "  Activer le partage clipboard [y/N]: " utm_clipboard
    utm_clipboard=${utm_clipboard:-n}
    read -p "  Activer VNC [y/N]: " utm_vnc
    utm_vnc=${utm_vnc:-n}
    local utm_vnc_port=5900
    if [ "$utm_vnc" = "y" ]; then
        read -p "  Port VNC [$utm_vnc_port]: " utm_vnc_port_input
        utm_vnc_port="${utm_vnc_port_input:-$utm_vnc_port}"
    fi
    echo ""
    echo "Mode reseau UTM:"
    echo "  [1] Partage (NAT)"
    echo "  [2] Pont (bridged)"
    echo "  [3] Hote seulement"
    echo "  [4] Deconnecte"
    read -p "  Mode reseau [1]: " utm_network_choice
    utm_network_choice=${utm_network_choice:-1}
    local utm_network_mode=""
    case $utm_network_choice in
        1) utm_network_mode="shared" ;;
        2) utm_network_mode="bridged" ;;
        3) utm_network_mode="host" ;;
        4) utm_network_mode="disconnected" ;;
        *) utm_network_mode="shared" ;;
    esac
    echo ""
    echo "Mode demulation UTM:"
    echo "  [1] SoftMMU"
    echo "  [2] System"
    local system_mode_available=false
    case $utm_architecture in
        "arm64") system_mode_available=true ;;
        "x86_64") system_mode_available=true ;;
        "ppc") echo "  Note: PowerPC ne supporte que SoftMMU"; system_mode_available=false ;;
    esac
    local utm_emulator="softmmu"
    if [ "$system_mode_available" = true ]; then
        read -p "  Mode [1]: " utm_emulator_choice
        utm_emulator_choice=${utm_emulator_choice:-1}
        case $utm_emulator_choice in
            1) utm_emulator="softmmu" ;;
            2) utm_emulator="system" ;;
        esac
    fi
    echo ""
    read -p "  Option de boot [1=CD, 2=Disque, 3=CD+Disque]: " utm_boot_choice
    utm_boot_choice=${utm_boot_choice:-1}
    local boot_order=""
    local iso_path=""
    case $utm_boot_choice in
        1) boot_order="d" ;;
        2) boot_order="c" ;;
        3) boot_order="dc" ;;
        *) boot_order="dc" ;;
    esac
    if [ "$boot_order" = "d" ] || [ "$boot_order" = "dc" ]; then
        list_isos
        if [ -n "$selected_iso" ]; then
            iso_path="$selected_iso"
        fi
    fi
    mkdir -p "$vm_dir"
    local utm_disk_path="$DISK_DIR/${vm_name}.qcow2"
    mkdir -p "$DISK_DIR"
    qemu-img create -f qcow2 "$utm_disk_path" "$vm_disk_size" || {
        log_error "Echec de la creation du disque"
        return 1
    }
    cat > "$vm_config" << EOF
# Configuration de la VM UTM: $vm_name
utm_os_type=$utm_os_type
utm_architecture=$utm_architecture
utm_emulator=$utm_emulator
ram=$vm_ram
cpu=$vm_cpu
disk=$utm_disk_path
iso=$iso_path
utm_network_mode=$utm_network_mode
utm_display=$utm_display
utm_sharing=$utm_sharing
utm_sharing_path=$utm_sharing_path
utm_clipboard=$utm_clipboard
utm_vnc=$utm_vnc
utm_vnc_port=$utm_vnc_port
boot_order=$boot_order
EOF
    log_info "Configuration UTM sauvegardee pour $vm_name"
    cat > "$vm_dir/utm-config.json" << EOF
{
  "name": "$vm_name",
  "target": "$utm_architecture",
  "emulator": "$utm_emulator",
  "memory": $vm_ram,
  "cpuCount": $vm_cpu,
  "disk": "$utm_disk_path",
  "iso": "$iso_path",
  "network": {"mode": "$utm_network_mode"},
  "display": {"mode": "$utm_display"},
  "sharing": {"enabled": "$utm_sharing", "path": "$utm_sharing_path", "clipboard": "$utm_clipboard"},
  "vnc": {"enabled": "$utm_vnc", "port": $utm_vnc_port},
  "bootOrder": "$boot_order"
}
EOF
    log_info "Configuration JSON generatee: $vm_dir/utm-config.json"
    return 0
}

create_vm() {
    local vm_name=$1
    if [ -z "$vm_name" ]; then
        log_error "Usage: $0 create VMNAME"
        return 1
    fi
    echo "Type de VM:"
    echo "  [1] QEMU (commande ligne)"
    echo "  [2] UTM (application graphique)"
    read -p "Type [1]: " vm_type_choice
    vm_type_choice=${vm_type_choice:-1}
    local vm_dir="$VM_DIR/$vm_name"
    mkdir -p "$vm_dir"
    case "$vm_type_choice" in
        1)
            log_header "Creation dune VM QEMU: $vm_name"
            echo "Architecture:"
            echo "  [1] G4 (PowerPC)"
            echo "  [2] 604ev (PowerPC)"
            echo "  [3] 604 (PowerPC)"
            echo "  [4] 601 (PowerPC)"
            echo "  [5] 68040 (Motorola)"
            echo "  [6] apollocore (68080)"
            echo "  [7] x86_64 (Intel/AMD)"
            echo "  [8] i386 (x86 32-bit)"
            echo "  [9] ARM"
            echo "  [A] ARM64"
            echo "  [B] SPARC"
            echo "  [C] SPARC64"
            read -p "Architecture [1]: " arch_choice
            arch_choice=${arch_choice:-1}
            local arch=""; local machine=""; local cpu_type=""
            case $arch_choice in
                1) arch="G4"; machine="mac99"; cpu_type="7455" ;;
                2) arch="604ev"; machine="g3beige"; cpu_type="604ev" ;;
                3) arch="604"; machine="g3beige"; cpu_type="604" ;;
                4) arch="601"; machine="g3beige"; cpu_type="601" ;;
                5) arch="68040"; machine="mac99"; cpu_type="68040" ;;
                6) arch="apollocore"; machine="m68k"; cpu_type="68080" ;;
                7) arch="x86_64"; machine="q35"; cpu_type="host" ;;
                8) arch="i386"; machine="q35"; cpu_type="host" ;;
                9) arch="arm"; machine="virt"; cpu_type="cortex-a15" ;;
                A|a) arch="arm64"; machine="virt"; cpu_type="cortex-a57" ;;
                B|b) arch="sparc"; machine="SS-10"; cpu_type="FUJITSU+MB86904" ;;
                C|c) arch="sparc64"; machine="sun4u"; cpu_type="TI+UltraSparc+IIi" ;;
                *) arch="G4"; machine="mac99"; cpu_type="7455" ;;
            esac
            read -p "RAM en MB [768]: " ram; ram=${ram:-768}
            read -p "Nombre de CPU [1]: " cpu; cpu=${cpu:-1}
            read -p "Nombre decrans [1]: " num_screens; num_screens=${num_screens:-1}
            echo "Methode multi-ecran:"
            echo "  [1] Auto"
            echo "  [2] Dual-PCI VGA"
            echo "  [3] Graphic Engine"
            read -p "Methode [1]: " method_choice; method_choice=${method_choice:-1}
            local multi_screen_method=""
            case $method_choice in
                1) multi_screen_method="auto" ;;
                2) multi_screen_method="dual-pci-vga" ;;
                3) multi_screen_method="graphic-engine" ;;
                *) multi_screen_method="auto" ;;
            esac
            read -p "VIA type (pmu/cuda/none) [cuda]: " via; via=${via:-cuda}
            echo "Disque de demarrage:"
            echo "  [1] Creer un nouveau disque"
            echo "  [2] Utiliser un disque existant"
            echo "  [3] Aucun disque"
            read -p "Option [1]: " disk_choice; disk_choice=${disk_choice:-1}
            local disk=""
            case $disk_choice in
                1) create_disk "$vm_name" && disk="$selected_disk" || disk="" ;;
                2) list_disks && disk="$selected_disk" || disk="" ;;
            esac
            echo "ISO dinstallation:"
            echo "  [1] Selectionner un ISO existant"
            echo "  [2] Aucun ISO"
            read -p "Option [2]: " iso_choice; iso_choice=${iso_choice:-2}
            local iso=""
            if [ "$iso_choice" = "1" ]; then
                list_isos && iso="$selected_iso" || iso=""
            fi
            echo "Mode reseau:"
            echo "  [1] NAT"
            echo "  [2] User"
            echo "  [3] Aucun"
            read -p "Mode [1]: " net_choice; net_choice=${net_choice:-1}
            local network_mode=""
            case $net_choice in
                1) network_mode="nat" ;;
                2) network_mode="user" ;;
                3) network_mode="none" ;;
            esac
            read -p "Repertoire de partage [$SHARE_DIR]: " share_dir; share_dir=${share_dir:-$SHARE_DIR}
            echo "Fichier ROM (optionnel pour Mac OS ancien):"
            echo "  [1] Selectionner un ROM"
            echo "  [2] Aucun"
            read -p "Option [2]: " rom_choice; rom_choice=${rom_choice:-2}
            local rom_file=""
            if [ "$rom_choice" = "1" ]; then
                list_roms && rom_file="$selected_rom" || rom_file=""
            fi
            echo "Mode daffichage:"
            echo "  [1] Cocoa (GUI)"
            echo "  [2] None (console)"
            read -p "Mode [1]: " display_choice; display_choice=${display_choice:-1}
            local display=""
            case $display_choice in
                1) display="cocoa" ;;
                2) display="none" ;;
            esac
            cat > "$vm_dir/config" << CONFIG
# Configuration de la VM: $vm_name
# Date: $(date)
arch=$arch
machine=$machine
cpu_type=$cpu_type
ram=$ram
cpu=$cpu
disk=$disk
iso=$iso
network_mode=$network_mode
display=$display
num_screens=$num_screens
multi_screen_method=$multi_screen_method
via=$via
share_dir=$share_dir
rom_file=${rom_file:-}
CONFIG
            log_info "VM QEMU creee: $vm_name"
            ;;
        2)
            create_utm_vm "$vm_name"
            ;;
    esac
}

list_vms() {
    log_header "Liste des VMs"
    if [ ! -d "$VM_DIR" ]; then
        echo "  Aucune VM trouvee"
        return 1
    fi
    local vms=(); local index=1
    for vm_dir in "$VM_DIR"/*/; do
        if [ -d "$vm_dir" ]; then
            local vm_name=$(basename "$vm_dir")
            vms+=("$vm_name")
            local vm_config="$vm_dir/config"
            if [ -f "$vm_config" ]; then
                source "$vm_config" 2>/dev/null || true
                local vm_type="QEMU"
                if [ -n "$utm_architecture" ]; then
                    vm_type="UTM"
                fi
                echo "  [$index] $vm_name (type: $vm_type, arch: ${arch:-${utm_architecture:-unknown}}, ram: ${ram:-unknown}MB)"
            else
                echo "  [$index] $vm_name"
            fi
            ((index++))
        fi
    done
    if [ ${#vms[@]} -eq 0 ]; then
        echo "  Aucune VM trouvee"
        return 1
    fi
    return 0
}

stop_vm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    if [ ! -d "$vm_dir" ]; then
        log_error "VM not found: $vm_name"
        return 1
    fi
    local pid_file="$vm_dir/pid"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid" && {
                log_info "VM $vm_name arreee (PID: $pid)"
                rm -f "$pid_file"
                return 0
            }
        else
            log_warn "Processus $pid deja termine"
            rm -f "$pid_file"
            return 0
        fi
    else
        log_error "Aucun PID trouve pour $vm_name"
        return 1
    fi
}

delete_vm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    if [ ! -d "$vm_dir" ]; then
        log_error "VM not found: $vm_name"
        return 1
    fi
    read -p "Etes-vous sur de vouloir supprimer la VM $vm_name et tous ses fichiers? [y/N]: " confirm
    if [ "$confirm" != "y" ]; then
        log_info "Suppression annulee"
        return 0
    fi
    stop_vm "$vm_name" 2>/dev/null || true
    rm -rf "$vm_dir" && {
        log_info "VM $vm_name supprimee"
        return 0
    }
    log_error "Echec de la suppression de $vm_name"
    return 1
}

# Valider la configuration d'une VM
validate_vm_config() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"
    
    if [ ! -d "$vm_dir" ]; then
        log_error "VM not found: $vm_name"
        return 1
    fi
    
    if [ ! -f "$vm_config" ]; then
        log_error "Config not found: $vm_config"
        return 1
    fi
    
    source "$vm_config" 2>/dev/null || {
        log_error "Failed to load config: $vm_config"
        return 1
    }
    
    local errors=()
    
    # Vérifier les champs requis
    if [ -z "$arch" ]; then
        errors+=("architecture non definie")
    fi
    
    if [ -z "$machine" ]; then
        errors+=("machine non definie")
    fi
    
    if [ -z "$ram" ]; then
        errors+=("RAM non definie")
    fi
    
    if [ -n "$disk" ] && [ ! -f "$disk" ]; then
        errors+=("Disque non trouve: $disk")
    fi
    
    if [ -n "$iso" ] && [ ! -f "$iso" ]; then
        errors+=("ISO non trouve: $iso")
    fi
    
    if [ -n "$rom_file" ] && [ ! -f "$rom_file" ]; then
        errors+=("ROM non trouve: $rom_file")
    fi
    
    if [ -n "$share_dir" ] && [ ! -d "$share_dir" ]; then
        errors+=("Repertoire de partage non trouve: $share_dir")
    fi
    
    # Vérifier les valeurs numériques
    if [ -n "$ram" ] && ! [[ "$ram" =~ ^[0-9]+$ ]]; then
        errors+=("RAM doit etre un nombre: $ram")
    fi
    
    if [ -n "$cpu" ] && ! [[ "$cpu" =~ ^[0-9]+$ ]]; then
        errors+=("CPU doit etre un nombre: $cpu")
    fi
    
    if [ -n "$num_screens" ] && ! [[ "$num_screens" =~ ^[0-9]+$ ]]; then
        errors+=("num_screens doit etre un nombre: $num_screens")
    fi
    
    if [ ${#errors[@]} -gt 0 ]; then
        log_error "Problemes de configuration:"
        for err in "${errors[@]}"; do
            log_error "  - $err"
        done
        return 1
    fi
    
    log_info "Configuration valide pour $vm_name"
    return 0
}

# Insert un ISO dans une VM en cours d'exécution
insert_iso() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local iso_to_insert=$2
    
    if [ ! -d "$vm_dir" ]; then
        log_error "VM not found: $vm_name"
        return 1
    fi
    
    if [ -z "$iso_to_insert" ]; then
        list_isos || return 1
        iso_to_insert="$selected_iso"
    fi
    
    if [ ! -f "$iso_to_insert" ]; then
        log_error "ISO non trouve: $iso_to_insert"
        return 1
    fi
    
    local pid_file="$vm_dir/pid"
    if [ ! -f "$pid_file" ]; then
        log_error "La VM $vm_name n'est pas en cours d'execution"
        return 1
    fi
    
    local pid=$(cat "$pid_file")
    if ! ps -p "$pid" > /dev/null 2>&1; then
        log_error "Le processus QEMU de $vm_name n'est plus actif"
        return 1
    fi
    
    log_info "Insertion de l'ISO: $(basename "$iso_to_insert") dans la VM $vm_name"
    
    # Utiliser qemu monitor pour changer le CDROM
    # Cette méthode nécessite que QEMU ait été démarré avec -monitor
    # On va plutôt modifier la configuration et redémarrer
    
    # Mettre à jour la configuration
    if [ -f "$vm_dir/config" ]; then
        sed -i.bak "s|^iso=.*|iso=$iso_to_insert|" "$vm_dir/config" 2>/dev/null || {
            echo "iso=$iso_to_insert" >> "$vm_dir/config"
        }
    fi
    
    log_info "ISO ajoute a la configuration. Redemarrez la VM pour prendre en compte."
    return 0
}

# Éjecter l'ISO d'une VM
eject_iso() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    
    if [ ! -d "$vm_dir" ]; then
        log_error "VM not found: $vm_name"
        return 1
    fi
    
    local pid_file="$vm_dir/pid"
    if [ ! -f "$pid_file" ]; then
        log_error "La VM $vm_name n'est pas en cours d'execution"
        return 1
    fi
    
    local pid=$(cat "$pid_file")
    if ! ps -p "$pid" > /dev/null 2>&1; then
        log_error "Le processus QEMU de $vm_name n'est plus actif"
        return 1
    fi
    
    log_info "Ejection de l'ISO de la VM $vm_name"
    
    # Mettre à jour la configuration
    if [ -f "$vm_dir/config" ]; then
        sed -i.bak 's|^iso=.*|iso=|' "$vm_dir/config" 2>/dev/null || {
            grep -v "^iso=" "$vm_dir/config" > "$vm_dir/config.tmp" 2>/dev/null && \
            mv "$vm_dir/config.tmp" "$vm_dir/config"
        }
    fi
    
    log_info "ISO retire de la configuration. Redemarrez la VM pour prendre en compte."
    return 0
}

# Démarrer une VM UTM
start_utm_vm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"
    
    if [ ! -d "$vm_dir" ]; then
        log_error "VM not found: $vm_name"
        return 1
    fi
    
    if [ ! -f "$vm_config" ]; then
        log_error "Config not found: $vm_config"
        return 1
    fi
    
    detect_utm
    if [ "$UTM_INSTALLED" != true ]; then
        log_error "UTM.app nest pas installe dans /Applications/UTM.app"
        return 1
    fi
    
    source "$vm_config" || return 1
    
    # Vérifier si c'est une config UTM
    if [ -z "$utm_architecture" ]; then
        log_error "Ce n'est pas une configuration UTM: $vm_name"
        return 1
    fi
    
    log_info "Demarrage de la VM UTM: $vm_name"
    
    # Créer le fichier .utm.json pour UTM
    local utm_json_file="$vm_dir/${vm_name}.utm.json"
    
    # Convertir la configuration en JSON pour UTM
    cat > "$utm_json_file" << EOF
{
  "name": "$vm_name",
  "target": "$utm_architecture",
  "emulator": "${utm_emulator:-softmmu}",
  "memory": ${ram:-4096},
  "cpuCount": ${cpu:-2},
  "disk": "$disk",
  "iso": "${iso:-}",
  "network": {"mode": "${utm_network_mode:-shared}"},
  "display": {"mode": "${utm_display:-gui}"},
  "sharing": {"enabled": "${utm_sharing:-no}", "path": "${utm_sharing_path:-$SHARE_DIR}", "clipboard": "${utm_clipboard:-no}"},
  "vnc": {"enabled": "${utm_vnc:-no}", "port": ${utm_vnc_port:-5900}},
  "bootOrder": "${boot_order:-dc}"
}
EOF
    
    log_info "Fichier UTM genere: $utm_json_file"
    log_info "Ouvrez UTM.app et importez ce fichier pour demarrer la VM"
    
    # Optionnel: Ouvrir automatiquement avec UTM
    if command -v open &>/dev/null; then
        read -p "Voulez-vous ouvrir UTM.app maintenant? [y/N]: " open_utm
        if [ "$open_utm" = "y" ]; then
            open "$UTM_PATH"
            log_info "UTM.app ouvert. Importez le fichier: $utm_json_file"
        fi
    fi
    
    return 0
}

# Exporter une VM vers UTM
export_utm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"
    
    if [ ! -d "$vm_dir" ]; then
        log_error "VM not found: $vm_name"
        return 1
    fi
    
    if [ ! -f "$vm_config" ]; then
        log_error "Config not found: $vm_config"
        return 1
    fi
    
    detect_utm
    if [ "$UTM_INSTALLED" != true ]; then
        log_warn "UTM.app nest pas installe, mais l'export continue"
    fi
    
    source "$vm_config" || return 1
    
    log_header "Export VM vers UTM: $vm_name"
    
    local utm_json_file="$vm_dir/${vm_name}.utm.json"
    
    # Déterminer l'architecture UTM
    local utm_arch=""
    case "$arch" in
        "G4"|"604ev"|"604"|"601"|"68040"|"ppc")
            utm_arch="ppc"
            ;;
        "x86_64"|"i386"|"i86")
            utm_arch="x86_64"
            ;;
        "arm"|"arm64")
            utm_arch="arm64"
            ;;
        "sparc"|"sparc64")
            utm_arch="sparc64"
            ;;
        *) utm_arch="x86_64" ;;
    esac
    
    # Déterminer le mode d'émulation
    local utm_emulator="softmmu"
    case "$utm_arch" in
        "arm64"|"x86_64")
            utm_emulator="softmmu"
            # UTM supporte aussi 'system' pour x86_64
            read -p "Utiliser System mode pour $utm_arch? [y/N]: " use_system
            if [ "$use_system" = "y" ]; then
                utm_emulator="system"
            fi
            ;;
        *) utm_emulator="softmmu" ;;
    esac
    
    # Déterminer le mode réseau
    local utm_network="shared"
    case "$network_mode" in
        "nat") utm_network="shared" ;;
        "user") utm_network="shared" ;;
        "bridged") utm_network="bridged" ;;
        "host") utm_network="host" ;;
        "none") utm_network="disconnected" ;;
    esac
    
    # Déterminer l'ordre de boot
    local boot_order_utm="dc"
    if [ -n "$boot_order" ]; then
        boot_order_utm="$boot_order"
    elif [ -n "$iso" ]; then
        boot_order_utm="dc"
    else
        boot_order_utm="c"
    fi
    
    # Créer le JSON UTM
    cat > "$utm_json_file" << EOF
{
  "name": "$vm_name",
  "target": "$utm_arch",
  "emulator": "$utm_emulator",
  "memory": ${ram:-4096},
  "cpuCount": ${cpu:-2},
  "disk": "$disk",
  "iso": "${iso:-}",
  "network": {"mode": "$utm_network"},
  "display": {"mode": "${display:-gui}"},
  "sharing": {"enabled": "yes", "path": "${share_dir:-$SHARE_DIR}", "clipboard": "yes"},
  "vnc": {"enabled": "no", "port": 5900},
  "bootOrder": "$boot_order_utm"
}
EOF
    
    log_info "VM exportée vers: $utm_json_file"
    log_info "Ouvrez UTM.app et importez ce fichier pour demarrer la VM"
    
    # Optionnel: Ouvrir automatiquement avec UTM
    if [ "$UTM_INSTALLED" = true ]; then
        read -p "Voulez-vous ouvrir UTM.app maintenant? [y/N]: " open_utm
        if [ "$open_utm" = "y" ]; then
            open "$UTM_PATH"
        fi
    fi
    
    return 0
}

init_directories() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$VM_DIR"
    mkdir -p "$DISK_DIR"
    mkdir -p "$ISO_DIR"
    mkdir -p "$SHARE_DIR"
}

case "$1" in
    start)
        if [ -n "$2" ]; then start_qemu_vm "$2"; else log_error "Usage: $0 start VMNAME"; fi
        ;;
    start-utm)
        if [ -n "$2" ]; then start_utm_vm "$2"; else log_error "Usage: $0 start-utm VMNAME"; fi
        ;;
    edit)
        if [ -n "$2" ]; then edit_vm "$2"; else log_error "Usage: $0 edit VMNAME"; fi
        ;;
    create)
        if [ -n "$2" ]; then create_vm "$2"; else log_error "Usage: $0 create VMNAME"; fi
        ;;
    list) list_vms ;;
    stop)
        if [ -n "$2" ]; then stop_vm "$2"; else log_error "Usage: $0 stop VMNAME"; fi
        ;;
    delete)
        if [ -n "$2" ]; then delete_vm "$2"; else log_error "Usage: $0 delete VMNAME"; fi
        ;;
    validate)
        if [ -n "$2" ]; then validate_vm_config "$2"; else log_error "Usage: $0 validate VMNAME"; fi
        ;;
    insert-iso)
        if [ -n "$2" ]; then insert_iso "$2" "$3"; else log_error "Usage: $0 insert-iso VMNAME [ISO]"; fi
        ;;
    eject-iso)
        if [ -n "$2" ]; then eject_iso "$2"; else log_error "Usage: $0 eject-iso VMNAME"; fi
        ;;
    export-utm)
        if [ -n "$2" ]; then export_utm "$2"; else log_error "Usage: $0 export-utm VMNAME"; fi
        ;;
    menu|"")
        init_directories
        detect_utm
        while true; do
            clear || echo ""
            log_header "VM Assistant - Menu Principal"
            echo ""
            echo "  [1] Creer une nouvelle VM"
            echo "  [2] Demarrer une VM (QEMU)"
            echo "  [3] Demarrer une VM (UTM)"
            echo "  [4] Editer une VM"
            echo "  [5] Lister les VMs"
            echo "  [6] Arreter une VM"
            echo "  [7] Supprimer une VM"
            echo "  [8] Valider la configuration d'une VM"
            echo "  [9] Insérer un ISO dans une VM"
            echo "  [A] Éjecter un ISO d'une VM"
            echo "  [B] Exporter une VM vers UTM"
            echo "  [C] Verifier linstallation"
            echo "  [Q] Quitter"
            echo ""
            if [ "$UTM_INSTALLED" = true ]; then echo "  UTM.app: ✓ Installe"; else echo "  UTM.app: ✗ Non installe"; fi
            command -v qemu-system-ppc &>/dev/null && echo "  QEMU PPC: ✓ Disponible" || echo "  QEMU PPC: ✗ Non disponible"
            command -v qemu-img &>/dev/null && echo "  qemu-img: ✓ Disponible" || echo "  qemu-img: ✗ Non disponible"
            command -v port &>/dev/null && echo "  MacPorts: ✓ Installe" || echo "  MacPorts: ✗ Non installe"
            command -v brew &>/dev/null && echo "  Homebrew: ✓ Installe" || echo "  Homebrew: ✗ Non installe"
            echo ""
            read -p "Selectionnez une option [Q]: " choice; choice=${choice:-Q}
            case "$choice" in
                1) read -p "Nom de la VM: " vm_name; if [ -n "$vm_name" ]; then create_vm "$vm_name"; else log_error "Nom vide"; fi ;;
                2) list_vms && read -p "Selectionner une VM: " vm_index && { vm_name=$(ls "$VM_DIR" | sed -n "${vm_index}p"); if [ -n "$vm_name" ]; then start_qemu_vm "$vm_name"; else log_error "VM non valide"; fi; } ;;
                3) list_vms && read -p "Selectionner une VM: " vm_index && { vm_name=$(ls "$VM_DIR" | sed -n "${vm_index}p"); if [ -n "$vm_name" ]; then start_utm_vm "$vm_name"; else log_error "VM non valide"; fi; } ;;
                4) list_vms && read -p "Selectionner une VM: " vm_index && { vm_name=$(ls "$VM_DIR" | sed -n "${vm_index}p"); if [ -n "$vm_name" ]; then edit_vm "$vm_name"; else log_error "VM non valide"; fi; } ;;
                5) list_vms ;;
                6) list_vms && read -p "Selectionner une VM: " vm_index && { vm_name=$(ls "$VM_DIR" | sed -n "${vm_index}p"); if [ -n "$vm_name" ]; then stop_vm "$vm_name"; else log_error "VM non valide"; fi; } ;;
                7) list_vms && read -p "Selectionner une VM: " vm_index && { vm_name=$(ls "$VM_DIR" | sed -n "${vm_index}p"); if [ -n "$vm_name" ]; then delete_vm "$vm_name"; else log_error "VM non valide"; fi; } ;;
                8) list_vms && read -p "Selectionner une VM: " vm_index && { vm_name=$(ls "$VM_DIR" | sed -n "${vm_index}p"); if [ -n "$vm_name" ]; then validate_vm_config "$vm_name"; else log_error "VM non valide"; fi; } ;;
                9) list_vms && read -p "Selectionner une VM: " vm_index && { vm_name=$(ls "$VM_DIR" | sed -n "${vm_index}p"); if [ -n "$vm_name" ]; then insert_iso "$vm_name"; else log_error "VM non valide"; fi; } ;;
                A|a) list_vms && read -p "Selectionner une VM: " vm_index && { vm_name=$(ls "$VM_DIR" | sed -n "${vm_index}p"); if [ -n "$vm_name" ]; then eject_iso "$vm_name"; else log_error "VM non valide"; fi; } ;;
                B|b) list_vms && read -p "Selectionner une VM: " vm_index && { vm_name=$(ls "$VM_DIR" | sed -n "${vm_index}p"); if [ -n "$vm_name" ]; then export_utm "$vm_name"; else log_error "VM non valide"; fi; } ;;
                C|c)
                    log_header "Verification de linstallation"
                    for arch in ppc x86_64 m68k arm sparc; do
                        command -v "qemu-system-$arch" &>/dev/null && log_info "qemu-system-$arch: ✓ trouve" || log_warn "qemu-system-$arch: ✗ non trouve"
                    done
                    command -v qemu-img &>/dev/null && log_info "qemu-img: ✓ trouve" || log_warn "qemu-img: ✗ non trouve"
                    [ "$UTM_INSTALLED" = true ] && log_info "UTM.app: ✓ installe" || log_warn "UTM.app: ✗ non installe"
                    [ -d "/Applications/Utilities/XQuartz.app" ] && log_info "XQuartz: ✓ installe" || log_warn "XQuartz: ✗ non installe"
                    read -p "Appuyez sur Entree pour continuer..." 
                    ;;
                Q|q) log_info "Au revoir!"; exit 0 ;;
                *) echo "Option non valide" ;;
            esac
            read -p "Appuyez sur Entree pour continuer..." 
        done
        ;;
    *)
        echo "Usage: $0 {start|start-utm|edit|create|list|stop|delete|validate|insert-iso|eject-iso|export-utm|menu} [VMNAME]"
        echo "Exemples:"
        echo "  $0 start macos9_g4"
        echo "  $0 start-utm ma_vm_utm"
        echo "  $0 edit macos9_g4"
        echo "  $0 create new_vm"
        echo "  $0 validate macos9_g4"
        echo "  $0 insert-iso macos9_g4 /path/to/iso.iso"
        echo "  $0 eject-iso macos9_g4"
        echo "  $0 export-utm macos9_g4"
        echo "  $0 menu"
        ;;
esac
