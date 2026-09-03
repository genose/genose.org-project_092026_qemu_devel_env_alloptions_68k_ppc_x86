#!/bin/bash
# =============================================================================
# VM Assistant - Module Gestion des VMs
# Cr'eation, modification, d'emarrage, arr^et des machines virtuelles
# Support: QEMU (toutes architectures) + UTM.app
# Utilise dirname $0 pour etre portable
# Version: 2.0.0 - Support complet pour toutes architectures
# =============================================================================

# Configuration globale
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="vm-assistant"
CONFIG_DIR="$HOME/vm_assistant"
VM_DIR="$CONFIG_DIR/vms"
ISO_DIR="$CONFIG_DIR/isos"
DISK_DIR="$CONFIG_DIR/vms"
SHARE_DIR="$HOME/vm_assistant/shares"

# Ports
SPICE_PORT=5900
GDB_PORT=1234
VNC_BASE_PORT=5900

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Variables globales
selected_vm=""
selected_iso=""
disk_list=()

# =============================================================================
# DETECTION DES ARCHITECTURES DISPONIBLES
# Utilisation de tableaux simples pour 'eviter les probl`emes de syntaxe
# =============================================================================

# Liste des architectures QEMU avec leurs propri'et'es
# Format: chaque ligne contient: qemu_bin arch_name description
QEMU_ARCHS=(
    "qemu-system-m68k 68k Motorola 68000 (68k) - Mac OS Classic, System 6-7"
    "qemu-system-m68k 68040 Motorola 68040 - Mac OS Classic optimis'e"
    "qemu-system-m68k apollocore Apollo Core (68080) - Mac OS 8.1-9 avec Apollo"
    "qemu-system-ppc G4 PowerPC G4 - Mac OS 8-9, Mac OS X 10.2-10.4"
    "qemu-system-ppc 601 PowerPC 601 - Mac OS 7.5-8.1"
    "qemu-system-ppc 604ev PowerPC 604ev - Mac OS 9 optimis'e"
    "qemu-system-ppc ppc PowerPC (g'en'erique) - Pour autres configurations PPC"
    "qemu-system-i386 i86 x86 (32-bit) - DOS, Windows 9x/2000, Linux 32-bit"
    "qemu-system-i386 i386 x86 (32-bit alternatif)"
    "qemu-system-x86_64 X86_64 x86_64 (64-bit) - Windows 64-bit, Linux 64-bit"
    "qemu-system-arm arm ARM (32-bit) - Linux ARM, Raspberry Pi OS"
    "qemu-system-aarch64 arm64 ARM64 (64-bit) - Linux ARM64"
    "qemu-system-sparc sparc SPARC - SunOS, Solaris"
    "qemu-system-sparc64 sparc64 SPARC64 - Solaris 64-bit"
)

# Param`etres par d'efaut pour chaque architecture
# Format: arch ram cpu machine cpu_type disk_size
DEFAULT_PARAMS=(
    "68k 128 1 q800 m68040 2G"
    "68040 256 1 q800 m68040 4G"
    "apollocore 512 1 q800 68080 4G"
    "G4 2048 1 mac99 750 10G"
    "601 512 1 g3beige 601 4G"
    "604ev 1024 1 mac99 604ev 8G"
    "ppc 1024 1 g3beige 750 8G"
    "i86 2048 2 pc pentium3 20G"
    "i386 1024 1 pc pentium 10G"
    "X86_64 4096 4 q35 host 50G"
    "arm 1024 2 versatilepb arm1176 8G"
    "arm64 2048 2 virt host 16G"
    "sparc 1024 1 sun4m Fujitsu+MB86904 8G"
    "sparc64 2048 2 sun4u Fujitsu+Sparc64IV+ 16G"
)

# Liste des CPU PowerPC avec descriptions (test'es avec Mac OS 9.2.2)
# Format: cpu_name description
PPC_CPU_OPTIONS=(
    "750 PowerPC G3 (750) - 900MHz, compatible Mac OS 9"
    "7400 PowerPC G4 (7400) - Premier G4 sans AltiVec, pour tests d'eveloppeurs"
    "7410 PowerPC G4 (7410) - 500MHz, avec AltiVec"
    "7450 PowerPC G4 (7450) - 733MHz, avec AltiVec"
    "7455 PowerPC G4 (7455) - 900MHz, avec AltiVec, meilleur choix"
    "601 PowerPC 601 - Pour Mac OS 7.5-8.1"
    "604ev PowerPC 604ev - Mac OS 9 optimis'e"
)

# Options pour le param`etre via (PowerPC)
VIA_OPTIONS=(
    "pmu Power Management Unit (par d'efaut)"
    "cuda CUDA chip (alternatif)"
    "none Aucun param`etre via"
)

# M'ethodes de multi-'ecran pour PowerPC/Mac OS 9
MULTI_SCREEN_METHODS=(
    "dual-pci-vga M'ethode Dual-PCI VGA (vga-ndrv) - Recommand'ee pour QEMU standard"
    "graphic-engine Device graphic-drawing-engine (qfb patches) - N'ecessite QEMU custom"
    "auto Auto-d'etection (essaie graphic-engine puis dual-pci-vga)"
)

# Fonction pour tester si un device QEMU existe
qemu_device_exists() {
    local device="$1"
    qemu-system-ppc -device help 2>/dev/null | grep -q "$device" && return 0 || return 1
}

# Types de syst`emes d'exploitation pour UTM
UTM_OS_OPTIONS=(
    "macOS9 Mac OS 9"
    "macOS10.4 Mac OS X 10.4"
    "macOS10.5 Mac OS X 10.5"
    "linux Linux"
    "windows Windows"
    "dos DOS"
)

# Fonction pour obtenir les param`etres par d'efaut d'une architecture
get_default_params() {
    local arch=$1
    for params in "${DEFAULT_PARAMS[@]}"; do
        local current_arch=$(echo "$params" | awk '{print $1}')
        if [ "$current_arch" = "$arch" ]; then
            echo "$params"
            return
        fi
    done
    # Valeurs par d'efaut si architecture non trouv'ee
    echo "$arch 1024 1 pc host 10G"
}

# Fonction pour obtenir la commande QEMU d'une architecture
get_qemu_bin() {
    local arch=$1
    for entry in "${QEMU_ARCHS[@]}"; do
        local qemu_bin=$(echo "$entry" | awk '{print $1}')
        local current_arch=$(echo "$entry" | awk '{print $2}')
        if [ "$current_arch" = "$arch" ]; then
            echo "$qemu_bin"
            return
        fi
    done
    echo "qemu-system-$arch"
}

# Fonction pour obtenir la description d'une architecture
get_arch_description() {
    local arch=$1
    for entry in "${QEMU_ARCHS[@]}"; do
        local current_arch=$(echo "$entry" | awk '{print $2}')
        if [ "$current_arch" = "$arch" ]; then
            echo "$entry" | awk '{$1=""; $2=""; print substr($0,3)}'
            return
        fi
    done
    echo "Architecture $arch"
}

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

# Cr'eer un r'epertoire avec sudo si n'ecessaire
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" 2>/dev/null || sudo mkdir -p "$dir" 2>/dev/null
        sudo chown "$(whoami):$(id -gn)" "$dir"
        sudo chmod 775 "$dir"
    fi
    if [ ! -d "$dir" ]; then
        log_error "Impossible de cr'eer: $dir"
        return 1
    fi
    return 0
}

# Detecter les ISOs disponibles (LOCAL ONLY - pas /Volumes)
detect_available_isos() {
    local search_dirs=(
        "$ISO_DIR"
        "$SHARE_DIR"
        "$HOME/Downloads"
        "$SCRIPT_DIR"
    )

    global_available_isos=()
    global_available_isos_paths=()
    global_available_isos_descriptions=()

    for dir in "${search_dirs[@]}"; do
        if [ -d "$dir" ]; then
            while IFS= read -r -d "" file; do
                if [[ "$file" == *.iso ]] || [[ "$file" == *.ISO ]]; then
                    local filename=$(basename "$file")
                    local size=$(du -h "$file" 2>/dev/null | cut -f1)
                    local description="$filename ($size)"

                    # D'etecter le type d'ISO
                    case "$filename" in
                        *"Mac"*|*"mac"*) description="[Mac OS] $filename ($size)" ;;
                        *"Windows"*|*"win"*) description="[Windows] $filename ($size)" ;;
                        *"Linux"*|*"linux"*) description="[Linux] $filename ($size)" ;;
                        *"DOS"*|*"dos"*) description="[DOS] $filename ($size)" ;;
                    esac

                    # 'Eviter les doublons
                    local already_found=false
                    for existing in "${global_available_isos_paths[@]}"; do
                        if [ "$existing" = "$file" ]; then
                            already_found=true
                            break
                        fi
                    done

                    if [ "$already_found" = false ]; then
                        global_available_isos+=("$filename")
                        global_available_isos_paths+=("$file")
                        global_available_isos_descriptions+=("$description")
                    fi
                fi
            done < <(find "$dir" -maxdepth 4 -type f \( -iname "*.iso" -o -iname "*.ISO" \) -print0 2>/dev/null)
        fi
    done

    # Afficher les ISOs d'etect'es
    if [ ${#global_available_isos_descriptions[@]} -gt 0 ]; then
        log_info "ISOs d'etect'es automatiquement:"
        for i in "${!global_available_isos_descriptions[@]}"; do
            log_info "  [$((i+1))] ${global_available_isos_descriptions[$i]}"
        done
    fi
}

# D'etecter les architectures QEMU disponibles
detect_available_architectures() {
    global_available_archs=()
    global_arch_descriptions=()

    # D'etecter UTM
    detect_utm

    # V'erifier chaque architecture
    for entry in "${QEMU_ARCHS[@]}"; do
        local qemu_bin=$(echo "$entry" | awk '{print $1}')
        local arch=$(echo "$entry" | awk '{print $2}')
        local desc=$(echo "$entry" | awk '{$1=""; $2=""; print substr($0,3)}')

        if command -v "$qemu_bin" &>/dev/null; then
            global_available_archs+=("$arch")
            global_arch_descriptions+=("$desc")
        fi
    done

    # Ajouter UTM comme option si disponible
    if [ "$UTM_INSTALLED" = true ]; then
        global_available_archs+=("UTM")
        global_arch_descriptions+=("UTM (Apple Silicon optimis'e) - Mac OS 9-11, Linux, Windows ARM")
    fi
}

# D'etecter UTM.app
detect_utm() {
    if [ -d "/Applications/UTM.app" ]; then
        UTM_INSTALLED=true
        UTM_PATH="/Applications/UTM.app"
    else
        UTM_INSTALLED=false
        UTM_PATH=""
    fi
}

# =============================================================================
# GESTION DES ISOS
# =============================================================================

list_isos() {
    log_header "Liste des ISOs disponibles"

    ensure_dir "$ISO_DIR"

    if [ -z "$(ls -A "$ISO_DIR")" ]; then
        log_info "Aucun ISO trouv'e dans $ISO_DIR"
        if [ -d "$SHARE_DIR" ] && [ -n "$(ls -A "$SHARE_DIR" | grep -E '\.(iso|ISO)$')" ]; then
            log_info "ISOs trouv'es dans $SHARE_DIR:"
            ls -lh "$SHARE_DIR"/*.iso "$SHARE_DIR"/*.ISO 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
        fi
        return 0
    fi

    local index=1
    disk_list=()

    echo ""
    echo "ISOs disponibles:"
    echo "-----------------"

    for iso in "$ISO_DIR"/*.iso "$ISO_DIR"/*.ISO; do
        if [ -f "$iso" ]; then
            local basename=$(basename "$iso")
            local size=$(du -h "$iso" | cut -f1)
            echo "  [$index] $basename ($size)"
            disk_list+=("$iso")
            ((index++))
        fi
    done

    if [ ${#disk_list[@]} -gt 0 ]; then
        echo ""
        read -p "S'electionnez un ISO (num'ero) ou Entrer pour annuler: " iso_choice
        if [ -n "$iso_choice" ] && [ "$iso_choice" -ge 1 ] && [ "$iso_choice" -le ${#disk_list[@]} ]; then
            selected_iso="${disk_list[$((iso_choice-1))]}"
            echo "ISO s'electionn'e: $selected_iso"
        fi
    fi

    return 0
}

download_iso() {
    log_header "T'el'echargement d'un ISO"

    ensure_dir "$ISO_DIR"

    local iso_urls=(
        "https://cdimage.debian.org/mirror/cdimage/archive/11.6.0/amd64/iso-dvd/debian-11.6.0-amd64-DVD-1.iso:Debian 11.6.0 amd64"
        "https://cdimage.ubuntu.com/releases/22.04/release/ubuntu-22.04-desktop-amd64.iso:Ubuntu 22.04 Desktop"
        "https://archlinux.org/iso/latest/archlinux-x86_64.iso:Arch Linux Latest"
    )

    echo ""
    echo "URLs pr'econfigur'ees:"
    echo "-------------------"
    for i in "${!iso_urls[@]}"; do
        IFS=':' read -r url desc <<< "${iso_urls[$i]}"
        echo "  [$((i+1))] $desc"
    done

    read -p "S'electionnez un ISO (num'ero) ou entrez une URL: " url_choice

    local iso_url=""
    local iso_name=""

    if [[ "$url_choice" =~ ^[0-9]+$ ]] && [ "$url_choice" -ge 1 ] && [ "$url_choice" -le ${#iso_urls[@]} ]; then
        IFS=':' read -r iso_url iso_name <<< "${iso_urls[$((url_choice-1))]}"
    elif [[ "$url_choice" == http* ]]; then
        iso_url="$url_choice"
        iso_name=$(basename "$url_choice")
    else
        log_error "Choix invalide"
        return 1
    fi

    local output_file="$ISO_DIR/$iso_name"

    log_info "T'el'echargement de $iso_url..."
    if command -v curl &> /dev/null; then
        curl -L -o "$output_file" "$iso_url" -# || {
            log_error "'Echec du t'el'echargement"
            rm -f "$output_file"
            return 1
        }
    elif command -v wget &> /dev/null; then
        wget -O "$output_file" "$iso_url" || {
            log_error "'Echec du t'el'echargement"
            rm -f "$output_file"
            return 1
        }
    else
        log_error "Ni curl ni wget n'est disponible"
        return 1
    fi

    if [ -f "$output_file" ]; then
        local size=$(du -h "$output_file" | cut -f1)
        log_info "ISO t'el'echarg'e: $output_file ($size)"
        selected_iso="$output_file"
        return 0
    else
        log_error "'Echec du t'el'echargement"
        return 1
    fi
}

# =============================================================================
# GESTION DES DISQUES
# =============================================================================

create_disk() {
    log_header "Cr'eation d'un disque virtuel"

    ensure_dir "$DISK_DIR"

    read -p "Nom du disque (sans extension): " disk_name
    read -p "Taille du disque (ex: 20G, 100M) [10G]: " disk_size
    read -p "Format (qcow2, raw, vmdk) [qcow2]: " disk_format

    disk_size=${disk_size:-10G}
    disk_format=${disk_format:-qcow2}
    local disk_path="$DISK_DIR/${disk_name}.${disk_format}"

    log_info "Cr'eation du disque: $disk_path ($disk_size, format: $disk_format)"

    case $disk_format in
        qcow2|raw|vmdk)
            qemu-img create -f "$disk_format" "$disk_path" "$disk_size" || return 1
            ;;
        *)
            log_error "Format non support'e: $disk_format"
            return 1
            ;;
    esac

    if [ -f "$disk_path" ]; then
        local size=$(du -h "$disk_path" | cut -f1)
        log_info "Disque cr'e'e: $disk_path ($size)"
        return 0
    else
        log_error "'Echec de la cr'eation du disque"
        return 1
    fi
}

list_disks() {
    log_header "Liste des disques virtuels"

    ensure_dir "$DISK_DIR"

    if [ -z "$(ls -A "$DISK_DIR")" ]; then
        log_info "Aucun disque trouv'e dans $DISK_DIR"
        return 0
    fi

    local index=1
    disk_list=()

    echo ""
    echo "Disques disponibles:"
    echo "-------------------"

    for disk in "$DISK_DIR"/*.qcow2 "$DISK_DIR"/*.raw "$DISK_DIR"/*.vmdk "$DISK_DIR"/*.img; do
        if [ -f "$disk" ]; then
            local basename=$(basename "$disk")
            local size=$(du -h "$disk" | cut -f1)
            echo "  [$index] $basename ($size)"
            disk_list+=("$disk")
            ((index++))
        fi
    done

    return 0
}

# =============================================================================
# GESTION DES VMS - LISTAGE
# =============================================================================

list_vms() {
    log_header "Liste des machines virtuelles"

    ensure_dir "$VM_DIR"

    if [ -z "$(ls -A "$VM_DIR")" ]; then
        log_info "Aucune VM trouv'ee dans $VM_DIR"
        return 0
    fi

    local index=1
    local vm_list=()

    echo ""
    echo "VMs disponibles:"
    echo "----------------"

    for vm_dir in "$VM_DIR"/*/; do
        if [ -d "$vm_dir" ]; then
            local vm_name=$(basename "$vm_dir")
            local vm_config="$vm_dir/config"

            local arch="Inconnu"
            local status="Arr^et'e"
            local ram="?"
            local cpu="?"
            local os_type="Inconnu"

            if [ -f "$vm_config" ]; then
                arch=$(grep -E "^arch=" "$vm_config" 2>/dev/null | cut -d= -f2)
                ram=$(grep -E "^ram=" "$vm_config" 2>/dev/null | cut -d= -f2)
                cpu=$(grep -E "^cpu=" "$vm_config" 2>/dev/null | cut -d= -f2)
                os_type=$(grep -E "^utm_os_type=" "$vm_config" 2>/dev/null | cut -d= -f2)
                [ -z "$os_type" ] && os_type="Custom"
            fi

            if [ -f "$vm_dir/pid" ]; then
                local pid=$(cat "$vm_dir/pid")
                if ps -p "$pid" &> /dev/null; then
                    status="En cours"
                fi
            fi

            # Type de VM
            local vm_type="QEMU"
            if [ "$arch" = "UTM" ]; then
                vm_type="UTM"
            fi

            echo "  [$index] $vm_name (Type: $vm_type, Arch: $arch, RAM: ${ram}MB, CPU: ${cpu}, Status: $status)"
            vm_list+=("$vm_name")
            ((index++))
        fi
    done

    if [ ${#vm_list[@]} -gt 0 ]; then
        echo ""
        read -p "S'electionnez une VM (num'ero) ou Entrer pour annuler: " vm_choice
        if [ -n "$vm_choice" ] && [ "$vm_choice" -ge 1 ] && [ "$vm_choice" -le ${#vm_list[@]} ]; then
            selected_vm="${vm_list[$((vm_choice-1))]}"
            echo "VM s'electionn'ee: $selected_vm"
        fi
    fi

    return 0
}

# =============================================================================
# GESTION DES VMS - CR'EATION
# =============================================================================

create_vm() {
    log_header "Cr'eation d'une nouvelle VM"

    ensure_dir "$VM_DIR"

    # D'etecter automatiquement les ISOs disponibles
    detect_available_isos

    # D'etecter les architectures QEMU disponibles
    detect_available_architectures

    # S'election de l'architecture
    local archs=("${global_available_archs[@]}")
    local arch_descriptions=("${global_arch_descriptions[@]}")

    # Si aucune architecture d'etect'ee, utiliser toutes les options
    if [ ${#archs[@]} -eq 0 ]; then
        archs=("68k" "68040" "apollocore" "G4" "601" "604ev" "ppc" "i86" "i386" "X86_64" "arm" "arm64" "sparc" "sparc64")
        arch_descriptions=()
        for arch in "${archs[@]}"; do
            arch_descriptions+=("$(get_arch_description "$arch")")
        done
    fi

    echo ""
    echo "S'electionnez l'architecture:"
    echo "----------------------------"
    for i in "${!archs[@]}"; do
        echo "  [$((i+1))] ${arch_descriptions[$i]}"
    done

    read -p "Architecture (num'ero): " arch_choice

    if [ -z "$arch_choice" ] || [ "$arch_choice" -lt 1 ] || [ "$arch_choice" -gt ${#archs[@]} ]; then
        log_error "Choix invalide"
        return 1
    fi

    local architecture="${archs[$((arch_choice-1))]}"

    # Sugg'erer un nom de VM bas'e sur l'architecture
    local suggested_name=""
    case $architecture in
        "68k") suggested_name="mac68k_$(date +%Y%m%d)" ;;
        "68040") suggested_name="mac68040_$(date +%Y%m%d)" ;;
        "apollocore") suggested_name="apollo_$(date +%Y%m%d)" ;;
        "G4") suggested_name="macos9_g4_$(date +%Y%m%d)" ;;
        "601") suggested_name="macos7_601_$(date +%Y%m%d)" ;;
        "604ev") suggested_name="macos9_604ev_$(date +%Y%m%d)" ;;
        "ppc") suggested_name="ppc_$(date +%Y%m%d)" ;;
        "i86") suggested_name="dos_win98_$(date +%Y%m%d)" ;;
        "i386") suggested_name="dos_i386_$(date +%Y%m%d)" ;;
        "X86_64") suggested_name="linux_x64_$(date +%Y%m%d)" ;;
        "arm") suggested_name="linux_arm_$(date +%Y%m%d)" ;;
        "arm64") suggested_name="linux_arm64_$(date +%Y%m%d)" ;;
        "sparc") suggested_name="solaris_sparc_$(date +%Y%m%d)" ;;
        "sparc64") suggested_name="solaris_sparc64_$(date +%Y%m%d)" ;;
        "UTM") suggested_name="utm_$(date +%Y%m%d)" ;;
        *) suggested_name="vm_$(date +%Y%m%d)" ;;
    esac

    # Nom de la VM
    read -p "Nom de la VM [$suggested_name]: " vm_name
    vm_name=${vm_name:-$suggested_name}

    # V'erifier si la VM existe d'ej`a
    if [ -d "$VM_DIR/$vm_name" ]; then
        log_error "La VM $vm_name existe d'ej`a"
        return 1
    fi

    # Configuration de la VM
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"

    mkdir -p "$vm_dir"

    # ================================================================
    # SI VM TYPE UTM
    # ================================================================
    if [ "$architecture" = "UTM" ]; then
        create_utm_vm "$vm_name" "$vm_dir"
        return $?
    fi

    # ================================================================
    # SI VM TYPE QEMU
    # ================================================================

    # Param`etres par d'efaut selon l'architecture
    local default_params=$(get_default_params "$architecture")
    local default_ram=$(echo "$default_params" | awk '{print $2}')
    local default_cpu=$(echo "$default_params" | awk '{print $3}')
    local default_machine=$(echo "$default_params" | awk '{print $4}')
    local default_cpu_type=$(echo "$default_params" | awk '{print $5}')
    local default_disk_size=$(echo "$default_params" | awk '{print $6}')

    # Demander les param`etres
    read -p "RAM en MB [$default_ram]: " vm_ram
    read -p "Nombre de CPU [$default_cpu]: " vm_cpu
    read -p "Taille du disque [$default_disk_size]: " vm_disk_size

    vm_ram=${vm_ram:-$default_ram}
    vm_cpu=${vm_cpu:-$default_cpu}
    vm_disk_size=${vm_disk_size:-$default_disk_size}

    # Type de r'eseau
    echo ""
    echo "Options de r'eseau:"
    echo "  [1] NAT (acc`es internet via l'h^ote)"
    echo "  [2] User (r'eseau NAT avec redirection de ports)"
    echo "  [3] Aucun"

    read -p "Type de r'eseau [1]: " network_choice
    network_choice=${network_choice:-1}

    local network_mode=""
    case $network_choice in
        1) network_mode="nat" ;;
        2) network_mode="user" ;;
        3) network_mode="none" ;;
    esac

    # Type d'affichage
    echo ""
    echo "Options d'affichage:"
    echo "  [1] cocoa (Mac natif)"
    echo "  [2] X11 (via XQuartz)"
    echo "  [3] SPICE (meilleur pour multi-'ecrans et clipboard)"
    echo "  [4] sdl"
    echo "  [5] vnc"
    echo "  [6] none (terminal)"

    read -p "Type d'affichage [1]: " display_choice
    display_choice=${display_choice:-1}

    local display_mode=""
    case $display_choice in
        1) display_mode="cocoa" ;;
        2) display_mode="x11" ;;
        3) display_mode="spice" ;;
        4) display_mode="sdl" ;;
        5) display_mode="vnc" ;;
        6) display_mode="none" ;;
    esac

    # Nombre d''ecrans
    read -p "Nombre d''ecrans [1]: " num_screens
    num_screens=${num_screens:-1}

    # Options avanc'ees
    echo ""
    echo "Options avanc'ees:"
    read -p "Activer le clipboard partage (requiert SPICE) [y/N]: " enable_clipboard
    read -p "Activer le drag & drop (requiert SPICE) [y/N]: " enable_dragdrop
    read -p "Activer le debugging GDB [y/N]: " enable_gdb

    enable_clipboard=${enable_clipboard:-n}
    enable_dragdrop=${enable_dragdrop:-n}
    enable_gdb=${enable_gdb:-n}

    # Configuration du boot
    echo ""
    echo "Options de boot:"
    echo "  [1] Boot depuis ISO"
    echo "  [2] Boot depuis disque dur"
    echo "  [3] Boot depuis les deux (ISO en premier)"

    read -p "Option de boot [1]: " boot_choice
    boot_choice=${boot_choice:-1}

    local boot_order=""
    local iso_path=""
    local disk_path="$DISK_DIR/${vm_name}.qcow2"

    case $boot_choice in
        1)
            boot_order="d"
            list_isos
            if [ -n "$selected_iso" ]; then
                iso_path="$selected_iso"
            else
                log_error "Aucun ISO s'electionn'e"
                return 1
            fi
            ;;
        2)
            boot_order="c"
            ;;
        3)
            boot_order="dc"
            list_isos
            if [ -n "$selected_iso" ]; then
                iso_path="$selected_iso"
            fi
            ;;
    esac

    # Cr'eer le disque dur
    log_info "Cr'eation du disque dur: $disk_path"
    qemu-img create -f qcow2 "$disk_path" "$vm_disk_size" || {
        log_error "'Echec de la cr'eation du disque"
        return 1
    }

    # Ecrire la configuration de la VM
    cat > "$vm_config" << EOF
# Configuration de la VM: $vm_name
# Date: $(date)

# Architecture
arch=$architecture
machine=$default_machine
cpu_type=$default_cpu_type

# Ressources
ram=$vm_ram
cpu=$vm_cpu

# Stockage
disk=$disk_path
iso=$iso_path

# R'eseau
network_mode=$network_mode

# Affichage
display=$display_mode
num_screens=$num_screens

# Options avanc'ees
enable_clipboard=$enable_clipboard
enable_dragdrop=$enable_dragdrop
enable_gdb=$enable_gdb

# Boot
boot_order=$boot_order

# Partages
share_dir=$SHARE_DIR
EOF

    log_info "VM $vm_name cr'e'ee avec succ`es!"
    log_info "Fichier de configuration: $vm_config"

    # Afficher la configuration
    echo ""
    echo "Configuration de la VM:"
    echo "  Nom: $vm_name"
    echo "  Architecture: $architecture"
    echo "  RAM: ${vm_ram}MB"
    echo "  CPU: $vm_cpu"
    echo "  Disque: $vm_disk_size ($disk_path)"
    echo "  R'eseau: $network_mode"
    echo "  Affichage: $display_mode ($num_screens 'ecran(s))"
    echo "  Boot: $boot_order"
    echo "  ISO: ${iso_path:-Aucun}"

    return 0
}

# Cr'eation d'une VM UTM
create_utm_vm() {
    local vm_name=$1
    local vm_dir=$2
    local vm_config="$vm_dir/config"

    detect_utm

    if [ "$UTM_INSTALLED" != true ]; then
        log_error "UTM.app n'est pas install'e dans /Applications/UTM.app"
        log_info "Installez UTM depuis: https://mac.getutm.app/"
        return 1
    fi

    log_header "Cr'eation d'une VM UTM: $vm_name"

    # Param`etres par d'efaut pour UTM
    local default_ram=4096
    local default_cpu=2
    local default_disk_size="20G"

    read -p "RAM en MB [$default_ram]: " vm_ram
    read -p "Nombre de CPU [$default_cpu]: " vm_cpu
    read -p "Taille du disque [$default_disk_size]: " vm_disk_size

    vm_ram=${vm_ram:-$default_ram}
    vm_cpu=${vm_cpu:-$default_cpu}
    vm_disk_size=${vm_disk_size:-$default_disk_size}

    # Type de syst`eme d'exploitation pour UTM
    echo ""
    echo "Type de syst`eme d'exploitation pour UTM:"
    local os_index=1
    local os_types_keys=()
    local os_types_descs=()
    for os_entry in "${UTM_OS_OPTIONS[@]}"; do
        os_types_keys+=("$(echo "$os_entry" | awk '{print $1}')")
        os_types_descs+=("$(echo "$os_entry" | awk '{print $2}')")
        echo "  [$os_index] ${os_types_descs[$((os_index-1))]}"
        ((os_index++))
    done

    read -p "Type [1]: " utm_os_type_choice
    utm_os_type_choice=${utm_os_type_choice:-1}

    local utm_os_type=""
    if [ "$utm_os_type_choice" -ge 1 ] && [ "$utm_os_type_choice" -le ${#os_types_keys[@]} ]; then
        utm_os_type="${os_types_keys[$((utm_os_type_choice-1))]}"
    else
        utm_os_type="macOS9"
    fi

    # Architecture UTM
    echo ""
    echo "Architecture UTM:"
    echo "  [1] PowerPC (G3/G4) - Mac OS 9, Mac OS X 10.2-10.4"
    echo "  [2] x86_64 - Linux, Windows, etc."
    echo "  [3] ARM64 - macOS 11+, Linux ARM64"

    read -p "Architecture [1]: " utm_arch_choice
    utm_arch_choice=${utm_arch_choice:-1}

    local utm_architecture=""
    case $utm_arch_choice in
        1) utm_architecture="ppc" ;;
        2) utm_architecture="x86_64" ;;
        3) utm_architecture="arm64" ;;
        *) utm_architecture="ppc" ;;
    esac

    # Mode d'affichage UTM
    echo ""
    echo "Mode d'affichage UTM:"
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

    # Options avanc'ees pour UTM
    echo ""
    echo "Options avanc'ees pour UTM:"

    # Partage de fichiers
    read -p "  Activer le partage de fichiers [y/N]: " utm_sharing
    utm_sharing=${utm_sharing:-n}
    local utm_sharing_path=""
    if [ "$utm_sharing" = "y" ]; then
        read -p "  Chemin du r'epertoire [$SHARE_DIR]: " utm_sharing_path_input
        utm_sharing_path="${utm_sharing_path_input:-$SHARE_DIR}"
    fi

    # Clipboard
    read -p "  Activer le partage clipboard [y/N]: " utm_clipboard
    utm_clipboard=${utm_clipboard:-n}

    # VNC
    read -p "  Activer VNC [y/N]: " utm_vnc
    utm_vnc=${utm_vnc:-n}
    local utm_vnc_port=5900
    if [ "$utm_vnc" = "y" ]; then
        read -p "  Port VNC [$utm_vnc_port]: " utm_vnc_port_input
        utm_vnc_port="${utm_vnc_port_input:-$utm_vnc_port}"
    fi

    # Mode r'eseau UTM
    echo ""
    echo "Mode r'eseau UTM:"
    echo "  [1] Partag'e (NAT)"
    echo "  [2] Pont (bridged)"
    echo "  [3] H^ote seulement"
    echo "  [4] D'econnect'e"

    read -p "  Mode r'eseau [1]: " utm_network_choice
    utm_network_choice=${utm_network_choice:-1}

    local utm_network_mode=""
    case $utm_network_choice in
        1) utm_network_mode="shared" ;;
        2) utm_network_mode="bridged" ;;
        3) utm_network_mode="host" ;;
        4) utm_network_mode="disconnected" ;;
        *) utm_network_mode="shared" ;;
    esac

    # Mode d''emulation: SoftMMU ou System
    echo ""
    echo "Mode d''emulation UTM:"
    echo "  [1] SoftMMU ('emulation logicielle) - Fonctionne toujours"
    echo "  [2] System (acc'el'eration mat'erielle) - Plus rapide, si disponible"

    local system_mode_available=false
    case $utm_architecture in
        "arm64") system_mode_available=true ;;
        "x86_64") system_mode_available=true ;;
        "ppc")
            echo "  Note: PowerPC ne supporte que SoftMMU"
            system_mode_available=false
            ;;
    esac

    local utm_hardware_accel=false
    if [ "$system_mode_available" = true ]; then
        read -p "  Mode [1]: " utm_emulator_choice
        utm_emulator_choice=${utm_emulator_choice:-1}
        case $utm_emulator_choice in
            1) utm_hardware_accel=false ;;
            2) utm_hardware_accel=true ;;
            *) utm_hardware_accel=false ;;
        esac
    else
        utm_hardware_accel=false
        log_info "  Utilisation automatique de SoftMMU"
    fi

    # Boot order
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

    # S'electionner un ISO si boot depuis CD
    if [ "$boot_order" = "d" ] || [ "$boot_order" = "dc" ]; then
        list_isos
        if [ -n "$selected_iso" ]; then
            iso_path="$selected_iso"
        fi
    fi

    # Cr'eer le disque UTM
    local utm_disk_path="$DISK_DIR/${vm_name}.qcow2"
    log_info "Cr'eation du disque: $utm_disk_path"
    qemu-img create -f qcow2 "$utm_disk_path" "$vm_disk_size" || {
        log_error "'Echec de la cr'eation du disque"
        return 1
    }

    # Sauvegarder la configuration UTM
    cat > "$vm_config" << EOF
# Configuration de la VM UTM: $vm_name
# Date: $(date)

# Type UTM
utm_os_type=$utm_os_type
utm_architecture=$utm_architecture
utm_display=$utm_display

# Options UTM
utm_sharing=$utm_sharing
utm_sharing_path=$utm_sharing_path
utm_clipboard=$utm_clipboard
utm_vnc=$utm_vnc
utm_vnc_port=$utm_vnc_port
utm_network_mode=$utm_network_mode
utm_hardware_accel=$utm_hardware_accel

# Ressources
ram=$vm_ram
cpu=$vm_cpu

# Stockage
disk=$utm_disk_path
iso=$iso_path

# Boot
boot_order=$boot_order

# R'eseau
network_mode=native

# Pour compatibilit'e avec QEMU
arch=UTM
machine=
display=$utm_display
EOF

    # Cr'eer le fichier UTM JSON pour import
    create_utm_config "$vm_name" "$vm_dir" "$utm_os_type" "$utm_architecture" "$vm_ram" "$vm_cpu" "$utm_disk_path" "$iso_path" "$utm_display" "$utm_sharing" "$utm_sharing_path" "$utm_clipboard" "$utm_vnc" "$utm_vnc_port" "$utm_network_mode" "$utm_hardware_accel"

    log_info "VM UTM $vm_name cr'e'ee!"
    log_info "Fichier de configuration: $vm_config"
    log_info "Fichier UTM JSON: $vm_dir/${vm_name}.utm.json"
    log_info "Pour importer dans UTM:"
    log_info "  1. Ouvrir UTM.app"
    log_info "  2. Cliquer sur 'Create VM'"
    log_info "  3. S'electionner 'Import Existing Virtual Machine'"
    log_info "  4. Choisir le fichier: $vm_dir/${vm_name}.utm.json"

    return 0
}

# Cr'eer un fichier de configuration UTM (.utm.json)
create_utm_config() {
    local vm_name=$1
    local vm_dir=$2
    local os_type=$3
    local architecture=$4
    local ram_mb=$5
    local cpu_count=$6
    local disk_path=$7
    local iso_path=$8
    local display_mode=$9
    local enable_sharing=${10:-false}
    local sharing_path=${11:-$SHARE_DIR}
    local enable_clipboard=${12:-false}
    local enable_vnc=${13:-false}
    local vnc_port=${14:-5900}
    local network_mode_utm=${15:-shared}
    local hardware_accel=${16:-false}

    local utm_json_file="$vm_dir/${vm_name}.utm.json"

    # Determiner l'UUID
    local vm_uuid=$(uuidgen 2>/dev/null || echo "$(date +%s)-$(openssl rand -hex 8)")
    local disk_uuid=$(uuidgen 2>/dev/null || echo "$(date +%s)-$(openssl rand -hex 8)")
    local iso_uuid=""
    if [ -n "$iso_path" ]; then
        iso_uuid=$(uuidgen 2>/dev/null || echo "$(date +%s)-$(openssl rand -hex 8)")
    fi

    # Configurer le syst`eme
    local system_architecture=""
    local system_type=""
    local system_boot_device=""

    case $architecture in
        "ppc")
            system_architecture="powerpc"
            system_type="mac99"
            system_boot_device="cdrom"
            ;;
        "x86_64")
            system_architecture="x86_64"
            system_type="q35"
            system_boot_device="harddrive"
            ;;
        "arm64")
            system_architecture="aarch64"
            system_type="virt"
            system_boot_device="harddrive"
            ;;
    esac

    case $os_type in
        "macOS9") system_boot_device="cdrom" ;;
        "macOS10.4"|"macOS10.5") system_boot_device="harddrive" ;;
    esac

    # Convertir la RAM en octets
    local ram_bytes=$((ram_mb * 1024 * 1024))

    # Cr'eer le JSON UTM
    cat > "$utm_json_file" << JSONEOF
{
  "identifier": "$vm_uuid",
  "name": "$vm_name",
  "notes": "Cr'e'ee par VM Assistant",
  "configVersion": 3,
  "configuration": {
    "system": {
      "architecture": "$system_architecture",
      "type": "$system_type",
      "bootDevice": "$system_boot_device",
      "cpuCount": $cpu_count,
      "memory": $ram_bytes,
      "hardwareType": "$(echo $system_architecture | tr '[:lower:]' '[:upper:]')",
      "hardwareAcceleration": $hardware_accel
    },
    "display": {
      "consoleOnly": false
    },
JSONEOF

    # Ajouter consoleOnly si terminal
    if [ "$display_mode" = "terminal" ]; then
        # D'ej`a false par d'efaut, on peut laisser
        :
    fi

    cat >> "$utm_json_file" << JSONEOF
    "sharing": {
      "enabled": $( [ "$enable_sharing" = "y" ] && echo "true" || echo "false" ),
      "directoryPath": "$sharing_path"
    },
    "serial": {
      "mode": "disconnected"
    },
    "clipboard": {
      "enabled": $( [ "$enable_clipboard" = "y" ] && echo "true" || echo "false" )
    },
    "network": {
      "mode": "$network_mode_utm",
      "devices": []
    }
JSONEOF

    # Ajouter VNC si activ'e
    if [ "$enable_vnc" = "y" ]; then
        cat >> "$utm_json_file" << JSONEOF
    ,
    "vnc": {
      "enabled": true,
      "port": $vnc_port
    }
JSONEOF
    fi

    cat >> "$utm_json_file" << JSONEOF
  },
  "data": {
    "drives": [
      {
        "identifier": "$disk_uuid",
        "interface": "virtio",
        "index": 0,
        "removable": false,
        "bootPriority": 1,
        "imagePath": "$disk_path"
      }
JSONEOF

    # Ajouter l'ISO si pr'esent
    if [ -n "$iso_path" ]; then
        cat >> "$utm_json_file" << JSONEOF
      ,
      {
        "identifier": "$iso_uuid",
        "interface": "ide",
        "index": 1,
        "removable": true,
        "bootPriority": 0,
        "imagePath": "$iso_path"
      }
JSONEOF
    fi

    # Fermer le JSON
    cat >> "$utm_json_file" << JSONEOF
    ]
  },
  "metadata": {
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "lastUpdated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "version": 3
  }
}
JSONEOF

    log_info "Fichier UTM JSON cr'e'e: $utm_json_file"
}

# =============================================================================
# GESTION DES VMS - D'EMARRAGE QEMU
# Bas'e sur la commande UTM fonctionnelle pour Mac OS 9.2
# =============================================================================

start_qemu_vm() {
    local vm_name=$1
    local vm_dir=$2
    local vm_config=$3

    source "$vm_config" || {
        log_error "Impossible de charger la configuration: $vm_config"
        return 1
    }

    log_header "D'emarrage de la VM QEMU: $vm_name"

    # D'eterminer le binaire QEMU
    local qemu_cmd=$(get_qemu_bin "$arch")
    if [ -z "$qemu_cmd" ]; then
        qemu_cmd="qemu-system-$arch"
    fi

    if ! command -v "$qemu_cmd" &> /dev/null; then
        log_error "Commande QEMU introuvable: $qemu_cmd"
        return 1
    fi

    # D'etecter le chemin BIOS pour PowerPC
    local bios_path=""
    case $arch in
        "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
            # Chemin BIOS pour PowerPC (n'ecessaire pour Mac OS 9)
            local bios_dirs=(
                "/Users/xenon/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu"
                "/usr/local/share/qemu"
                "/usr/share/qemu"
                "/opt/local/share/qemu"
            )
            for dir in "${bios_dirs[@]}"; do
                if [ -f "$dir/openbios-ppc" ]; then
                    bios_path="$dir"
                    break
                fi
            done
            ;;
    esac

    # V'erifier si XQuartz est n'ecessaire
    if [ "$display" = "x11" ]; then
        if ! pgrep -x "Xquartz" &> /dev/null; then
            log_warn "XQuartz n'est pas en cours d'ex'ecution"
            log_info "Lancez XQuartz avec: open -a XQuartz"
            read -p "Voulez-vous continuer? (y/N): " continue_choice
            if [ "$continue_choice" != "y" ]; then
                return 1
            fi
        fi
    fi

    # Construction de la commande QEMU
    local qemu_args=()

    # BIOS path pour PowerPC (n'ecessaire pour Mac OS 9)
    if [ -n "$bios_path" ]; then
        qemu_args+=("-L" "$bios_path")
    fi

    # RAM
    qemu_args+=("-m" "${ram}M")

    # CPU
    qemu_args+=("-smp" "$cpu")

    # Machine et CPU - pour PowerPC, ces options seront ajout'ees dans la section sp'ecifique
    local is_ppc=false
    case $arch in
        "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
            is_ppc=true
            ;;
    esac

    if [ "$is_ppc" = false ]; then
        # Machine
        if [ -n "$machine" ]; then
            qemu_args+=("-machine" "$machine")
        fi

        # Type de CPU
        if [ -n "$cpu_type" ]; then
            qemu_args+=("-cpu" "$cpu_type")
        fi
    fi

    # Boot order et stockage - m'ethode d'epend de l'architecture

    if [ "$is_ppc" = false ]; then
        # M'ethode standard pour non-PPC
        if [ -n "$boot_order" ]; then
            qemu_args+=("-boot" "$boot_order")
        fi

        # Disque dur
        if [ -n "$disk" ] && [ -f "$disk" ]; then
            local disk_if="virtio"
            case $arch in
                "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
                    disk_if="ide"
                    ;;
            esac
            qemu_args+=("-drive" "file=$disk,format=qcow2,if=$disk_if")
        fi

        # ISO
        if [ -n "$iso" ] && [ -f "$iso" ]; then
            qemu_args+=("-cdrom" "$iso")
        fi
    fi

    # Configuration r'eseau
    case $network_mode in
        "nat"|"user")
            case $arch in
                "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
                    # PPC utilise sungem + vmnet-shared (comme dans UTM)
                    local mac_addr=$(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/:$//')
                    qemu_args+=("-device" "sungem,mac=$mac_addr,netdev=net0")
                    qemu_args+=("-netdev" "vmnet-shared,id=net0")
                    ;;
                *)
                    # x86 et autres
                    qemu_args+=("-netdev" "user,id=mynet0,net=192.168.100.0/24,dhcpstart=192.168.100.100")
                    qemu_args+=("-device" "virtio-net-pci,netdev=mynet0")
                    ;;
            esac
            ;;
        "none")
            # Pas de r'eseau
            ;;
    esac

    # Configuration d'affichage
    local spice_supported=true
    case $arch in
        "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
            if ! $qemu_cmd -help 2>&1 | grep -q "spice"; then
                spice_supported=false
                log_warn "SPICE non support'e pour $arch, utilisation de cocoa"
            fi
            ;;
    esac

    case $display in
        "x11")
            qemu_args+=("-display" "x11")
            ;;
        "spice")
            if [ "$spice_supported" = false ]; then
                qemu_args+=("-display" "cocoa")
                qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
                if [ "$num_screens" -gt 1 ]; then
                    for (( i=1; i<num_screens; i++ )); do
                        qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
                    done
                fi
                log_warn "SPICE non disponible, utilisation de display cocoa"
            else
                local spice_port=$((SPICE_PORT + $(echo "$vm_name" | tr -cd '0-9') % 100))
                qemu_args+=("-spice" "port=$spice_port,addr=127.0.0.1,disable-ticketing=on")
                qemu_args+=("-device" "virtio-serial-pci")
                qemu_args+=("-device" "virtserialport,chardev=spicechannel0,name=com.redhat.spice.0")
                qemu_args+=("-chardev" "spicevmc,id=spicechannel0,name=vdagent")

                if [ "$enable_clipboard" = "y" ]; then
                    qemu_args+=("-device" "virtio-serial-pci")
                    qemu_args+=("-device" "virtserialport,chardev=spicechannel1,name=com.redhat.spice.1")
                    qemu_args+=("-chardev" "spicevmc,id=spicechannel1,name=vdagent")
                fi

                for (( i=0; i<num_screens; i++ )); do
                    qemu_args+=("-device" "qxl-vga,id=video$i")
                done

                log_info "Connexion SPICE: spicy -h 127.0.0.1 -p $spice_port"
            fi
            ;;
        "sdl")
            qemu_args+=("-display" "sdl")
            ;;
        "cocoa")
            qemu_args+=("-display" "cocoa")
            ;;
        "vnc")
            local vnc_port=$((VNC_BASE_PORT + $(echo "$vm_name" | tr -cd '0-9') % 100))
            qemu_args+=("-vnc" "127.0.0.1:$vnc_port")
            log_info "Connexion VNC: vncviewer 127.0.0.1:$vnc_port"
            ;;
        "none")
            qemu_args+=("-nographic")
            ;;
    esac

    # Partage de fichiers (9p)
    if [ -d "$share_dir" ]; then
        qemu_args+=("-fsdev" "local,security_model=mapped,id=fsdev0,path=$share_dir")
        local fsdev_device="virtio-9p-pci"
        case $arch in
            "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
                # PPC ne supporte pas virtio-9p-pci
                ;;
            *)
                qemu_args+=("-device" "$fsdev_device,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare")
                ;;
        esac
    fi

    # Debugging GDB
    if [ "$enable_gdb" = "y" ]; then
        qemu_args+=("-gdb" "tcp::${GDB_PORT}")
        qemu_args+=("-S")
        log_info "Debugging GDB actif sur le port ${GDB_PORT}"
        log_info "Connectez-vous avec: gdb -ex 'target remote localhost:${GDB_PORT}'"
    fi

    # Options sp'ecifiques pour PowerPC
    case $arch in
        "G4"|"604ev"|"ppc")
            local ppc_machine="${machine:-mac99}"
            if [ "$arch" = "604ev" ] || [ "$arch" = "ppc" ]; then
                ppc_machine="g3beige"
            fi
            local via_type="${via:-cuda}"
            qemu_args+=("-machine" "${ppc_machine},via=${via_type}")
            qemu_args+=("-cpu" "${cpu_type:-750}")
            qemu_args+=("-accel" "tcg,tb-size=128")
            
            # Multi-screen methods for PowerPC/Mac OS 9
            # Supported methods: dual-pci-vga, graphic-engine, auto
            local multi_screen_method="${multi_screen_method:-auto}"
            
            if [ "$num_screens" -gt 1 ]; then
                case "$multi_screen_method" in
                    "graphic-engine")
                        # Method graphic-drawing-engine (requires QEMU with qfb patches)
                        qemu_args+=("-device" "graphic-drawing-engine,heads=${num_screens}")
                        log_info "Multi-'ecran: m'ethode graphic-drawing-engine (heads=${num_screens})"
                        ;;
                    "dual-pci-vga")
                        # M'ethode Dual-PCI VGA Device Hack
                        qemu_args+=("-prom-env" "vga-ndrv?=true")
                        qemu_args+=("-g" "1024x768x32")
                        qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video0,xres=1024,yres=768")
                        for (( screen_num=1; screen_num<num_screens; screen_num++ )); do
                            local screen_id="video$screen_num"
                            qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=$screen_id,xres=1024,yres=768")
                        done
                        log_info "Multi-ecran: methode Dual-PCI VGA (${num_screens} ecrans)"
                        ;;
                    "auto"|""")
                        # Auto-d'etection: essayer graphic-engine d'abord, sinon dual-pci-vga
                        if qemu_device_exists "graphic-drawing-engine"; then
                            qemu_args+=("-device" "graphic-drawing-engine,heads=${num_screens}")
                            log_info "Multi-ecran: methode graphic-drawing-engine detectee (heads=${num_screens})"
                        else
                            qemu_args+=("-prom-env" "vga-ndrv?=true")
                            qemu_args+=("-g" "1024x768x32")
                            qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video0,xres=1024,yres=768")
                            for (( screen_num=1; screen_num<num_screens; screen_num++ )); do
                                local screen_id="video$screen_num"
                                qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=$screen_id,xres=1024,yres=768")
                            done
                            log_info "Multi-ecran: methode Dual-PCI VGA (graphic-drawing-engine not available)"
                        fi
                        ;;
                esac
            else
                # Pour 1 'ecran, utiliser seulement le device VGA
                qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
            fi

            # M'ethode UTM pour PowerPC : utiliser bootindex au lieu de -boot/-cdrom
            # CDROM boot en premier (bootindex=0), HDD en second (bootindex=1)
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "if=none,media=disk,id=drive0,file=$disk,format=qcow2")
                qemu_args+=("-device" "ide-hd,bus=ide.0,unit=0,drive=drive0,bootindex=1")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-drive" "if=none,media=cdrom,id=drive1,file=$iso,readonly=on")
                qemu_args+=("-device" "ide-cd,bus=ide.0,unit=1,drive=drive1,bootindex=0")
            fi

            # Son pour PowerPC (es1370 pour mac99, comme dans UTM)
            if [ "$sound" = "screamer" ] || [ "$sound" = "es1370" ]; then
                qemu_args+=("-audiodev" "coreaudio,id=sound0")
                qemu_args+=("-device" "es1370,id=sound0")
            fi

            # Utiliser boot-command pour Mac OS (plus fiable que auto-boot)
            qemu_args+=("-prom-env" "boot-args=-v")
            qemu_args+=("-prom-env" "vga-ndrv?=true")
            qemu_args+=("-prom-env" "boot-command=init-program go")

            # Ajouter le loader NDRV
            local ndrv_loader=""
            local ndrv_paths=(
                "/usr/local/share/qemu/ppc-ndrvloader"
                "/usr/share/qemu/ppc-ndrvloader"
                "/opt/local/share/qemu/ppc-ndrvloader"
                "$HOME/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu/ppc-ndrvloader"
                "/Library/Application Support/UTM/qemu/ppc-ndrvloader"
            )

            for path in "${ndrv_paths[@]}"; do
                if [ -f "$path" ]; then
                    ndrv_loader="$path"
                    break
                fi
            done

            if [ -n "$ndrv_loader" ] && [ -f "$ndrv_loader" ]; then
                qemu_args+=("-device" "loader,addr=0x4000000,file=$ndrv_loader")
                log_info "Loader NDRV utilis'e: $ndrv_loader"
            else
                log_warn "Loader NDRV non trouv'e. Mac OS peut d'emarrer mais sans support r'eseau optimis'e."
            fi
            ;;
        "601")
            qemu_args+=("-machine" "g3beige")
            qemu_args+=("-cpu" "${cpu_type:-601}")
            qemu_args+=("-accel" "tcg")
            # Utiliser -vga none + device VGA comme dans la config UTM qui fonctionne
            qemu_args+=("-vga" "none")
            qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
            # M'ethode UTM pour PowerPC
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "if=none,media=disk,id=drive0,file=$disk,format=qcow2")
                qemu_args+=("-device" "ide-hd,bus=ide.0,unit=0,drive=drive0,bootindex=0")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-drive" "if=none,media=cdrom,id=drive1,file=$iso,readonly=on")
                qemu_args+=("-device" "ide-cd,bus=ide.0,unit=1,drive=drive1,bootindex=1")
            fi
            qemu_args+=("-prom-env" "boot-command=init-program go")
            ;;
        "apollocore")
            qemu_args+=("-machine" "q800")
            qemu_args+=("-cpu" "${cpu_type:-68080}")
            qemu_args+=("-accel" "tcg")
            # Utiliser -vga none + device VGA comme dans la config UTM qui fonctionne
            qemu_args+=("-vga" "none")
            qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
            # M'ethode UTM pour PowerPC
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "if=none,media=disk,id=drive0,file=$disk,format=qcow2")
                qemu_args+=("-device" "ide-hd,bus=ide.0,unit=0,drive=drive0,bootindex=0")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-drive" "if=none,media=cdrom,id=drive1,file=$iso,readonly=on")
                qemu_args+=("-device" "ide-cd,bus=ide.0,unit=1,drive=drive1,bootindex=1")
            fi
            qemu_args+=("-prom-env" "boot-command=init-program go")
            ;;
        "68k"|"68040")
            qemu_args+=("-accel" "tcg")
            # 68k ne supporte pas -vga std, utiliser m'ethode standard
            if [ -n "$boot_order" ]; then
                qemu_args+=("-boot" "$boot_order")
            else
                qemu_args+=("-boot" "c")
            fi
            # Disques avec if=ide pour 68k (m'ethode standard)
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-hda" "$disk")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-cdrom" "$iso")
            fi
            ;;
        "i86"|"i386")
            qemu_args+=("-accel" "tcg")
            ;;
        "X86_64")
            qemu_args+=("-accel" "tcg")
            qemu_args+=("-enable-kvm")
            qemu_args+=("-cpu" "host,migratable=off")
            ;;
        "arm"|"arm64"|"sparc"|"sparc64")
            qemu_args+=("-accel" "tcg")
            ;;
    esac

    # Executer QEMU
    log_info "D'emarrage de la VM avec la commande:"
    echo "  $qemu_cmd ${qemu_args[*]}"
    echo ""

    # Rediriger stderr vers un fichier de log
    $qemu_cmd "${qemu_args[@]}" 2>"$vm_dir/qemu.log" &

    # Enregistrer le PID
    local qemu_pid=$!
    echo "$qemu_pid" > "$vm_dir/pid"

    log_info "VM $vm_name d'emarr'ee avec le PID: $qemu_pid"
    log_info "Pour arr^eter la VM: kill $qemu_pid"
    log_info "Logs: $vm_dir/qemu.log"

    return 0
}

# D'emarrer une VM (fonction principale)
start_vm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"

    if [ ! -f "$vm_config" ]; then
        log_error "Configuration de la VM introuvable: $vm_config"
        return 1
    fi

    # Valider la configuration avant de d'emarrer
    validate_vm_config "$vm_name" || {
        log_error "Impossible de d'emarrer la VM: configuration invalide"
        return 1
    }

    # Charger la configuration
    source "$vm_config"

    # V'erifier si c'est une VM UTM
    if [ "$arch" = "UTM" ]; then
        start_utm_vm "$vm_name" "$vm_dir" "$vm_config"
        return $?
    fi

    # D'emarrer comme QEMU
    start_qemu_vm "$vm_name" "$vm_dir" "$vm_config"
    return $?
}

# D'emarrer une VM UTM
start_utm_vm() {
    local vm_name=$1
    local vm_dir=$2
    local vm_config=$3

    source "$vm_config" || {
        log_error "Impossible de charger la configuration UTM: $vm_config"
        return 1
    }

    log_header "D'emarrage de la VM UTM: $vm_name"

    local utm_json_file="$vm_dir/${vm_name}.utm.json"

    if [ ! -f "$utm_json_file" ]; then
        log_error "Fichier UTM JSON introuvable: $utm_json_file"
        return 1
    fi

    # V'erifier si UTM est install'e
    detect_utm
    if [ "$UTM_INSTALLED" != true ]; then
        log_error "UTM.app n'est pas install'e"
        return 1
    fi

    # Ouvrir UTM avec l'URL d'import
    local utm_url="utm://import?url=file://$(echo "$utm_json_file" | sed 's|/|%2F|g')"
    log_info "Ouverture de UTM avec: $utm_url"
    open "$utm_url"
    log_info "UTM devrait s'ouvrir avec la VM."
    log_info "Si ce n'est pas le cas, importez manuellement: $utm_json_file"

    return 0
}

# =============================================================================
# VALIDATION DE LA CONFIGURATION VM
# =============================================================================

validate_vm_config() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"

    if [ ! -f "$vm_config" ]; then
        log_error "Fichier de configuration introuvable: $vm_config"
        return 1
    fi

    source "$vm_config" || {
        log_error "Impossible de charger la configuration: $vm_config"
        return 1
    }

    # V'erifier les param`etres essentiels
    if [ -z "$arch" ]; then
        log_error "Architecture non sp'ecifi'ee dans la configuration"
        return 1
    fi

    if [ -z "$ram" ]; then
        log_error "RAM non sp'ecifi'ee dans la configuration"
        return 1
    fi

    if [ -z "$cpu" ]; then
        log_error "CPU non sp'ecifi'e dans la configuration"
        return 1
    fi

    # V'erifier que QEMU est disponible pour cette architecture
    if [ "$arch" != "UTM" ]; then
        local qemu_cmd=$(get_qemu_bin "$arch")
        if [ -z "$qemu_cmd" ]; then
            qemu_cmd="qemu-system-$arch"
        fi
        
        if ! command -v "$qemu_cmd" &> /dev/null; then
            log_error "QEMU non trouv'e pour l'architecture $arch: $qemu_cmd"
            return 1
        fi
    else
        # V'erifier UTM
        detect_utm
        if [ "$UTM_INSTALLED" != true ]; then
            log_error "UTM.app est requis pour cette VM mais n'est pas install'e"
            return 1
        fi
    fi

    # V'erifier que le disque existe
    if [ -n "$disk" ] && [ ! -f "$disk" ]; then
        log_error "Disque introuvable: $disk"
        return 1
    fi

    # V'erifier que l'ISO existe si sp'ecifi'e
    if [ -n "$iso" ] && [ "$iso" != "Aucun" ] && [ ! -f "$iso" ]; then
        log_warn "ISO introuvable: $iso"
    fi

    # V'erifier que le r'epertoire de partage existe
    if [ -n "$share_dir" ] && [ ! -d "$share_dir" ]; then
        log_warn "R'epertoire de partage introuvable: $share_dir"
    fi

    log_info "Configuration de la VM $vm_name est valide"
    return 0
}

# =============================================================================
# ARR^ETER UNE VM
# =============================================================================

stop_vm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"

    if [ ! -d "$vm_dir" ]; then
        log_error "VM introuvable: $vm_name"
        return 1
    fi

    if [ ! -f "$vm_config" ]; then
        log_error "Configuration de la VM introuvable: $vm_config"
        return 1
    fi

    # V'erifier si la VM est en cours d'ex'ecution
    local pid_file="$vm_dir/pid"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" &> /dev/null; then
            log_info "Arr^et de la VM $vm_name (PID: $pid)..."
            kill "$pid" 2>/dev/null
            
            # Attendre que le processus soit termin'e
            local count=0
            while ps -p "$pid" &> /dev/null && [ $count -lt 10 ]; do
                sleep 1
                ((count++))
            done
            
            if ps -p "$pid" &> /dev/null; then
                log_warn "La VM n'a pas r'epondu au signal TERM, tentative avec KILL..."
                kill -9 "$pid" 2>/dev/null
                sleep 1
            fi
            
            # Supprimer le fichier PID
            rm -f "$pid_file"
            log_info "VM $vm_name arr^et'ee"
            return 0
        else
            log_info "La VM $vm_name n'est pas en cours d'ex'ecution (PID $pid inexistant)"
            rm -f "$pid_file"
            return 0
        fi
    else
        log_info "La VM $vm_name n'est pas en cours d'ex'ecution (pas de fichier PID)"
        return 0
    fi
}

# =============================================================================
# MODIFIER UNE VM
# =============================================================================

edit_vm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"

    if [ ! -d "$vm_dir" ]; then
        log_error "VM introuvable: $vm_name"
        return 1
    fi

    if [ ! -f "$vm_config" ]; then
        log_error "Configuration de la VM introuvable: $vm_config"
        return 1
    fi

    # Charger la configuration actuelle
    source "$vm_config" || {
        log_error "Impossible de charger la configuration: $vm_config"
        return 1
    }

    log_header "Modification de la VM: $vm_name"

    # V'erifier si c'est une VM UTM
    if [ "$arch" = "UTM" ]; then
        log_info "Modification des VMs UTM n'ecessite une recr'eation."
        log_info "Supprimez et recr'eez la VM pour modifier ses param`etres."
        read -p "Voulez-vous recr'eer cette VM? (y/N): " recreate_choice
        if [ "$recreate_choice" = "y" ]; then
            # Sauvegarder les infos importantes
            local old_disk="$disk"
            local old_iso="$iso"
            
            # Supprimer la VM
            delete_vm "$vm_name" || return 1
            
            # Recr'eer avec les m^emes param`etres
            selected_iso="$old_iso"
            create_utm_vm "$vm_name" "$VM_DIR/$vm_name" || return 1
            
            log_info "VM $vm_name recr'e'ee"
        fi
        return 0
    fi

    echo "Configuration actuelle:"
    echo "  Architecture: $arch ($machine, CPU: $cpu_type)"
    echo "  RAM: ${ram}MB"
    echo "  CPU: $cpu"
    echo "  Disque: $disk"
    echo "  ISO: ${iso:-Aucun}"
    echo "  R'eseau: $network_mode"
    echo "  Affichage: $display ($num_screens 'ecran(s))"
    echo "  Boot: $boot_order"
    echo ""

    # Menu de modification
    echo "Que voulez-vous modifier?"
    echo "  [1] Nom de la VM"
    echo "  [2] Architecture/CPU"
    echo "  [3] RAM"
    echo "  [4] Nombre de CPU"
    echo "  [5] Disque dur"
    echo "  [6] ISO"
    echo "  [7] R'eseau"
    echo "  [8] Affichage"
    echo "  [9] Options de boot"
    echo "  [10] Options avanc'ees (clipboard, dragdrop, GDB)"
    echo "  [11] Tout modifier"
    echo "  [12] Terminer"
    echo ""

    read -p "Choix: " edit_choice
    case "$edit_choice" in
        1)
            read -p "Nouveau nom de la VM [$vm_name]: " new_vm_name
            new_vm_name=${new_vm_name:-$vm_name}
            if [ "$new_vm_name" != "$vm_name" ]; then
                # Renommer le dossier
                if [ -d "$VM_DIR/$new_vm_name" ]; then
                    log_error "Une VM avec ce nom existe d'ej`a"
                    return 1
                fi
                mv "$vm_dir" "$VM_DIR/$new_vm_name" || {
                    log_error "'Echec du renommage"
                    return 1
                }
                vm_dir="$VM_DIR/$new_vm_name"
                vm_config="$vm_dir/config"
                vm_name="$new_vm_name"
                sed -i '' "s|^# Configuration de la VM: .*|# Configuration de la VM: $vm_name|" "$vm_config"
                log_info "VM renomm'ee en $new_vm_name"
            fi
            ;;
        2)
            # Modifier l'architecture
            echo "Architectures disponibles:"
            for i in "${!QEMU_ARCHS[@]}"; do
                local entry="${QEMU_ARCHS[$i]}"
                local qemu_bin=$(echo "$entry" | awk '{print $1}')
                local arch_name=$(echo "$entry" | awk '{print $2}')
                local desc=$(echo "$entry" | awk '{$1=""; $2=""; print substr($0,3)}')
                if command -v "$qemu_bin" &>/dev/null; then
                    echo "  [$((i+1))] $desc"
                else
                    echo "  [$((i+1))] $desc (non disponible)"
                fi
            done
            read -p "Nouvelle architecture (num'ero): " new_arch_choice
            if [ -n "$new_arch_choice" ] && [ "$new_arch_choice" -ge 1 ] && [ "$new_arch_choice" -le ${#QEMU_ARCHS[@]} ]; then
                local new_entry="${QEMU_ARCHS[$((new_arch_choice-1))]}"
                architecture=$(echo "$new_entry" | awk '{print $2}')
                machine=$(echo "$new_entry" | awk '{print $3}')
                cpu_type=$(echo "$new_entry" | awk '{print $4}')
                
                # Mettre `a jour les param`etres par d'efaut
                local new_default_params=$(get_default_params "$architecture")
                ram=$(echo "$new_default_params" | awk '{print $2}')
                cpu=$(echo "$new_default_params" | awk '{print $3}')
                
                log_info "Architecture modifi'ee en $architecture"
            fi
            ;;
        3) read -p "Nouvelle RAM en MB [$ram]: " ram; ram=${ram:-$ram} ;;
        4) read -p "Nouveau nombre de CPU [$cpu]: " cpu; cpu=${cpu:-$cpu} ;;
        5)
            # Modifier le disque
            echo "Disques disponibles:"
            list_disks
            read -p "Nouveau disque (chemin complet) [$disk]: " new_disk
            new_disk=${new_disk:-$disk}
            if [ -f "$new_disk" ]; then
                disk="$new_disk"
                log_info "Disque modifi'e"
            else
                log_error "Disque introuvable: $new_disk"
                return 1
            fi
            ;;
        6)
            # Modifier l'ISO
            list_isos
            if [ -n "$selected_iso" ]; then
                iso="$selected_iso"
                log_info "ISO modifi'e"
            fi
            ;;
        7)
            # Modifier le r'eseau
            echo "Options de r'eseau:"
            echo "  [1] NAT (acc`es internet via l'h^ote)"
            echo "  [2] User (r'eseau NAT avec redirection de ports)"
            echo "  [3] Aucun"
            read -p "Type de r'eseau [$network_mode]: " new_network_choice
            case "$new_network_choice" in
                1) network_mode="nat" ;;
                2) network_mode="user" ;;
                3) network_mode="none" ;;
            esac
            ;;
        8)
            # Modifier l'affichage
            echo "Options d'affichage:"
            echo "  [1] cocoa (Mac natif)"
            echo "  [2] X11 (via XQuartz)"
            echo "  [3] SPICE (meilleur pour multi-'ecrans et clipboard)"
            echo "  [4] sdl"
            echo "  [5] vnc"
            echo "  [6] none (terminal)"
            read -p "Type d'affichage [$display]: " new_display_choice
            case "$new_display_choice" in
                1) display="cocoa" ;;
                2) display="x11" ;;
                3) display="spice" ;;
                4) display="sdl" ;;
                5) display="vnc" ;;
                6) display="none" ;;
            esac
            read -p "Nombre d''ecrans [$num_screens]: " num_screens
            num_screens=${num_screens:-$num_screens}
            ;;
        9)
            # Modifier l'ordre de boot
            echo "Options de boot:"
            echo "  [1] Boot depuis ISO"
            echo "  [2] Boot depuis disque dur"
            echo "  [3] Boot depuis les deux (ISO en premier)"
            read -p "Option de boot [$boot_order]: " new_boot_choice
            case "$new_boot_choice" in
                1) boot_order="d" ;;
                2) boot_order="c" ;;
                3) boot_order="dc" ;;
            esac
            ;;
        10)
            # Options avanc'ees
            read -p "Activer le clipboard partage (requiert SPICE) [${enable_clipboard}]: " enable_clipboard
            enable_clipboard=${enable_clipboard:-$enable_clipboard}
            read -p "Activer le drag & drop (requiert SPICE) [${enable_dragdrop}]: " enable_dragdrop
            enable_dragdrop=${enable_dragdrop:-$enable_dragdrop}
            read -p "Activer le debugging GDB [${enable_gdb}]: " enable_gdb
            enable_gdb=${enable_gdb:-$enable_gdb}
            ;;
        11)
            # Tout modifier - recr'eer la VM
            log_info "Recr'eation compl`ete de la VM..."
            delete_vm "$vm_name" || return 1
            create_vm || return 1
            return 0
            ;;
        12)
            # Terminer - sauvegarder les modifications
            ;;
        *)
            log_error "Choix invalide"
            ;;
    esac

    # Sauvegarder les modifications
    cat > "$vm_config" << EOF
# Configuration de la VM: $vm_name
# Date: $(date)

# Architecture
arch=$architecture
machine=$machine
cpu_type=$cpu_type

# Ressources
ram=$ram
cpu=$cpu

# Stockage
disk=$disk
iso=${iso:-}

# R'eseau
network_mode=$network_mode

# Affichage
display=$display
num_screens=$num_screens

# Options avanc'ees
enable_clipboard=$enable_clipboard
enable_dragdrop=$enable_dragdrop
enable_gdb=$enable_gdb

# Boot
boot_order=$boot_order

# Partages
share_dir=$SHARE_DIR
EOF

    log_info "Configuration de la VM $vm_name mise `a jour"
    
    # Valider la nouvelle configuration
    validate_vm_config "$vm_name" || {
        log_error "La nouvelle configuration n'est pas valide"
        return 1
    }
    
    return 0
}

# =============================================================================
# SUPPRIMER UNE VM
# =============================================================================

delete_vm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"

    if [ ! -d "$vm_dir" ]; then
        log_error "VM introuvable: $vm_name"
        return 1
    fi

    # V'erifier si la VM est en cours d'ex'ecution
    if [ -f "$vm_dir/pid" ]; then
        local pid=$(cat "$vm_dir/pid")
        if ps -p "$pid" &> /dev/null; then
            log_error "La VM $vm_name est en cours d'ex'ecution. Arr^etez-la d'abord."
            return 1
        fi
    fi

    read -p "Voulez-vous vraiment supprimer la VM $vm_name et tous ses fichiers? (y/N): " confirm
    if [ "$confirm" != "y" ]; then
        log_info "Suppression annul'ee"
        return 0
    fi

    log_info "Suppression de la VM $vm_name..."

    # Arr^eter la VM si n'ecessaire
    stop_vm "$vm_name" 2>/dev/null

    # Supprimer le dossier de la VM
    rm -rf "$vm_dir" || {
        log_error "'Echec de la suppression"
        return 1
    }

    log_info "VM $vm_name supprim'ee"
    return 0
}

# =============================================================================
# INS'ERER UN ISO DANS UNE VM
# =============================================================================

insert_iso() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"

    if [ ! -d "$vm_dir" ]; then
        log_error "VM introuvable: $vm_name"
        return 1
    fi

    if [ ! -f "$vm_config" ]; then
        log_error "Configuration de la VM introuvable: $vm_config"
        return 1
    fi

    # V'erifier si la VM est en cours d'ex'ecution
    if [ -f "$vm_dir/pid" ]; then
        local pid=$(cat "$vm_dir/pid")
        if ps -p "$pid" &> /dev/null; then
            log_error "Pour changer l'ISO, arr^etez d'abord la VM et modifiez sa configuration."
            log_info "Vous pouvez utiliser l'option 'Modifier une VM' pour changer l'ISO."
            return 1
        fi
    fi

    log_header "Insertion d'un ISO dans la VM: $vm_name"

    # Charger la configuration
    source "$vm_config" || {
        log_error "Impossible de charger la configuration"
        return 1
    }

    # S'electionner un ISO
    list_isos
    if [ -z "$selected_iso" ]; then
        log_error "Aucun ISO s'electionn'e"
        return 1
    fi

    # Mettre `a jour la configuration
    iso="$selected_iso"
    
    # Si c'est une VM UTM, mettre `a jour le fichier JSON aussi
    if [ "$arch" = "UTM" ]; then
        local utm_json_file="$vm_dir/${vm_name}.utm.json"
        if [ -f "$utm_json_file" ]; then
            # Mettre `a jour le JSON avec le nouvel ISO
            local iso_uuid=$(uuidgen 2>/dev/null || echo "$(date +%s)-$(openssl rand -hex 8)")
            
            # Sauvegarder l'ancien JSON
            cp "$utm_json_file" "$vm_dir/${vm_name}.utm.json.bak" || true
            
            # Cr'eer un nouveau JSON avec le nouvel ISO
            create_utm_config "$vm_name" "$vm_dir" "$utm_os_type" "$utm_architecture" "$ram" "$cpu" "$disk" "$iso" "$utm_display" "$utm_sharing" "$utm_sharing_path" "$utm_clipboard" "$utm_vnc" "$utm_vnc_port" "$utm_network_mode" "$utm_hardware_accel" || {
                # Restaurer si 'echec
                mv "$vm_dir/${vm_name}.utm.json.bak" "$utm_json_file" 2>/dev/null || true
                return 1
            }
            rm -f "$vm_dir/${vm_name}.utm.json.bak"
        fi
    fi

    # Sauvegarder les modifications
    sed -i '' "s|^iso=.*|iso=$iso|" "$vm_config"
    
    log_info "ISO ins'er'e: $iso"
    return 0
}

# =============================================================================
# 'EJECTER L'ISO D'UNE VM
# =============================================================================

eject_iso() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"

    if [ ! -d "$vm_dir" ]; then
        log_error "VM introuvable: $vm_name"
        return 1
    fi

    if [ ! -f "$vm_config" ]; then
        log_error "Configuration de la VM introuvable: $vm_config"
        return 1
    fi

    # V'erifier si la VM est en cours d'ex'ecution
    if [ -f "$vm_dir/pid" ]; then
        local pid=$(cat "$vm_dir/pid")
        if ps -p "$pid" &> /dev/null; then
            log_error "Pour 'ejecter l'ISO, arr^etez d'abord la VM et modifiez sa configuration."
            return 1
        fi
    fi

    log_header "'Ejection de l'ISO de la VM: $vm_name"

    # Mettre `a jour la configuration
    sed -i '' "s|^iso=.*|iso=|" "$vm_config"
    
    # Si c'est une VM UTM, recr'eer le JSON sans ISO
    local arch=$(grep -E "^arch=" "$vm_config" 2>/dev/null | cut -d= -f2)
    if [ "$arch" = "UTM" ]; then
        # Charger les param`etres UTM depuis la config
        local utm_os_type=$(grep -E "^utm_os_type=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local utm_architecture=$(grep -E "^utm_architecture=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local utm_display=$(grep -E "^utm_display=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local utm_sharing=$(grep -E "^utm_sharing=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local utm_sharing_path=$(grep -E "^utm_sharing_path=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local utm_clipboard=$(grep -E "^utm_clipboard=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local utm_vnc=$(grep -E "^utm_vnc=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local utm_vnc_port=$(grep -E "^utm_vnc_port=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local utm_network_mode=$(grep -E "^utm_network_mode=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local utm_hardware_accel=$(grep -E "^utm_hardware_accel=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local disk=$(grep -E "^disk=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local ram=$(grep -E "^ram=" "$vm_config" 2>/dev/null | cut -d= -f2)
        local cpu=$(grep -E "^cpu=" "$vm_config" 2>/dev/null | cut -d= -f2)
        
        local utm_json_file="$vm_dir/${vm_name}.utm.json"
        if [ -f "$utm_json_file" ]; then
            create_utm_config "$vm_name" "$vm_dir" "$utm_os_type" "$utm_architecture" "$ram" "$cpu" "$disk" "" "$utm_display" "$utm_sharing" "$utm_sharing_path" "$utm_clipboard" "$utm_vnc" "$utm_vnc_port" "$utm_network_mode" "$utm_hardware_accel" || {
                return 1
            }
        fi
    fi

    log_info "ISO 'eject'e de la VM $vm_name"
    return 0
}

# =============================================================================
# EXPORTER UNE VM VERS UTM
# =============================================================================

export_utm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"

    if [ ! -d "$vm_dir" ]; then
        log_error "VM introuvable: $vm_name"
        return 1
    fi

    if [ ! -f "$vm_config" ]; then
        log_error "Configuration de la VM introuvable: $vm_config"
        return 1
    fi

    # V'erifier si UTM est install'e
    detect_utm
    if [ "$UTM_INSTALLED" != true ]; then
        log_error "UTM.app est requis pour exporter une VM"
        log_info "Installez UTM depuis: https://mac.getutm.app/"
        return 1
    fi

    # Charger la configuration
    source "$vm_config" || {
        log_error "Impossible de charger la configuration"
        return 1
    }

    log_header "Export de la VM $vm_name vers UTM"

    if [ "$arch" = "UTM" ]; then
        log_info "Cette VM est d'ej`a une VM UTM"
        local utm_json_file="$vm_dir/${vm_name}.utm.json"
        if [ -f "$utm_json_file" ]; then
            log_info "Fichier UTM JSON: $utm_json_file"
            log_info "Pour importer dans UTM:"
            log_info "  1. Ouvrir UTM.app"
            log_info "  2. Cliquer sur 'Create VM'"
            log_info "  3. S'electionner 'Import Existing Virtual Machine'"
            log_info "  4. Choisir le fichier: $utm_json_file"
        fi
        return 0
    fi

    # Convertir la VM QEMU en configuration UTM
    log_info "Conversion de la VM QEMU en configuration UTM..."

    # D'eterminer le type de syst`eme UTM
    local utm_os_type="linux"
    case $arch in
        "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
            utm_os_type="macOS9"
            ;;
        "i86"|"i386")
            utm_os_type="dos"
            ;;
        "X86_64")
            utm_os_type="linux"
            ;;
        "arm"|"arm64")
            utm_os_type="linux"
            ;;
    esac

    # D'eterminer l'architecture UTM
    local utm_architecture="x86_64"
    case $arch in
        "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
            utm_architecture="ppc"
            ;;
        "i86"|"i386")
            utm_architecture="x86_64"
            ;;
        "X86_64")
            utm_architecture="x86_64"
            ;;
        "arm")
            utm_architecture="arm64"
            ;;
        "arm64")
            utm_architecture="arm64"
            ;;
    esac

    # Cr'eer la configuration UTM
    create_utm_config "${vm_name}_utm" "$vm_dir" "$utm_os_type" "$utm_architecture" "$ram" "$cpu" "$disk" "${iso:-}" "cocoa" "y" "$SHARE_DIR" "y" "n" "5900" "shared" "false" || {
        return 1
    }

    log_info "VM $vm_name export'ee vers UTM"
    log_info "Fichier UTM JSON: $vm_dir/${vm_name}_utm.utm.json"
    log_info "Pour importer dans UTM:"
    log_info "  1. Ouvrir UTM.app"
    log_info "  2. Cliquer sur 'Create VM'"
    log_info "  3. S'electionner 'Import Existing Virtual Machine'"
    log_info "  4. Choisir le fichier: $vm_dir/${vm_name}_utm.utm.json"

    return 0
}

# =============================================================================
# FONCTION PRINCIPALE POUR LE MENU VM
# =============================================================================

process_vm_menu() {
    while true; do
        show_vm_menu
        read -p "Votre choix: " vm_menu_choice
        
        case "$vm_menu_choice" in
            1)
                # Lister les VMs
                list_vms
                ;;
            2)
                # Cr'eer une nouvelle VM
                create_vm
                ;;
            3)
                # D'emarrer une VM
                list_vms
                if [ -n "$selected_vm" ]; then
                    start_vm "$selected_vm"
                else
                    read -p "Nom de la VM `a d'emarrer: " vm_name_to_start
                    if [ -n "$vm_name_to_start" ]; then
                        start_vm "$vm_name_to_start"
                    fi
                fi
                ;;
            4)
                # Arr^eter une VM
                list_vms
                if [ -n "$selected_vm" ]; then
                    stop_vm "$selected_vm"
                else
                    read -p "Nom de la VM `a arr^eter: " vm_name_to_stop
                    if [ -n "$vm_name_to_stop" ]; then
                        stop_vm "$vm_name_to_stop"
                    fi
                fi
                ;;
            5)
                # Modifier une VM
                list_vms
                if [ -n "$selected_vm" ]; then
                    edit_vm "$selected_vm"
                else
                    read -p "Nom de la VM `a modifier: " vm_name_to_edit
                    if [ -n "$vm_name_to_edit" ]; then
                        edit_vm "$vm_name_to_edit"
                    fi
                fi
                ;;
            6)
                # Supprimer une VM
                list_vms
                if [ -n "$selected_vm" ]; then
                    delete_vm "$selected_vm"
                else
                    read -p "Nom de la VM `a supprimer: " vm_name_to_delete
                    if [ -n "$vm_name_to_delete" ]; then
                        delete_vm "$vm_name_to_delete"
                    fi
                fi
                ;;
            7)
                # Ins'erer un ISO dans une VM
                list_vms
                if [ -n "$selected_vm" ]; then
                    insert_iso "$selected_vm"
                else
                    read -p "Nom de la VM: " vm_name_for_iso
                    if [ -n "$vm_name_for_iso" ]; then
                        insert_iso "$vm_name_for_iso"
                    fi
                fi
                ;;
            8)
                # 'Ejecter l'ISO d'une VM
                list_vms
                if [ -n "$selected_vm" ]; then
                    eject_iso "$selected_vm"
                else
                    read -p "Nom de la VM: " vm_name_for_eject
                    if [ -n "$vm_name_for_eject" ]; then
                        eject_iso "$vm_name_for_eject"
                    fi
                fi
                ;;
            9)
                # Exporter une VM vers UTM
                list_vms
                if [ -n "$selected_vm" ]; then
                    export_utm "$selected_vm"
                else
                    read -p "Nom de la VM `a exporter: " vm_name_to_export
                    if [ -n "$vm_name_to_export" ]; then
                        export_utm "$vm_name_to_export"
                    fi
                fi
                ;;
            10)
                # Retour
                return 0
                ;;
            *)
                log_error "Choix invalide"
                ;;
        esac
        
        read -p "Appuyez sur Entrer pour continuer..." dummy
    done
}

# =============================================================================
# FONCTIONS DE DEBUG ET TEST
# =============================================================================

# Affiche la commande QEMU qui serait g'en'er'ee (pour d'ebogage)
show_qemu_command() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"

    if [ ! -d "$vm_dir" ]; then
        log_error "VM introuvable: $vm_name"
        return 1
    fi

    if [ ! -f "$vm_config" ]; then
        log_error "Configuration de la VM introuvable: $vm_config"
        return 1
    fi

    log_header "Commande QEMU pour la VM: $vm_name"

    # Charger la configuration
    source "$vm_config" || {
        log_error "Impossible de charger la configuration"
        return 1
    }

    # D'eterminer le binaire QEMU
    local qemu_cmd=$(get_qemu_bin "$arch")
    if [ -z "$qemu_cmd" ]; then
        qemu_cmd="qemu-system-$arch"
    fi

    if ! command -v "$qemu_cmd" &> /dev/null; then
        log_error "Commande QEMU introuvable: $qemu_cmd"
        return 1
    fi

    # D'etecter le chemin BIOS pour PowerPC
    local bios_path=""
    case $arch in
        "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
            local bios_dirs=(
                "/Users/xenon/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu"
                "/usr/local/share/qemu"
                "/usr/share/qemu"
                "/opt/local/share/qemu"
            )
            for dir in "${bios_dirs[@]}"; do
                if [ -f "$dir/openbios-ppc" ]; then
                    bios_path="$dir"
                    break
                fi
            done
            ;;
    esac

    # Construction de la commande QEMU (m^eme logique que start_qemu_vm mais affiche seulement)
    local qemu_args=()

    # BIOS path pour PowerPC
    if [ -n "$bios_path" ]; then
        qemu_args+=("-L" "$bios_path")
    fi

    # RAM
    qemu_args+=("-m" "${ram}M")

    # CPU
    qemu_args+=("-smp" "$cpu")

    # Machine et CPU - pour PowerPC, ces options seront ajout'ees dans la section sp'ecifique
    local is_ppc=false
    case $arch in
        "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
            is_ppc=true
            ;;
    esac

    if [ "$is_ppc" = false ]; then
        # Machine
        if [ -n "$machine" ]; then
            qemu_args+=("-machine" "$machine")
        fi

        # Type de CPU
        if [ -n "$cpu_type" ]; then
            qemu_args+=("-cpu" "$cpu_type")
        fi
    fi

    # Boot order et stockage - m'ethode d'epend de l'architecture

    if [ "$is_ppc" = false ]; then
        # M'ethode standard pour non-PPC
        if [ -n "$boot_order" ]; then
            qemu_args+=("-boot" "$boot_order")
        fi

        # Disque dur
        if [ -n "$disk" ] && [ -f "$disk" ]; then
            local disk_if="virtio"
            case $arch in
                "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
                    disk_if="ide"
                    ;;
            esac
            qemu_args+=("-drive" "file=$disk,format=qcow2,if=$disk_if")
        fi

        # ISO
        if [ -n "$iso" ] && [ -f "$iso" ]; then
            qemu_args+=("-cdrom" "$iso")
        fi
    fi

    # Configuration r'eseau
    case $network_mode in
        "nat"|"user")
            case $arch in
                "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
                    local mac_addr=$(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/:$//')
                    qemu_args+=("-device" "sungem,mac=$mac_addr,netdev=net0")
                    qemu_args+=("-netdev" "vmnet-shared,id=net0")
                    ;;
                *)
                    qemu_args+=("-netdev" "user,id=mynet0,net=192.168.100.0/24,dhcpstart=192.168.100.100")
                    qemu_args+=("-device" "virtio-net-pci,netdev=mynet0")
                    ;;
            esac
            ;;
    esac

    # Configuration d'affichage
    local spice_supported=true
    case $arch in
        "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
            if ! $qemu_cmd -help 2>&1 | grep -q "spice"; then
                spice_supported=false
            fi
            ;;
    esac

    case $display in
        "x11")
            qemu_args+=("-display" "x11")
            ;;
        "spice")
            if [ "$spice_supported" = false ]; then
                qemu_args+=("-display" "cocoa")
                qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
                if [ "$num_screens" -gt 1 ]; then
                    for (( i=1; i<num_screens; i++ )); do
                        qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
                    done
                fi
            else
                local spice_port=$((SPICE_PORT + $(echo "$vm_name" | tr -cd '0-9') % 100))
                qemu_args+=("-spice" "port=$spice_port,addr=127.0.0.1,disable-ticketing=on")
                qemu_args+=("-device" "virtio-serial-pci")
                qemu_args+=("-device" "virtserialport,chardev=spicechannel0,name=com.redhat.spice.0")
                qemu_args+=("-chardev" "spicevmc,id=spicechannel0,name=vdagent")
                for (( i=0; i<num_screens; i++ )); do
                    qemu_args+=("-device" "qxl-vga,id=video$i")
                done
            fi
            ;;
        "sdl")
            qemu_args+=("-display" "sdl")
            ;;
        "cocoa")
            qemu_args+=("-display" "cocoa")
            ;;
        "vnc")
            local vnc_port=$((VNC_BASE_PORT + $(echo "$vm_name" | tr -cd '0-9') % 100))
            qemu_args+=("-vnc" "127.0.0.1:$vnc_port")
            ;;
        "none")
            qemu_args+=("-nographic")
            ;;
    esac

    # Partage de fichiers (9p)
    if [ -d "$share_dir" ]; then
        qemu_args+=("-fsdev" "local,security_model=mapped,id=fsdev0,path=$share_dir")
        local fsdev_device="virtio-9p-pci"
        case $arch in
            "68k"|"68040"|"apollocore"|"G4"|"601"|"604ev"|"ppc")
                # PPC ne supporte pas virtio-9p-pci
                ;;
            *)
                qemu_args+=("-device" "$fsdev_device,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare")
                ;;
        esac
    fi

    # Debugging GDB
    if [ "$enable_gdb" = "y" ]; then
        qemu_args+=("-gdb" "tcp::${GDB_PORT}")
        qemu_args+=("-S")
    fi

    # Options sp'ecifiques pour PowerPC
    case $arch in
        "G4"|"604ev"|"ppc")
            local ppc_machine="${machine:-mac99}"
            if [ "$arch" = "604ev" ] || [ "$arch" = "ppc" ]; then
                ppc_machine="g3beige"
            fi
            local via_type="${via:-cuda}"
            qemu_args+=("-machine" "${ppc_machine},via=${via_type}")
            qemu_args+=("-cpu" "${cpu_type:-750}")
            qemu_args+=("-accel" "tcg,tb-size=128")
            
            # Multi-screen methods for PowerPC/Mac OS 9
            # Supported methods: dual-pci-vga, graphic-engine, auto
            local multi_screen_method="${multi_screen_method:-auto}"
            
            if [ "$num_screens" -gt 1 ]; then
                case "$multi_screen_method" in
                    "graphic-engine")
                        # Method graphic-drawing-engine (requires QEMU with qfb patches)
                        qemu_args+=("-device" "graphic-drawing-engine,heads=${num_screens}")
                        log_info "Multi-'ecran: m'ethode graphic-drawing-engine (heads=${num_screens})"
                        ;;
                    "dual-pci-vga")
                        # M'ethode Dual-PCI VGA Device Hack
                        qemu_args+=("-prom-env" "vga-ndrv?=true")
                        qemu_args+=("-g" "1024x768x32")
                        qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video0,xres=1024,yres=768")
                        for (( screen_num=1; screen_num<num_screens; screen_num++ )); do
                            local screen_id="video$screen_num"
                            qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=$screen_id,xres=1024,yres=768")
                        done
                        log_info "Multi-ecran: methode Dual-PCI VGA (${num_screens} ecrans)"
                        ;;
                    "auto"|""")
                        # Auto-d'etection: essayer graphic-engine d'abord, sinon dual-pci-vga
                        if qemu_device_exists "graphic-drawing-engine"; then
                            qemu_args+=("-device" "graphic-drawing-engine,heads=${num_screens}")
                            log_info "Multi-ecran: methode graphic-drawing-engine detectee (heads=${num_screens})"
                        else
                            qemu_args+=("-prom-env" "vga-ndrv?=true")
                            qemu_args+=("-g" "1024x768x32")
                            qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video0,xres=1024,yres=768")
                            for (( screen_num=1; screen_num<num_screens; screen_num++ )); do
                                local screen_id="video$screen_num"
                                qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=$screen_id,xres=1024,yres=768")
                            done
                            log_info "Multi-ecran: methode Dual-PCI VGA (graphic-drawing-engine not available)"
                        fi
                        ;;
                esac
            else
                # Pour 1 'ecran, utiliser seulement le device VGA
                qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
            fi

            # M'ethode UTM pour PowerPC : utiliser bootindex au lieu de -boot/-cdrom
            # CDROM boot en premier (bootindex=0), HDD en second (bootindex=1)
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "if=none,media=disk,id=drive0,file=$disk,format=qcow2")
                qemu_args+=("-device" "ide-hd,bus=ide.0,unit=0,drive=drive0,bootindex=1")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-drive" "if=none,media=cdrom,id=drive1,file=$iso,readonly=on")
                qemu_args+=("-device" "ide-cd,bus=ide.0,unit=1,drive=drive1,bootindex=0")
            fi

            # Son pour PowerPC (es1370 pour mac99, comme dans UTM)
            if [ "$sound" = "screamer" ] || [ "$sound" = "es1370" ]; then
                qemu_args+=("-audiodev" "coreaudio,id=sound0")
                qemu_args+=("-device" "es1370,id=sound0")
            fi

            # Utiliser boot-command pour Mac OS (plus fiable que auto-boot)
            qemu_args+=("-prom-env" "boot-args=-v")
            qemu_args+=("-prom-env" "vga-ndrv?=true")
            qemu_args+=("-prom-env" "boot-command=init-program go")

            # Ajouter le loader NDRV si trouv'e
            local ndrv_loader=""
            local ndrv_paths=(
                "/usr/local/share/qemu/ppc-ndrvloader"
                "/usr/share/qemu/ppc-ndrvloader"
                "/opt/local/share/qemu/ppc-ndrvloader"
                "$HOME/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu/ppc-ndrvloader"
                "/Library/Application Support/UTM/qemu/ppc-ndrvloader"
            )
            for path in "${ndrv_paths[@]}"; do
                if [ -f "$path" ]; then
                    ndrv_loader="$path"
                    break
                fi
            done
            if [ -n "$ndrv_loader" ] && [ -f "$ndrv_loader" ]; then
                qemu_args+=("-device" "loader,addr=0x4000000,file=$ndrv_loader")
            fi
            ;;
        "601")
            qemu_args+=("-machine" "g3beige")
            qemu_args+=("-cpu" "${cpu_type:-601}")
            qemu_args+=("-accel" "tcg")
            # Utiliser -vga none + device VGA comme dans la config UTM qui fonctionne
            qemu_args+=("-vga" "none")
            qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
            # M'ethode UTM pour PowerPC
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "if=none,media=disk,id=drive0,file=$disk,format=qcow2")
                qemu_args+=("-device" "ide-hd,bus=ide.0,unit=0,drive=drive0,bootindex=0")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-drive" "if=none,media=cdrom,id=drive1,file=$iso,readonly=on")
                qemu_args+=("-device" "ide-cd,bus=ide.0,unit=1,drive=drive1,bootindex=1")
            fi
            qemu_args+=("-prom-env" "boot-command=init-program go")
            ;;
        "apollocore")
            qemu_args+=("-machine" "q800")
            qemu_args+=("-cpu" "${cpu_type:-68080}")
            qemu_args+=("-accel" "tcg")
            # Utiliser -vga none + device VGA comme dans la config UTM qui fonctionne
            qemu_args+=("-vga" "none")
            qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
            # M'ethode UTM pour PowerPC
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "if=none,media=disk,id=drive0,file=$disk,format=qcow2")
                qemu_args+=("-device" "ide-hd,bus=ide.0,unit=0,drive=drive0,bootindex=0")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-drive" "if=none,media=cdrom,id=drive1,file=$iso,readonly=on")
                qemu_args+=("-device" "ide-cd,bus=ide.0,unit=1,drive=drive1,bootindex=1")
            fi
            qemu_args+=("-prom-env" "boot-command=init-program go")
            ;;
        "68k"|"68040")
            qemu_args+=("-accel" "tcg")
            # 68k ne supporte pas -vga std, utiliser m'ethode standard
            if [ -n "$boot_order" ]; then
                qemu_args+=("-boot" "$boot_order")
            else
                qemu_args+=("-boot" "c")
            fi
            # Disques avec if=ide pour 68k (m'ethode standard)
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-hda" "$disk")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-cdrom" "$iso")
            fi
            ;;
        "i86"|"i386")
            qemu_args+=("-accel" "tcg")
            ;;
        "X86_64")
            qemu_args+=("-accel" "tcg")
            qemu_args+=("-enable-kvm")
            qemu_args+=("-cpu" "host,migratable=off")
            ;;
        "arm"|"arm64"|"sparc"|"sparc64")
            qemu_args+=("-accel" "tcg")
            ;;
    esac

    # Afficher la commande
    echo ""
    echo "Commande QEMU compl`ete :"
    echo "================================================================"
    echo "$qemu_cmd ${qemu_args[*]}"
    echo "================================================================"
    echo ""
    
    # Afficher aussi en format lisible (un argument par ligne)
    echo "Format d'etaill'e (pour copier/coller) :"
    echo "----------------------------------------------------------------"
    echo "$qemu_cmd \\"
    for arg in "${qemu_args[@]}"; do
        echo "  $arg \\"
    done
    echo ""
    
    return 0
}

# Cr'eer une VM de test rapidement avec un ISO existant
# Usage: create_test_vm [vm_name] [arch] [ram_MB] [cpu_count] [disk_size] [iso_path]
create_test_vm() {
    local vm_name=""
    local arch="G4"
    local ram="2048"
    local cpu="1"
    local disk_size="10G"
    local iso_path=""
    
    # Analyser les arguments
    # Si 1 argument : vm_name
    # Si 2+ arguments : vm_name, arch, ram, cpu, disk_size, [iso_path]
    if [ $# -ge 1 ]; then
        vm_name="$1"
    else
        vm_name="test_vm_$(date +%Y%m%d_%H%M%S)"
    fi
    
    if [ $# -ge 2 ]; then
        arch="$2"
    fi
    
    if [ $# -ge 3 ]; then
        ram="$3"
    fi
    
    if [ $# -ge 4 ]; then
        cpu="$4"
    fi
    
    if [ $# -ge 5 ]; then
        disk_size="$5"
    fi
    
    if [ $# -ge 6 ]; then
        iso_path="$6"
    fi

    log_header "Cr'eation rapide d'une VM de test: $vm_name (Arch: $arch, RAM: ${ram}MB, CPU: $cpu, Disque: $disk_size)"

    ensure_dir "$VM_DIR"
    
    if [ -d "$VM_DIR/$vm_name" ]; then
        log_error "La VM $vm_name existe d'ej`a"
        return 1
    fi

    # Si aucun ISO sp'ecifi'e, essayer de trouver un ISO Mac OS 9
    if [ -z "$iso_path" ]; then
        # Chercher un ISO Mac OS 9 dans les r'epertoires connus
        local iso_dirs=(
            "$ISO_DIR"
            "$SHARE_DIR"
            "$HOME/Downloads"
            "$SCRIPT_DIR"
        )
        
        for dir in "${iso_dirs[@]}"; do
            if [ -d "$dir" ]; then
                # Chercher un ISO Mac OS 9
                local iso_candidates=(
                    "$dir/Mac_OS_9.2.2_Universal_Install.iso"
                    "$dir/Mac_OS_9.2.2_Unsupported_G4s.iso"
                    "$dir/MacOSX.4.iso"
                    "$dir/MAC_OS_7-6-1_RETAIL.ISO"
                )
                
                for candidate in "${iso_candidates[@]}"; do
                    if [ -f "$candidate" ]; then
                        iso_path="$candidate"
                        log_info "ISO trouv'e: $iso_path"
                        break
                    fi
                done
                
                if [ -n "$iso_path" ]; then
                    break
                fi
                
                # Sinon, prendre le premier ISO trouv'e
                local first_iso=$(find "$dir" -maxdepth 3 -type f \( -iname "*.iso" -o -iname "*.ISO" \) -print -q 2>/dev/null | head -1)
                if [ -n "$first_iso" ]; then
                    iso_path="$first_iso"
                    log_info "Premier ISO trouv'e: $iso_path"
                    break
                fi
            fi
        done
    fi

    if [ -z "$iso_path" ]; then
        log_warn "Aucun ISO trouv'e, la VM d'emarrera sans ISO (boot depuis disque)"
        iso_path=""
    fi

    # Cr'eer le disque
    local disk_path="$DISK_DIR/${vm_name}.qcow2"
    log_info "Cr'eation du disque: $disk_path ($disk_size)"
    qemu-img create -f qcow2 "$disk_path" "$disk_size" 2>/dev/null || {
        log_error "'Echec de la cr'eation du disque"
        return 1
    }

    # Cr'eer le dossier de la VM
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"
    mkdir -p "$vm_dir"

    # D'eterminer les param`etres par d'efaut pour l'architecture
    local default_params=$(get_default_params "$arch")
    local default_machine=$(echo "$default_params" | awk '{print $4}')
    local default_cpu_type=$(echo "$default_params" | awk '{print $5}')

    # 'Ecrire la configuration
    cat > "$vm_config" << EOF
# Configuration de la VM: $vm_name
# Date: $(date)
# Cr'e'ee automatiquement par create_test_vm

# Architecture
arch=$arch
machine=$default_machine
cpu_type=$default_cpu_type

# Ressources
ram=$ram
cpu=$cpu

# Stockage
disk=$disk_path
iso=$iso_path

# R'eseau
network_mode=nat

# Affichage
display=cocoa
num_screens=1

# Options avanc'ees
enable_clipboard=n
enable_dragdrop=n
enable_gdb=n

# Boot
boot_order=dc

# Partages
share_dir=$SHARE_DIR
EOF

    log_info "VM de test $vm_name cr'e'ee!"
    log_info "Configuration: $vm_config"
    
    # Afficher la commande QEMU
    echo ""
    show_qemu_command "$vm_name"
    
    return 0
}

# =============================================================================
# MENU VM (pour l'utilisation standalone)
# =============================================================================

show_vm_menu() {
    clear
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${PURPLE}                    Gestion des Machines Virtuelles${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo ""
    echo "  [1]  Lister les VMs existantes"
    echo "  [2]  Cr'eer une nouvelle VM"
    echo "  [3]  D'emarrer une VM"
    echo "  [4]  Arr^eter une VM"
    echo "  [5]  Modifier une VM"
    echo "  [6]  Supprimer une VM"
    echo "  [7]  Ins'erer un ISO dans une VM"
    echo "  [8]  'Ejecter l'ISO d'une VM"
    echo "  [9]  Exporter une VM vers UTM"
    echo "  [10] Retour"
    echo ""
}

# =============================================================================
# SECTION PRINCIPALE - TRAITEMENT DES ARGUMENTS
# =============================================================================

# V'erifier si ce script est appel'e directement ou sourc'e
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script appel'e directement
    if [ $# -gt 0 ]; then
        # Mode appel avec arguments
        case "$1" in
            list)
                list_vms
                ;;
            create)
                create_vm
                ;;
            start)
                if [ -n "$2" ]; then
                    start_vm "$2"
                else
                    list_vms
                    if [ -n "$selected_vm" ]; then
                        start_vm "$selected_vm"
                    fi
                fi
                ;;
            stop)
                if [ -n "$2" ]; then
                    stop_vm "$2"
                else
                    list_vms
                    if [ -n "$selected_vm" ]; then
                        stop_vm "$selected_vm"
                    fi
                fi
                ;;
            edit)
                if [ -n "$2" ]; then
                    edit_vm "$2"
                else
                    list_vms
                    if [ -n "$selected_vm" ]; then
                        edit_vm "$selected_vm"
                    fi
                fi
                ;;
            delete)
                if [ -n "$2" ]; then
                    delete_vm "$2"
                else
                    list_vms
                    if [ -n "$selected_vm" ]; then
                        delete_vm "$selected_vm"
                    fi
                fi
                ;;
            insert-iso)
                if [ -n "$2" ]; then
                    insert_iso "$2"
                else
                    list_vms
                    if [ -n "$selected_vm" ]; then
                        insert_iso "$selected_vm"
                    fi
                fi
                ;;
            eject-iso)
                if [ -n "$2" ]; then
                    eject_iso "$2"
                else
                    list_vms
                    if [ -n "$selected_vm" ]; then
                        eject_iso "$selected_vm"
                    fi
                fi
                ;;
            export-utm)
                if [ -n "$2" ]; then
                    export_utm "$2"
                else
                    list_vms
                    if [ -n "$selected_vm" ]; then
                        export_utm "$selected_vm"
                    fi
                fi
                ;;
            disks|list-disks)
                list_disks
                ;;
            create-disk)
                create_disk
                ;;
            isos|list-isos)
                list_isos
                ;;
            download-iso)
                download_iso
                ;;
            show-qemu|show-command)
                if [ -n "$2" ]; then
                    show_qemu_command "$2"
                else
                    list_vms
                    if [ -n "$selected_vm" ]; then
                        show_qemu_command "$selected_vm"
                    else
                        read -p "Nom de la VM: " vm_name_for_command
                        if [ -n "$vm_name_for_command" ]; then
                            show_qemu_command "$vm_name_for_command"
                        fi
                    fi
                fi
                ;;
            create-test-vm|create-test)
                shift
                create_test_vm "$@"
                ;;
            menu)
                process_vm_menu
                ;;
            *)
                echo "Usage: $0 {list|create|start|stop|edit|delete|insert-iso|eject-iso|export-utm|disks|create-disk|isos|download-iso|show-qemu|create-test-vm|menu}"
                echo ""
                echo "Ou Lancez sans arguments pour le menu interactif"
                process_vm_menu
                ;;
        esac
    else
        # Mode menu interactif par d'efaut
        process_vm_menu
    fi
fi
