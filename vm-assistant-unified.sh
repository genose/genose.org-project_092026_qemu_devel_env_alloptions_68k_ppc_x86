#!/usr/bin/env bash
# =============================================================================
# vm-assistant-unified.sh — UNIFIED VM Assistant for QEMU/UTM
# 
# Combines the best of:
#   - vm_assist.sh (Copilot): Professional QEMU build integration, retro focus
#   - vm-assistant-vm.sh: 14 architectures, ISO management, UTM export
#
# Supported platforms:
#   • Apple MacOS 7.1 – 9.2.2  (m68k + PPC Old World / New World)
#   • Atari ST / STE / TT / Falcon  (m68k)
#   • Commodore Amiga  (m68k)
#   • HaikuOS  (i386 / x86_64)
#   • Solaris family  (x86 + SPARC)
#   • Windows XP  (i386)
#   • OpenStep  (i386)
#   • PLUS: apollocore (68080), arm, arm64
#
# Features:
#   ✓ Custom QEMU build with patches
#   ✓ 14 architectures support
#   ✓ ISO insert/eject
#   ✓ UTM export
#   ✓ Multi-screen support
#   ✓ GDB debugging
#   ✓ Network sharing (Samba/Netatalk)
#   ✓ RAMDISK support (/tmp/volatile_hd)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — override with environment variables
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VM_CONFIG_DIR="${SCRIPT_DIR}/vm-configs"
QEMU_PREFIX="${QEMU_PREFIX:-${HOME}/.local/qemu-retro}"
QEMU_BIN_DIR="${QEMU_BIN_DIR:-${QEMU_PREFIX}/bin}"
VM_IMAGE_DIR="${VM_IMAGE_DIR:-${HOME}/vm-images}"
VM_SHARED_DIR="${VM_SHARED_DIR:-${HOME}/vm-shared}"
DEFAULT_RAM_MB="${DEFAULT_RAM_MB:-256}"
DEFAULT_DISPLAY="${DEFAULT_DISPLAY:-sdl}"

# VM Assistant specific
CONFIG_DIR="${HOME}/.vm-assistant"
VM_DIR="${CONFIG_DIR}/vms"
DISK_DIR="${CONFIG_DIR}/disks"
ISO_DIR="${CONFIG_DIR}/isos"
SHARE_DIR="/tmp/volatile_hd"
ROM_DIR="/tmp/volatile_hd/MacROMan/TestImages"

# Default ports
DEFAULT_GDB_PORT=1234
DEFAULT_SSH_PORT=2222
DEFAULT_NETATALK_PORT=548

# Patches directory
PATCHES_DIR="${PATCHES_DIR:-${SCRIPT_DIR}/patches}"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_MAGENTA='\033[1;35m'
C_BLUE='\033[0;34m'

log()     { printf "${C_GREEN}[vm_assistant]${C_RESET} %s\n" "$*"; }
warn()    { printf "${C_YELLOW}[vm_assistant] WARN:${C_RESET} %s\n" "$*" >&2; }
die()     { printf "${C_RED}[vm_assistant] ERROR:${C_RESET} %s\n" "$*" >&2; exit 1; }
heading() { printf "\n${C_CYAN}${C_BOLD}=== %s ===${C_RESET}\n\n" "$*"; }

# ---------------------------------------------------------------------------
# Resolve QEMU binary (checks custom build first, then system)
# ---------------------------------------------------------------------------
qemu_bin() {
    local name="$1"
    local candidates=("${QEMU_BIN_DIR}/${name}" "$(command -v "${name}" 2>/dev/null || true)")
    for c in "${candidates[@]}"; do
        if [[ -x "${c}" ]]; then
            echo "${c}"
            return 0
        fi
    done
    die "Cannot find '${name}'. Build QEMU first with build_qemu.sh or set QEMU_BIN_DIR."
}

qemu_img_bin() {
    qemu_bin "qemu-img"
}

# ---------------------------------------------------------------------------
# Detect UTM
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Detect dependencies
# ---------------------------------------------------------------------------
detect_dependencies() {
    # Detection de UTM
    detect_utm

    # Detection de XQuartz
    if [ -d "/Applications/Utilities/XQuartz.app" ]; then
        XQUARTZ_INSTALLED=true
    else
        XQUARTZ_INSTALLED=false
    fi

    # Detection de MacPorts
    if command -v port &>/dev/null; then
        MACPORTS_INSTALLED=true
    else
        MACPORTS_INSTALLED=false
    fi

    # Detection de Homebrew
    if command -v brew &>/dev/null; then
        HOMEBREW_INSTALLED=true
    else
        HOMEBREW_INSTALLED=false
    fi

    # Detection des binaires QEMU
    QEMU_ARCHS=()
    for arch in ppc x86_64 m68k arm sparc aarch64 i386 ppc64 sparc64; do
        if command -v "qemu-system-${arch}" &>/dev/null; then
            QEMU_ARCHS+=("${arch}")
        fi
    done
}

# ---------------------------------------------------------------------------
# Utility: ask for a value with a default
# ---------------------------------------------------------------------------
ask() {
    local prompt="$1" default="$2" answer
    read -rp "$(printf "${C_BOLD}${prompt}${C_RESET} [${default}]: ")" answer
    echo "${answer:-${default}}"
}

ask_ram_size() {
    local prompt="$1" default="$2" answer
    while true; do
        answer=$(ask "${prompt}" "${default}")
        if [[ "${answer}" =~ ^[0-9]+([Mm]|[Gg])?$ ]]; then
            local numeric_part="${answer%[MmGg]}"
            local suffix="${answer:${#numeric_part}}"
            if (( numeric_part >= 1 )); then
                echo "${numeric_part}${suffix^^}"
                return 0
            fi
            warn "Invalid RAM size '${answer}'. The value must be at least 1 MiB."
        else
            warn "Invalid RAM size '${answer}'. Use a plain MiB value or an M/G suffix such as 512M, 2G, or 4G."
        fi
    done
}

# ---------------------------------------------------------------------------
# List available ISOs
# ---------------------------------------------------------------------------
list_isos() {
    local iso_dirs=("${ISO_DIR}" "/tmp/volatile_hd" "${SCRIPT_DIR}" "${HOME}/Downloads" "${HOME}/ISO")
    local global_available_isos_paths=()
    local index=1
    local selected_iso=""

    log "Scanning for ISO files..."

    for iso_dir in "${iso_dirs[@]}"; do
        if [[ -d "${iso_dir}" ]]; then
            while IFS= read -r -d '' file; do
                case "${file}" in
                    *.iso|*.ISO|*.img|*.IMG|*.qcow2|*.QCOW2)
                        # Check for duplicates
                        local already_found=false
                        for existing in "${global_available_isos_paths[@]}"; do
                            if [ "$existing" = "$file" ]; then
                                already_found=true
                                break
                            fi
                        done
                        if [ "$already_found" = false ]; then
                            global_available_isos_paths+=("$file")
                            echo "  [${index}] $(basename "$file")"
                            ((index++))
                        fi
                        ;;
                esac
            done < <(find "${iso_dir}" -type f \( -iname "*.iso" -o -iname "*.img" -o -iname "*.qcow2" \) -print0 2>/dev/null)
        fi
    done

    if [ ${#global_available_isos_paths[@]} -gt 0 ]; then
        read -rp "Select an ISO [1-${#global_available_isos_paths[@]}]: " selected_index
        if [[ "${selected_index}" =~ ^[0-9]+$ && ${selected_index} -le ${#global_available_isos_paths[@]} && ${selected_index} -gt 0 ]]; then
            selected_iso="${global_available_isos_paths[$((selected_index-1))]}"
            log "Selected ISO: ${selected_iso}"
        else
            log "No ISO selected."
            selected_iso=""
        fi
    else
        log "No ISO files found."
        selected_iso=""
    fi

    export selected_iso
}

# ---------------------------------------------------------------------------
# List available disks
# ---------------------------------------------------------------------------
list_disks() {
    local disk_dirs=("${DISK_DIR}" "/tmp/volatile_hd" "${SCRIPT_DIR}" "${HOME}/vm-images" "${HOME}/VirtualMachines")
    local global_available_disks_paths=()
    local index=1
    local selected_disk=""

    log "Scanning for disk files..."

    for disk_dir in "${disk_dirs[@]}"; do
        if [[ -d "${disk_dir}" ]]; then
            while IFS= read -r -d '' file; do
                case "${file}" in
                    *.qcow2|*.QCOW2|*.img|*.IMG|*.raw|*.RAW)
                        # Check for duplicates
                        local already_found=false
                        for existing in "${global_available_disks_paths[@]}"; do
                            if [ "$existing" = "$file" ]; then
                                already_found=true
                                break
                            fi
                        done
                        if [ "$already_found" = false ]; then
                            global_available_disks_paths+=("$file")
                            echo "  [${index}] $(basename "$file") ($(du -h "$file" | cut -f1))"
                            ((index++))
                        fi
                        ;;
                esac
            done < <(find "${disk_dir}" -type f \( -iname "*.qcow2" -o -iname "*.img" -o -iname "*.raw" \) -print0 2>/dev/null)
        fi
    done

    if [ ${#global_available_disks_paths[@]} -gt 0 ]; then
        read -rp "Select a disk [1-${#global_available_disks_paths[@]}]: " selected_index
        if [[ "${selected_index}" =~ ^[0-9]+$ && ${selected_index} -le ${#global_available_disks_paths[@]} && ${selected_index} -gt 0 ]]; then
            selected_disk="${global_available_disks_paths[$((selected_index-1))]}"
            log "Selected disk: ${selected_disk}"
        else
            log "No disk selected."
            selected_disk=""
        fi
    else
        log "No disk files found."
        selected_disk=""
    fi

    export selected_disk
}

# ---------------------------------------------------------------------------
# Create a new disk
# ---------------------------------------------------------------------------
create_disk() {
    local vm_name="$1"
    local disk_size="${2:-20G}"
    local disk_path="${DISK_DIR}/${vm_name}.qcow2"

    mkdir -p "${DISK_DIR}"
    
    if qemu_img_bin create -f qcow2 "${disk_path}" "${disk_size}" 2>/dev/null; then
        log "Disk created: ${disk_path}"
        selected_disk="${disk_path}"
        export selected_disk
        return 0
    else
        warn "Failed to create disk."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# List ROMs
# ---------------------------------------------------------------------------
list_roms() {
    local rom_dirs=("${ROM_DIR}" "${SCRIPT_DIR}/resources/roms/MacROMan" "/tmp/volatile_hd/MacROMan" "/tmp/volatile_hd/MacROMan/TestImages")
    local global_available_roms_paths=()
    local index=1
    local selected_rom=""

    log "Scanning for ROM files..."

    for rom_dir in "${rom_dirs[@]}"; do
        if [[ -d "${rom_dir}" ]]; then
            while IFS= read -r -d '' file; do
                case "${file}" in
                    *.rom|*.ROM|*.bin|*.BIN)
                        # Check for duplicates
                        local already_found=false
                        for existing in "${global_available_roms_paths[@]}"; do
                            if [ "$existing" = "$file" ]; then
                                already_found=true
                                break
                            fi
                        done
                        if [ "$already_found" = false ]; then
                            global_available_roms_paths+=("$file")
                            echo "  [${index}] $(basename "$file")"
                            ((index++))
                        fi
                        ;;
                esac
            done < <(find "${rom_dir}" -type f \( -iname "*.rom" -o -iname "*.bin" \) -print0 2>/dev/null)
        fi
    done

    if [ ${#global_available_roms_paths[@]} -gt 0 ]; then
        read -rp "Select a ROM [1-${#global_available_roms_paths[@]}]: " selected_index
        if [[ "${selected_index}" =~ ^[0-9]+$ && ${selected_index} -le ${#global_available_roms_paths[@]} && ${selected_index} -gt 0 ]]; then
            selected_rom="${global_available_roms_paths[$((selected_index-1))]}"
            log "Selected ROM: ${selected_rom}"
        else
            log "No ROM selected."
            selected_rom=""
        fi
    else
        log "No ROM files found."
        selected_rom=""
    fi

    export selected_rom
}

# ---------------------------------------------------------------------------
# Validate VM configuration
# ---------------------------------------------------------------------------
validate_vm_config() {
    local vm_name="$1"
    local vm_dir="${VM_DIR}/${vm_name}"
    local vm_config="${vm_dir}/config"
    
    if [ ! -d "${vm_dir}" ]; then
        die "VM not found: ${vm_name}"
    fi
    
    if [ ! -f "${vm_config}" ]; then
        die "Config not found: ${vm_config}"
    fi
    
    # Source the config
    source "${vm_config}" 2>/dev/null || true
    
    # Validate required fields
    if [ -z "${arch:-}" ]; then
        die "Architecture not specified"
    fi
    
    if [ -n "${disk:-}" ] && [ ! -f "${disk}" ]; then
        warn "Disk file not found: ${disk}"
    fi
    
    if [ -n "${iso:-}" ] && [ ! -f "${iso}" ]; then
        warn "ISO file not found: ${iso}"
    fi
    
    log "VM configuration is valid"
    return 0
}

# ---------------------------------------------------------------------------
# Insert ISO into VM
# ---------------------------------------------------------------------------
insert_iso() {
    local vm_name="$1"
    local vm_dir="${VM_DIR}/${vm_name}"
    local vm_config="${vm_dir}/config"
    
    validate_vm_config "${vm_name}" || return 1
    
    list_isos
    if [ -z "${selected_iso:-}" ]; then
        die "No ISO selected"
    fi
    
    # Update the config
    if grep -q "^iso=" "${vm_config}" 2>/dev/null; then
        sed -i.bak "s|^iso=.*|iso=${selected_iso}|" "${vm_config}"
    else
        echo "iso=${selected_iso}" >> "${vm_config}"
    fi
    
    log "ISO inserted: ${selected_iso}"
    return 0
}

# ---------------------------------------------------------------------------
# Eject ISO from VM
# ---------------------------------------------------------------------------
eject_iso() {
    local vm_name="$1"
    local vm_dir="${VM_DIR}/${vm_name}"
    local vm_config="${vm_dir}/config"
    
    validate_vm_config "${vm_name}" || return 1
    
    # Clear the ISO
    if grep -q "^iso=" "${vm_config}" 2>/dev/null; then
        sed -i.bak "s|^iso=.*|iso=|" "${vm_config}"
    else
        echo "iso=" >> "${vm_config}"
    fi
    
    log "ISO ejected"
    return 0
}

# ---------------------------------------------------------------------------
# Export VM to UTM format
# ---------------------------------------------------------------------------
export_utm() {
    local vm_name="$1"
    local vm_dir="${VM_DIR}/${vm_name}"
    local vm_config="${vm_dir}/config"
    
    validate_vm_config "${vm_name}" || return 1
    
    # Source the config
    source "${vm_config}" 2>/dev/null || true
    
    # Determine UTM architecture
    local utm_arch=""
    case "${arch:-G4}" in
        "ppc"|"G4"|"604ev"|"604"|"601"|"68040"|"apollocore"|"68k")
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
        *)
            die "Unsupported architecture for UTM: ${arch}"
            ;;
    esac
    
    # Determine UTM OS type
    local utm_os_type="linux"
    if [[ "${arch}" == "ppc" || "${arch}" == "G4" || "${arch}" == "604ev" || "${arch}" == "604" || "${arch}" == "601" || "${arch}" == "68040" ]]; then
        utm_os_type="macOS9"
    fi
    
    # Create UTM config JSON
    local utm_config_file="${vm_dir}/utm-config.json"
    
    cat > "${utm_config_file}" << EOF
{
  "name": "${vm_name}",
  "target": "${utm_arch}",
  "emulator": "softmmu",
  "memory": ${ram:-768},
  "cpuCount": ${cpu:-1},
  "disk": "${disk:-}",
  "iso": "${iso:-}",
  "network": {"mode": "${network_mode:-shared}"},
  "display": {"mode": "gui"},
  "sharing": {"enabled": true, "path": "${SHARE_DIR}", "clipboard": true},
  "vnc": {"enabled": false, "port": 5900},
  "bootOrder": "${boot_order:-dc}"
}
EOF
    
    log "UTM configuration exported to: ${utm_config_file}"
    return 0
}

# ---------------------------------------------------------------------------
# List VMs
# ---------------------------------------------------------------------------
list_vms() {
    local index=1
    local vms=()

    if [ ! -d "${VM_DIR}" ]; then
        mkdir -p "${VM_DIR}"
    fi

    for vm_dir in "${VM_DIR}"/*/; do
        if [ -d "${vm_dir}" ]; then
            local vm_name=$(basename "${vm_dir}")
            vms+=("${vm_name}")
            local vm_config="${vm_dir}/config"
            if [ -f "${vm_config}" ]; then
                source "${vm_config}" 2>/dev/null || true
                local vm_type="QEMU"
                if [ -n "${utm_architecture:-}" ]; then
                    vm_type="UTM"
                fi
                echo "  [${index}] ${vm_name} (type: ${vm_type}, arch: ${arch:-${utm_architecture:-unknown}}, ram: ${ram:-unknown}MB)"
            else
                echo "  [${index}] ${vm_name}"
            fi
            ((index++))
        fi
    done

    if [ ${#vms[@]} -eq 0 ]; then
        echo "  No VMs found"
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Stop VM
# ---------------------------------------------------------------------------
stop_vm() {
    local vm_name="$1"
    local vm_dir="${VM_DIR}/${vm_name}"

    if [ ! -d "${vm_dir}" ]; then
        die "VM not found: ${vm_name}"
    fi

    local pid_file="${vm_dir}/pid"
    if [ -f "${pid_file}" ]; then
        local pid=$(cat "${pid_file}")
        if ps -p "${pid}" > /dev/null 2>&1; then
            kill "${pid}" && {
                log "VM ${vm_name} stopped (PID: ${pid})"
                rm -f "${pid_file}"
            }
        else
            warn "Process ${pid} already terminated"
        fi
        rm -f "${pid_file}"
    fi

    log "VM ${vm_name} stopped"
    return 0
}

# ---------------------------------------------------------------------------
# Delete VM
# ---------------------------------------------------------------------------
delete_vm() {
    local vm_name="$1"
    local vm_dir="${VM_DIR}/${vm_name}"

    if [ ! -d "${vm_dir}" ]; then
        die "VM not found: ${vm_name}"
    fi

    read -rp "Are you sure you want to delete VM ${vm_name} and all its files? [y/N]: " confirm
    if [ "${confirm}" != "y" ]; then
        log "Deletion cancelled"
        return 0
    fi

    stop_vm "${vm_name}" 2>/dev/null || true
    rm -rf "${vm_dir}" && {
        log "VM ${vm_name} deleted"
        return 0
    }

    die "Failed to delete ${vm_name}"
}

# ---------------------------------------------------------------------------
# Start QEMU VM
# ---------------------------------------------------------------------------
start_qemu_vm() {
    local vm_name="$1"
    local vm_dir="${VM_DIR}/${vm_name}"
    local vm_config="${vm_dir}/config"

    if [ ! -d "${vm_dir}" ]; then
        die "VM not found: ${vm_name}"
    fi

    if [ ! -f "${vm_config}" ]; then
        die "Config not found: ${vm_config}"
    fi

    source "${vm_config}" 2>/dev/null || true

    log "Starting VM QEMU: ${vm_name}"
    local arch="${arch:-G4}"
    local machine="${machine:-mac99}"
    local cpu_type="${cpu_type:-7455}"
    local ram="${ram:-768}"
    local cpu_count="${cpu:-1}"
    local display="${display:-cocoa}"
    local num_screens="${num_screens:-1}"
    local disk="${disk:-}"
    local iso="${iso:-}"
    local share_dir="${share_dir:-/tmp/volatile_hd}"
    local network_mode="${network_mode:-nat}"
    local via="${via:-cuda}"
    local multi_screen_method="${multi_screen_method:-auto}"
    local rom_file="${rom_file:-}"
    local enable_gdb="${enable_gdb:-n}"
    local gdb_port="${gdb_port:-$DEFAULT_GDB_PORT}"
    local enable_ssh="${enable_ssh:-n}"
    local ssh_port="${ssh_port:-$DEFAULT_SSH_PORT}"
    local enable_netatalk="${enable_netatalk:-n}"
    local netatalk_share_name="${netatalk_share_name:-VM_${vm_name}}"

    local qemu_args=()

    # Use custom QEMU if available
    local qemu_ppc_bin=$(qemu_bin "qemu-system-ppc")
    local qemu_x86_bin=$(qemu_bin "qemu-system-x86_64")
    local qemu_arm_bin=$(qemu_bin "qemu-system-aarch64")
    local qemu_sparc_bin=$(qemu_bin "qemu-system-sparc64")

    case "${arch}" in
        "G4"|"604ev"|"604"|"601"|"68040"|"apollocore"|"68k"|"ppc")
            if [ -n "${qemu_ppc_bin}" ]; then
                qemu_args+=("${qemu_ppc_bin}")
            else
                qemu_args+=("qemu-system-ppc")
            fi
            ;;
        "x86_64"|"i386"|"i86")
            if [ -n "${qemu_x86_bin}" ]; then
                qemu_args+=("${qemu_x86_bin}")
            else
                qemu_args+=("qemu-system-x86_64")
            fi
            ;;
        "arm"|"arm64")
            if [ -n "${qemu_arm_bin}" ]; then
                qemu_args+=("${qemu_arm_bin}")
            else
                qemu_args+=("qemu-system-aarch64")
            fi
            ;;
        "sparc"|"sparc64")
            if [ -n "${qemu_sparc_bin}" ]; then
                qemu_args+=("${qemu_sparc_bin}")
            else
                qemu_args+=("qemu-system-sparc64")
            fi
            ;;
        *)
            die "Unsupported architecture: ${arch}"
            ;;
    esac

    # ROM file (for old Mac OS like 7.6.1)
    if [ -n "${rom_file}" ] && [ -f "${rom_file}" ]; then
        local rom_size=$(stat -f%z "${rom_file}" 2>/dev/null || stat -c%s "${rom_file}" 2>/dev/null || echo 0)
        if [ "${rom_size}" -le 1048576 ]; then
            qemu_args+=("-bios" "${rom_file}")
            log "Using ROM: $(basename "${rom_file}")"
        else
            warn "ROM too large (${rom_size} bytes > 1MB). QEMU PPC BIOS limit is 1MB. ROM not loaded."
        fi
    fi

    qemu_args+=("-m" "${ram}M")
    qemu_args+=("-smp" "${cpu_count}")

    # Networking
    case "${network_mode}" in
        "nat")
            qemu_args+=("-device" "sungem,mac=52:54:00:12:34:56,netdev=net0")
            qemu_args+=("-netdev" "vmnet-shared,id=net0")
            ;;
        "user")
            qemu_args+=("-netdev" "user,id=net0,net=192.168.100.0/24,dhcpstart=192.168.100.100")
            qemu_args+=("-device" "virtio-net-pci,netdev=net0")
            ;;
    esac

    # GDB debugging
    if [ "${enable_gdb}" = "y" ]; then
        qemu_args+=("-gdb" "tcp::${gdb_port}")
        qemu_args+=("-S")
        log "GDB debugging active on port: ${gdb_port}"
        log "Connect with: gdb-multiarch -ex 'target remote localhost:${gdb_port}'"
    fi

    # SSH port forwarding
    if [ "${enable_ssh}" = "y" ]; then
        qemu_args+=("-netdev" "user,id=sshnet0,hostfwd=tcp::${ssh_port}-:22")
        qemu_args+=("-device" "virtio-net-pci,netdev=sshnet0")
        log "SSH forwarding active: host:${ssh_port} -> guest:22"
    fi

    # Display
    case "${display}" in
        "cocoa") qemu_args+=("-display" "cocoa") ;;
        "sdl") qemu_args+=("-display" "sdl") ;;
        "gtk") qemu_args+=("-display" "gtk") ;;
        "vnc") qemu_args+=("-vnc" ":${VNC_PORT}") ;;
        "spice")
            if command -v qemu-system-x86_64 &>/dev/null && qemu-system-x86_64 -device virtio-serial-pci,help >/dev/null 2>&1; then
                local spice_port=${SPICE_PORT:-5900}
                local spice_socket="/tmp/vm_${vm_name}_spice.sock"
                qemu_args+=("-spice" "unix=on,addr=${spice_socket},disable-ticketing=on,image-compression=off,playback-compression=off,streaming-video=off,gl=off")
                qemu_args+=("-device" "virtio-serial-pci")
                qemu_args+=("-device" "virtserialport,chardev=spicechannel0,name=com.redhat.spice.0")
                qemu_args+=("-chardev" "spicevmc,id=spicechannel0,name=vdagent")
                # For PPC, use -vga none and add VGA device separately
                if [[ "${arch}" =~ ^(G4|604ev|604|68040|601|604|750|7400|ppc)$ ]]; then
                    qemu_args+=("-vga" "none")
                    qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
                fi
                log "SPICE socket: ${spice_socket}"
                log "Connect with: remote-viewer spice://${spice_socket} or use virt-viewer"
            else
                log_warn "SPICE support not detected in QEMU. Falling back to VNC."
                qemu_args+=("-vnc" ":${VNC_PORT:-5900}")
            fi
            ;;
        "none") qemu_args+=("-nographic") ;;
        *) qemu_args+=("-display" "cocoa") ;;
    esac

    # File sharing
    if [ -d "${share_dir}" ]; then
        qemu_args+=("-fsdev" "local,security_model=mapped,id=fsdev0,path=${share_dir}")
        qemu_args+=("-device" "virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare")
    fi

    # Architecture-specific settings
    case "${arch}" in
        "G4"|"604ev"|"ppc"|"68040"|"601"|"604"|"750"|"7400")
            local ppc_machine="${machine:-mac99}"
            case "${arch}" in
                "604ev"|"604"|"68040"|"601"|"750"|"7400") ppc_machine="g3beige" ;;
            esac
            if [ "${ppc_machine}" = "g3beige" ]; then
                qemu_args+=("-machine" "${ppc_machine}")
            else
                qemu_args+=("-machine" "${ppc_machine},via=${via}")
            fi
            qemu_args+=("-cpu" "${cpu_type}")
            qemu_args+=("-accel" "tcg,tb-size=128")

            # Multi-screen for PPC
            if [ "${num_screens}" -gt 1 ]; then
                case "${multi_screen_method}" in
                    "graphic-engine")
                        qemu_args+=("-device" "graphic-drawing-engine,heads=${num_screens}")
                        ;;
                    "dual-pci-vga")
                        qemu_args+=("-prom-env" "vga-ndrv?=true")
                        qemu_args+=("-g" "1024x768x32")
                        qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video0,xres=1024,yres=768")
                        for (( s=1; s<num_screens; s++ )); do
                            qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video${s},xres=1024,yres=768")
                        done
                        ;;
                    "auto"|"")
                        if command -v qemu-system-ppc &>/dev/null; then
                            # Check if graphic-drawing-engine is available
                            if qemu-system-ppc -device graphic-drawing-engine,help >/dev/null 2>&1; then
                                qemu_args+=("-device" "graphic-drawing-engine,heads=${num_screens}")
                            else
                                qemu_args+=("-prom-env" "vga-ndrv?=true")
                                qemu_args+=("-g" "1024x768x32")
                                qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video0,xres=1024,yres=768")
                                for (( s=1; s<num_screens; s++ )); do
                                    qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video${s},xres=1024,yres=768")
                                done
                            fi
                        fi
                        ;;
                esac
            else
                qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
            fi

            # ISO and disk for PPC
            if [ -n "${iso}" ] && [ -f "${iso}" ]; then
                qemu_args+=("-drive" "if=none,media=cdrom,id=drive1,file=${iso},readonly=on")
                qemu_args+=("-device" "ide-cd,bus=ide.0,unit=1,drive=drive1,bootindex=0")
            fi
            if [ -n "${disk}" ] && [ -f "${disk}" ]; then
                qemu_args+=("-drive" "if=none,media=disk,id=drive0,file=${disk},format=qcow2")
                qemu_args+=("-device" "ide-hd,bus=ide.0,unit=0,drive=drive0,bootindex=1")
            fi

            qemu_args+=("-prom-env" "boot-args=-v")
            qemu_args+=("-prom-env" "vga-ndrv?=true")
            qemu_args+=("-prom-env" "auto-boot?=true")

            # NDRV loader for Mac OS
            local ndrv_loader=""
            for path in \
                "/usr/local/share/qemu/ppc-ndrvloader" \
                "/usr/share/qemu/ppc-ndrvloader" \
                "/opt/local/share/qemu/ppc-ndrvloader" \
                "${HOME}/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu/ppc-ndrvloader" \
                "/Applications/UTM.app/Contents/Resources/qemu/share/qemu/ppc-ndrvloader" \
                "/tmp/volatile_hd/ppc-ndrvloader"; do
                if [ -f "${path}" ]; then
                    ndrv_loader="${path}"
                    break
                fi
            done
            if [ -n "${ndrv_loader}" ]; then
                qemu_args+=("-device" "loader,addr=0x4000000,file=${ndrv_loader}")
                log "Using NDRV loader: ${ndrv_loader}"
            else
                log_warn "NDRV loader not found. Some Mac OS versions may not boot properly."
                log_warn "Download from: https://github.com/cesarblum/openbios/raw/master/bin/ppc-ndrvloader"
            fi
            ;;

        "x86_64"|"i386"|"i86")
            qemu_args+=("-machine" "q35,accel=hvf")
            qemu_args+=("-cpu" "host")

            if [ "${num_screens}" -gt 1 ]; then
                qemu_args+=("-vga" "virtio")
                for (( s=1; s<num_screens; s++ )); do
                    qemu_args+=("-device" "virtio-gpu-pci")
                done
            else
                qemu_args+=("-vga" "virtio")
            fi

            if [ -n "${disk}" ] && [ -f "${disk}" ]; then
                qemu_args+=("-drive" "file=${disk},format=qcow2,if=virtio")
            fi

            if [ -n "${iso}" ] && [ -f "${iso}" ]; then
                qemu_args+=("-cdrom" "${iso}")
            fi
            ;;

        "arm"|"arm64")
            qemu_args+=("-machine" "virt")
            qemu_args+=("-cpu" "host")

            if [ "${arch}" = "arm" ]; then
                qemu_args+=("-bios" "/usr/local/share/qemu-edk2/arm/edk2-arm-code.fd")
            fi

            if [ "${num_screens}" -gt 1 ]; then
                qemu_args+=("-vga" "virtio")
                for (( s=1; s<num_screens; s++ )); do
                    qemu_args+=("-device" "virtio-gpu-pci")
                done
            else
                qemu_args+=("-vga" "virtio")
            fi

            if [ -n "${disk}" ] && [ -f "${disk}" ]; then
                qemu_args+=("-drive" "file=${disk},format=qcow2,if=virtio")
            fi

            if [ -n "${iso}" ] && [ -f "${iso}" ]; then
                qemu_args+=("-cdrom" "${iso}")
            fi
            ;;

        "sparc"|"sparc64")
            local sparc_machine=""
            local sparc_cpu=""
            if [ "${arch}" = "sparc" ]; then
                sparc_machine="sun4m"
                sparc_cpu="Fujitsu+MB86904"
            else
                sparc_machine="sun4u"
                sparc_cpu="Fujitsu+Sparc64IV+"
            fi

            qemu_args+=("-machine" "${sparc_machine}")
            qemu_args+=("-cpu" "${sparc_cpu}")

            if [ "${num_screens}" -gt 1 ]; then
                qemu_args+=("-vga" "tcx")
            else
                qemu_args+=("-vga" "tcx")
            fi

            if [ -n "${disk}" ] && [ -f "${disk}" ]; then
                qemu_args+=("-drive" "file=${disk},format=qcow2,if=scsi")
            fi

            if [ -n "${iso}" ] && [ -f "${iso}" ]; then
                qemu_args+=("-cdrom" "${iso}")
            fi
            ;;

        *)
            die "Unsupported architecture: ${arch}"
            ;;
    esac

    log "Starting VM with command:"
    echo "  ${qemu_args[*]}"

    # Save command to start.sh
    mkdir -p "${vm_dir}"
    echo "#!/bin/bash" > "${vm_dir}/start.sh"
    echo "# Generated by vm-assistant-unified" >> "${vm_dir}/start.sh"
    echo "exec " >> "${vm_dir}/start.sh"
    printf "%s " "${qemu_args[@]}" >> "${vm_dir}/start.sh"
    echo "" >> "${vm_dir}/start.sh"
    chmod +x "${vm_dir}/start.sh"
    log "Command saved to: ${vm_dir}/start.sh"

    # Execute
    echo ""
    exec "${qemu_args[@]}"
}

# ---------------------------------------------------------------------------
# Create VM configuration
# ---------------------------------------------------------------------------
create_vm() {
    local vm_name="$1"

    if [ -z "${vm_name}" ]; then
        die "Usage: create_vm VMNAME"
    fi

    echo "VM Type:"
    echo "  [1] QEMU (command line)"
    echo "  [2] UTM (graphical app)"
    read -rp "Type [1]: " vm_type_choice
    vm_type_choice=${vm_type_choice:-1}

    local vm_dir="${VM_DIR}/${vm_name}"
    mkdir -p "${vm_dir}"

    case "${vm_type_choice}" in
        1)
            heading "Creating QEMU VM: ${vm_name}"

            echo "Architecture:"
            echo "  [1] G4 (PowerPC)"
            echo "  [2] 604ev (PowerPC)"
            echo "  [3] 604 (PowerPC)"
            echo "  [4] 601 (PowerPC)"
            echo "  [5] 68040 (Motorola)"
            echo "  [6] apollocore (68080)"
            echo "  [7] x86_64 (Intel/AMD)"
            echo "  [8] arm"
            echo "  [9] arm64"
            echo "  [10] sparc"
            echo "  [11] sparc64"
            read -rp "Architecture [1]: " arch_choice
            arch_choice=${arch_choice:-1}

            local arch=""
            local machine=""
            local cpu_type=""
            case ${arch_choice} in
                1) arch="G4"; machine="mac99"; cpu_type="7455" ;;
                2) arch="604ev"; machine="g3beige"; cpu_type="604ev" ;;
                3) arch="604"; machine="g3beige"; cpu_type="604" ;;
                4) arch="601"; machine="g3beige"; cpu_type="601" ;;
                5) arch="68040"; machine="mac99"; cpu_type="68040" ;;
                6) arch="apollocore"; machine="q800"; cpu_type="68080" ;;
                7) arch="x86_64"; machine="q35"; cpu_type="host" ;;
                8) arch="arm"; machine="virt"; cpu_type="cortina-a9" ;;
                9) arch="arm64"; machine="virt"; cpu_type="host" ;;
                10) arch="sparc"; machine="sun4m"; cpu_type="Fujitsu+MB86904" ;;
                11) arch="sparc64"; machine="sun4u"; cpu_type="Fujitsu+Sparc64IV+" ;;
                *) arch="G4"; machine="mac99"; cpu_type="7455" ;;
            esac

            read -rp "RAM in MB [768]: " ram
            ram=${ram:-768}

            read -rp "CPU count [1]: " cpu_count
            cpu_count=${cpu_count:-1}

            read -rp "Number of screens [1]: " num_screens
            num_screens=${num_screens:-1}

            echo "Multi-screen method:"
            echo "  [1] Auto"
            echo "  [2] Dual-PCI VGA"
            echo "  [3] Graphic Engine"
            read -rp "Method [1]: " method_choice
            method_choice=${method_choice:-1}
            local multi_screen_method=""
            case ${method_choice} in
                1) multi_screen_method="auto" ;;
                2) multi_screen_method="dual-pci-vga" ;;
                3) multi_screen_method="graphic-engine" ;;
                *) multi_screen_method="auto" ;;
            esac

            read -rp "VIA type (pmu/cuda/none) [cuda]: " via
            via=${via:-cuda}

            echo "Boot disk:"
            echo "  [1] Create a new disk"
            echo "  [2] Use existing disk"
            echo "  [3] No disk"
            read -rp "Option [1]: " disk_choice
            disk_choice=${disk_choice:-1}
            local disk=""
            case ${disk_choice} in
                1) create_disk "${vm_name}" && disk="${selected_disk}" || disk="" ;;
                2) list_disks && disk="${selected_disk}" || disk="" ;;
            esac

            echo "ISO:"
            echo "  [1] Select existing ISO"
            echo "  [2] No ISO"
            read -rp "Option [2]: " iso_choice
            iso_choice=${iso_choice:-2}
            local iso=""
            if [ "${iso_choice}" = "1" ]; then
                list_isos && iso="${selected_iso}" || iso=""
            fi

            echo "Network mode:"
            echo "  [1] NAT"
            echo "  [2] User"
            echo "  [3] None"
            read -rp "Mode [1]: " net_choice
            net_choice=${net_choice:-1}
            local network_mode=""
            case ${net_choice} in
                1) network_mode="nat" ;;
                2) network_mode="user" ;;
                3) network_mode="none" ;;
            esac

            read -rp "Share directory [${SHARE_DIR}]: " share_dir_input
            share_dir=${share_dir_input:-${SHARE_DIR}}

            echo "ROM file (optional for old Mac OS):"
            echo "  [1] Select a ROM"
            echo "  [2] None"
            read -rp "Option [2]: " rom_choice
            rom_choice=${rom_choice:-2}
            local rom_file=""
            if [ "${rom_choice}" = "1" ]; then
                list_roms && rom_file="${selected_rom}" || rom_file=""
            fi

            echo ""
            echo "Debug/Network options:"
            read -rp "Enable GDB debugging [n]: " enable_gdb_input
            enable_gdb=${enable_gdb_input:-n}
            local gdb_port=""
            if [ "${enable_gdb}" = "y" ]; then
                read -rp "  GDB port [${DEFAULT_GDB_PORT}]: " gdb_port
                gdb_port=${gdb_port:-${DEFAULT_GDB_PORT}}
            fi

            read -rp "Enable SSH forward [n]: " enable_ssh_input
            enable_ssh=${enable_ssh_input:-n}
            local ssh_port=""
            if [ "${enable_ssh}" = "y" ]; then
                read -rp "  SSH port [${DEFAULT_SSH_PORT}]: " ssh_port
                ssh_port=${ssh_port:-${DEFAULT_SSH_PORT}}
            fi

            read -rp "Enable Netatalk [n]: " enable_netatalk_input
            enable_netatalk=${enable_netatalk_input:-n}
            local netatalk_share_name=""
            if [ "${enable_netatalk}" = "y" ]; then
                read -rp "  Share name [VM_${vm_name}]: " netatalk_share_name
                netatalk_share_name=${netatalk_share_name:-VM_${vm_name}}
            fi

            echo "Display mode:"
            echo "  [1] Cocoa (GUI)"
            echo "  [2] SDL"
            echo "  [3] GTK"
            echo "  [4] VNC"
            echo "  [5] SPICE (multi-ecran + USB redirection)"
            echo "  [6] None (console)"
            read -rp "Mode [1]: " display_choice
            display_choice=${display_choice:-1}
            local display=""
            case ${display_choice} in
                1) display="cocoa" ;;
                2) display="sdl" ;;
                3) display="gtk" ;;
                4) display="vnc" ;;
                5) display="spice" ;;
                6) display="none" ;;
            esac

            # Save configuration
            cat > "${vm_dir}/config" << CONFIG
# VM Configuration: ${vm_name}
# Date: $(date)
# Architecture
arch=${arch}
machine=${machine}
cpu_type=${cpu_type}
# Resources
ram=${ram}
cpu=${cpu_count}
# Storage
disk=${disk}
iso=${iso}
# Network
network_mode=${network_mode}
# Display
display=${display}
num_screens=${num_screens}
multi_screen_method=${multi_screen_method}
via=${via}
share_dir=${share_dir}
rom_file=${rom_file:-}
# Debug/Network
enable_gdb=${enable_gdb}
gdb_port=${gdb_port:-}
enable_ssh=${enable_ssh}
ssh_port=${ssh_port:-}
enable_netatalk=${enable_netatalk}
netatalk_share_name=${netatalk_share_name:-}
CONFIG

            log "QEMU VM created: ${vm_name}"
            ;;

        2)
            heading "Creating UTM VM: ${vm_name}"

            local default_ram=4096
            local default_cpu=2
            local default_disk_size="20G"

            read -rp "RAM in MB [${default_ram}]: " vm_ram
            read -rp "CPU count [${default_cpu}]: " vm_cpu
            read -rp "Disk size [${default_disk_size}]: " vm_disk_size

            vm_ram=${vm_ram:-${default_ram}}
            vm_cpu=${vm_cpu:-${default_cpu}}
            vm_disk_size=${vm_disk_size:-${default_disk_size}}

            echo ""
            echo "Operating System Type:"
            echo "  [1] Mac OS 9"
            echo "  [2] Mac OS X 10.4"
            echo "  [3] Mac OS X 10.5"
            echo "  [4] Linux"
            echo "  [5] Windows"
            echo "  [6] DOS"
            read -rp "Type [1]: " utm_os_type_choice
            utm_os_type_choice=${utm_os_type_choice:-1}
            local utm_os_type=""
            case ${utm_os_type_choice} in
                1) utm_os_type="macOS9" ;;
                2) utm_os_type="macOS10.4" ;;
                3) utm_os_type="macOS10.5" ;;
                4) utm_os_type="linux" ;;
                5) utm_os_type="windows" ;;
                6) utm_os_type="dos" ;;
                *) utm_os_type="macOS9" ;;
            esac

            echo ""
            echo "Architecture:"
            echo "  [1] PowerPC (G3/G4)"
            echo "  [2] x86_64"
            echo "  [3] ARM64"
            echo "  [4] ARM"
            echo "  [5] SPARC"
            echo "  [6] SPARC64"
            read -rp "Architecture [1]: " utm_arch_choice
            utm_arch_choice=${utm_arch_choice:-1}
            local utm_architecture=""
            case ${utm_arch_choice} in
                1) utm_architecture="ppc" ;;
                2) utm_architecture="x86_64" ;;
                3) utm_architecture="arm64" ;;
                4) utm_architecture="arm" ;;
                5) utm_architecture="sparc" ;;
                6) utm_architecture="sparc64" ;;
                *) utm_architecture="ppc" ;;
            esac

            echo ""
            echo "Display mode:"
            echo "  [1] GUI"
            echo "  [2] Terminal"
            read -rp "Mode [1]: " utm_display_choice
            utm_display_choice=${utm_display_choice:-1}
            local utm_display=""
            case ${utm_display_choice} in
                1) utm_display="gui" ;;
                2) utm_display="terminal" ;;
                *) utm_display="gui" ;;
            esac

            echo ""
            echo "Advanced options:"
            read -rp "  Enable file sharing [y/N]: " utm_sharing
            utm_sharing=${utm_sharing:-n}
            local utm_sharing_path=""
            if [ "${utm_sharing}" = "y" ]; then
                read -rp "  Share path [${SHARE_DIR}]: " utm_sharing_path_input
                utm_sharing_path="${utm_sharing_path_input:-${SHARE_DIR}}"
            fi

            read -rp "  Enable clipboard sharing [y/N]: " utm_clipboard
            utm_clipboard=${utm_clipboard:-n}

            read -rp "  Enable VNC [y/N]: " utm_vnc
            utm_vnc=${utm_vnc:-n}
            local utm_vnc_port=5900
            if [ "${utm_vnc}" = "y" ]; then
                read -rp "  VNC port [${utm_vnc_port}]: " utm_vnc_port_input
                utm_vnc_port="${utm_vnc_port_input:-${utm_vnc_port}}"
            fi

            echo ""
            echo "Network mode:"
            echo "  [1] Shared (NAT)"
            echo "  [2] Bridged"
            echo "  [3] Host only"
            echo "  [4] Disconnected"
            read -rp "  Network mode [1]: " utm_network_choice
            utm_network_choice=${utm_network_choice:-1}
            local utm_network_mode=""
            case ${utm_network_choice} in
                1) utm_network_mode="shared" ;;
                2) utm_network_mode="bridged" ;;
                3) utm_network_mode="host" ;;
                4) utm_network_mode="disconnected" ;;
                *) utm_network_mode="shared" ;;
            esac

            echo ""
            echo "Emulation mode:"
            local system_mode_available=false
            case ${utm_architecture} in
                "arm64"|"arm"|"x86_64"|"sparc"|"sparc64")
                    system_mode_available=true
                    ;;
                "ppc")
                    echo "  Note: PowerPC only supports SoftMMU"
                    system_mode_available=false
                    ;;
            esac

            local utm_emulator="softmmu"
            if [ "${system_mode_available}" = true ]; then
                echo "  [1] SoftMMU"
                echo "  [2] System"
                read -rp "  Mode [1]: " utm_emulator_choice
                utm_emulator_choice=${utm_emulator_choice:-1}
                case ${utm_emulator_choice} in
                    1) utm_emulator="softmmu" ;;
                    2) utm_emulator="system" ;;
                esac
            fi

            echo ""
            read -rp "  Boot order [1=CD, 2=Disk, 3=CD+Disk]: " utm_boot_choice
            utm_boot_choice=${utm_boot_choice:-1}
            local boot_order=""
            local iso_path=""
            case ${utm_boot_choice} in
                1) boot_order="d" ;;
                2) boot_order="c" ;;
                3) boot_order="dc" ;;
                *) boot_order="dc" ;;
            esac

            if [ "${boot_order}" = "d" ] || [ "${boot_order}" = "dc" ]; then
                list_isos
                if [ -n "${selected_iso:-}" ]; then
                    iso_path="${selected_iso}"
                fi
            fi

            local utm_disk_path="${DISK_DIR}/${vm_name}.qcow2"
            mkdir -p "${DISK_DIR}"
            qemu_img_bin create -f qcow2 "${utm_disk_path}" "${vm_disk_size}" || {
                die "Failed to create disk"
            }

            # Save QEMU-style config (for compatibility)
            cat > "${vm_dir}/config" << CONFIG
# UTM VM Configuration: ${vm_name}
utm_os_type=${utm_os_type}
utm_architecture=${utm_architecture}
utm_emulator=${utm_emulator}
ram=${vm_ram}
cpu=${vm_cpu}
disk=${utm_disk_path}
iso=${iso_path}
utm_network_mode=${utm_network_mode}
utm_display=${utm_display}
utm_sharing=${utm_sharing}
utm_sharing_path=${utm_sharing_path}
utm_clipboard=${utm_clipboard}
utm_vnc=${utm_vnc}
utm_vnc_port=${utm_vnc_port}
boot_order=${boot_order}
CONFIG

            # Also save UTM JSON config
            cat > "${vm_dir}/utm-config.json" << EOF
{
  "name": "${vm_name}",
  "target": "${utm_architecture}",
  "emulator": "${utm_emulator}",
  "memory": ${vm_ram},
  "cpuCount": ${vm_cpu},
  "disk": "${utm_disk_path}",
  "iso": "${iso_path}",
  "network": {"mode": "${utm_network_mode}"},
  "display": {"mode": "${utm_display}"},
  "sharing": {"enabled": "${utm_sharing}", "path": "${utm_sharing_path}", "clipboard": "${utm_clipboard}"},
  "vnc": {"enabled": "${utm_vnc}", "port": ${utm_vnc_port}},
  "bootOrder": "${boot_order}"
}
EOF

            log "UTM VM created: ${vm_name}"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Edit VM configuration
# ---------------------------------------------------------------------------
edit_vm() {
    local vm_name="$1"
    local vm_dir="${VM_DIR}/${vm_name}"
    local vm_config="${vm_dir}/config"

    if [ ! -d "${vm_dir}" ]; then
        die "VM not found: ${vm_name}"
    fi

    if [ ! -f "${vm_config}" ]; then
        die "Config not found: ${vm_config}"
    fi

    source "${vm_config}" 2>/dev/null || true

    heading "Editing VM: ${vm_name}"

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
        echo "  [8] Debug/Network (GDB/SSH/Netatalk)"
        echo "  [9] Show current config"
        echo "  [S] Save and exit"
        echo "  [Q] Exit without saving"
        echo ""

        read -rp "Select option [9]: " choice
        choice=${choice:-9}

        case "${choice}" in
            1)
                echo "Current: arch=${arch:-G4}, machine=${machine:-mac99}, cpu_type=${cpu_type:-7455}, via=${via:-cuda}"
                echo "Available CPU types for PowerPC:"
                echo "  7455 - G4 900MHz (recommended)"
                echo "  7450 - G4 733MHz"
                echo "  7410 - G4 500MHz"
                echo "  750  - G3 900MHz"
                echo "  604ev - PowerPC 604e"
                echo "  604  - PowerPC 604"
                echo "  601  - PowerPC 601"
                echo "  68040 - Motorola 68040"
                read -rp "Architecture (G4/601/604ev/604/ppc/68040/apollocore/arm/arm64/sparc/sparc64) [${arch:-G4}]: " arch
                read -rp "Machine [${machine:-mac99}]: " machine
                read -rp "CPU type [${cpu_type:-7455}]: " cpu_type
                read -rp "VIA type (pmu/cuda/none) [${via:-cuda}]: " via
                arch=${arch:-G4}
                machine=${machine:-mac99}
                cpu_type=${cpu_type:-7455}
                via=${via:-cuda}
                ;;

            2)
                read -rp "RAM in MB [${ram:-768}]: " ram
                read -rp "CPU count [${cpu:-1}]: " cpu
                ram=${ram:-768}
                cpu=${cpu:-1}
                ;;

            3)
                echo "  [A] Select existing disk"
                echo "  [B] Select existing ISO"
                echo "  [C] Clear disk"
                echo "  [D] Clear ISO"
                read -rp "Option [A/B/C/D]: " storage_choice
                case "${storage_choice}" in
                    A) list_disks && disk="${selected_disk}" || echo "No disk selected" ;;
                    B) list_isos && iso="${selected_iso}" || echo "No ISO selected" ;;
                    C) disk="" ;;
                    D) iso="" ;;
                esac
                ;;

            4)
                read -rp "Display (cocoa/sdl/gtk/vnc/spice/none) [${display:-cocoa}]: " display
                read -rp "Number of screens [${num_screens:-1}]: " num_screens
                read -rp "Multi-screen method (auto/dual-pci-vga/graphic-engine) [${multi_screen_method:-auto}]: " multi_screen_method
                display=${display:-cocoa}
                num_screens=${num_screens:-1}
                multi_screen_method=${multi_screen_method:-auto}
                ;;

            5)
                read -rp "Network mode (nat/user/none) [${network_mode:-nat}]: " network_mode
                network_mode=${network_mode:-nat}
                ;;

            6)
                read -rp "Share directory [${share_dir:-/tmp/volatile_hd}]: " share_dir
                share_dir=${share_dir:-/tmp/volatile_hd}
                ;;

            7)
                list_roms && rom_file="${selected_rom}" || echo "No ROM selected"
                ;;

            8)
                read -rp "Enable GDB debugging [${enable_gdb:-n}]: " enable_gdb
                enable_gdb=${enable_gdb:-n}
                if [ "${enable_gdb}" = "y" ]; then
                    read -rp "  GDB port [${DEFAULT_GDB_PORT}]: " gdb_port
                    gdb_port=${gdb_port:-${DEFAULT_GDB_PORT}}
                else
                    gdb_port=""
                fi

                read -rp "Enable SSH forward [${enable_ssh:-n}]: " enable_ssh
                enable_ssh=${enable_ssh:-n}
                if [ "${enable_ssh}" = "y" ]; then
                    read -rp "  SSH port [${DEFAULT_SSH_PORT}]: " ssh_port
                    ssh_port=${ssh_port:-${DEFAULT_SSH_PORT}}
                else
                    ssh_port=""
                fi

                read -rp "Enable Netatalk [${enable_netatalk:-n}]: " enable_netatalk
                enable_netatalk=${enable_netatalk:-n}
                if [ "${enable_netatalk}" = "y" ]; then
                    read -rp "  Share name [VM_${vm_name}]: " netatalk_share_name
                    netatalk_share_name=${netatalk_share_name:-VM_${vm_name}}
                else
                    netatalk_share_name=""
                fi
                ;;

            9)
                echo "Current configuration:"
                echo "  arch=${arch} machine=${machine} cpu_type=${cpu_type} via=${via}"
                echo "  ram=${ram} cpu=${cpu}"
                echo "  disk=${disk} iso=${iso}"
                echo "  display=${display} num_screens=${num_screens} method=${multi_screen_method}"
                echo "  network_mode=${network_mode} share_dir=${share_dir}"
                echo "  rom_file=${rom_file:-none}"
                echo "  GDB: ${enable_gdb:-no} port=${gdb_port:-none}"
                echo "  SSH: ${enable_ssh:-no} port=${ssh_port:-none}"
                echo "  Netatalk: ${enable_netatalk:-no} share=${netatalk_share_name:-none}"
                ;;

            S|s)
                cat > "${vm_config}" << CONFIG
# VM Configuration: ${vm_name}
# Date: $(date)
# Architecture
arch=${arch:-G4}
machine=${machine:-mac99}
cpu_type=${cpu_type:-7455}
# Resources
ram=${ram:-768}
cpu=${cpu:-1}
# Storage
disk=${disk:-}
iso=${iso:-}
# Network
network_mode=${network_mode:-nat}
# Display
display=${display:-cocoa}
num_screens=${num_screens:-1}
multi_screen_method=${multi_screen_method:-auto}
# Sharing
share_dir=${share_dir:-/tmp/volatile_hd}
via=${via:-cuda}
rom_file=${rom_file:-}
# Debug/Network
enable_gdb=${enable_gdb:-n}
gdb_port=${gdb_port:-}
enable_ssh=${enable_ssh:-n}
ssh_port=${ssh_port:-}
enable_netatalk=${enable_netatalk:-n}
netatalk_share_name=${netatalk_share_name:-}
CONFIG
                log "Configuration saved for ${vm_name}"
                return 0
                ;;

            Q|q)
                return 0
                ;;

            *)
                echo "Invalid option"
                ;;
        esac
        echo ""
    done
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------
show_main_menu() {
    detect_dependencies

    while true; do
        clear || echo ""
        heading "VM Assistant Unified - Main Menu"
        echo ""
        echo "QEMU Management:"
        echo "  [1] Build QEMU with patches (custom version)"
        echo "  [2] Check QEMU installation"
        echo ""
        echo "VM Management:"
        echo "  [3] Create a new VM"
        echo "  [4] Start a VM"
        echo "  [5] Edit a VM"
        echo "  [6] List VMs"
        echo "  [7] Stop a VM"
        echo "  [8] Delete a VM"
        echo ""
        echo "ISO/Disk Management:"
        echo "  [9] Insert ISO into VM"
        echo "  [A] Eject ISO from VM"
        echo "  [B] Create new disk"
        echo "  [C] List disks"
        echo ""
        echo "Advanced:"
        echo "  [D] Validate VM configuration"
        echo "  [E] Export VM to UTM format"
        echo "  [F] Configure network sharing (Samba/Netatalk)"
        echo "  [G] Verify installation"
        echo ""
        echo "  [Q] Quit"
        echo ""

        # Status
        [ "${UTM_INSTALLED}" = true ] && echo "  ${C_GREEN}✓${C_RESET} UTM.app installed" || echo "  ${C_RED}✗${C_RESET} UTM.app not installed"
        [ "${XQUARTZ_INSTALLED}" = true ] && echo "  ${C_GREEN}✓${C_RESET} XQuartz installed" || echo "  ${C_RED}✗${C_RESET} XQuartz not installed"
        [ "${MACPORTS_INSTALLED}" = true ] && echo "  ${C_GREEN}✓${C_RESET} MacPorts installed" || echo "  ${C_RED}✗${C_RESET} MacPorts not installed"
        [ "${HOMEBREW_INSTALLED}" = true ] && echo "  ${C_GREEN}✓${C_RESET} Homebrew installed" || echo "  ${C_RED}✗${C_RESET} Homebrew not installed"
        if [ ${#QEMU_ARCHS[@]} -gt 0 ]; then
            echo "  ${C_GREEN}✓${C_RESET} QEMU available for: ${QEMU_ARCHS[*]}"
        else
            echo "  ${C_RED}✗${C_RESET} No QEMU installed"
        fi
        echo ""

        read -rp "Select an option [Q]: " choice
        choice=${choice:-Q}

        case "${choice}" in
            1)
                heading "Building QEMU with patches"
                if [ -f "${SCRIPT_DIR}/build_qemu.sh" ]; then
                    "${SCRIPT_DIR}/build_qemu.sh" all
                else
                    die "build_qemu.sh not found"
                fi
                ;;

            2)
                heading "Checking QEMU installation"
                for arch in "${QEMU_ARCHS[@]}"; do
                    local qemu_bin=$(qemu_bin "qemu-system-${arch}")
                    if [ -n "${qemu_bin}" ]; then
                        log "qemu-system-${arch}: ✓ found at ${qemu_bin}"
                    else
                        warn "qemu-system-${arch}: ✗ not found"
                    fi
                done
                read -rp "Press Enter to continue..." 
                ;;

            3)
                read -rp "VM name: " vm_name
                if [ -n "${vm_name}" ]; then
                    create_vm "${vm_name}"
                else
                    die "Empty name"
                fi
                read -rp "Press Enter to continue..." 
                ;;

            4)
                list_vms && read -rp "Select a VM: " vm_index
                if [ -n "${vm_index}" ]; then
                    vm_name=$(ls "${VM_DIR}" | sed -n "${vm_index}p")
                    if [ -n "${vm_name}" ]; then
                        start_qemu_vm "${vm_name}"
                    else
                        die "Invalid VM"
                    fi
                fi
                read -rp "Press Enter to continue..." 
                ;;

            5)
                list_vms && read -rp "Select a VM: " vm_index
                if [ -n "${vm_index}" ]; then
                    vm_name=$(ls "${VM_DIR}" | sed -n "${vm_index}p")
                    if [ -n "${vm_name}" ]; then
                        edit_vm "${vm_name}"
                    else
                        die "Invalid VM"
                    fi
                fi
                ;;

            6)
                list_vms
                read -rp "Press Enter to continue..." 
                ;;

            7)
                list_vms && read -rp "Select a VM: " vm_index
                if [ -n "${vm_index}" ]; then
                    vm_name=$(ls "${VM_DIR}" | sed -n "${vm_index}p")
                    if [ -n "${vm_name}" ]; then
                        stop_vm "${vm_name}"
                    else
                        die "Invalid VM"
                    fi
                fi
                read -rp "Press Enter to continue..." 
                ;;

            8)
                list_vms && read -rp "Select a VM: " vm_index
                if [ -n "${vm_index}" ]; then
                    vm_name=$(ls "${VM_DIR}" | sed -n "${vm_index}p")
                    if [ -n "${vm_name}" ]; then
                        delete_vm "${vm_name}"
                    else
                        die "Invalid VM"
                    fi
                fi
                read -rp "Press Enter to continue..." 
                ;;

            9)
                list_vms && read -rp "Select a VM: " vm_index
                if [ -n "${vm_index}" ]; then
                    vm_name=$(ls "${VM_DIR}" | sed -n "${vm_index}p")
                    if [ -n "${vm_name}" ]; then
                        insert_iso "${vm_name}"
                    else
                        die "Invalid VM"
                    fi
                fi
                read -rp "Press Enter to continue..." 
                ;;

            A|a)
                list_vms && read -rp "Select a VM: " vm_index
                if [ -n "${vm_index}" ]; then
                    vm_name=$(ls "${VM_DIR}" | sed -n "${vm_index}p")
                    if [ -n "${vm_name}" ]; then
                        eject_iso "${vm_name}"
                    else
                        die "Invalid VM"
                    fi
                fi
                read -rp "Press Enter to continue..." 
                ;;

            B|b)
                read -rp "VM name for disk: " vm_name
                create_disk "${vm_name:-new_vm}"
                read -rp "Press Enter to continue..." 
                ;;

            C|c)
                list_disks
                read -rp "Press Enter to continue..." 
                ;;

            D|d)
                list_vms && read -rp "Select a VM: " vm_index
                if [ -n "${vm_index}" ]; then
                    vm_name=$(ls "${VM_DIR}" | sed -n "${vm_index}p")
                    if [ -n "${vm_name}" ]; then
                        validate_vm_config "${vm_name}"
                    else
                        die "Invalid VM"
                    fi
                fi
                read -rp "Press Enter to continue..." 
                ;;

            E|e)
                list_vms && read -rp "Select a VM: " vm_index
                if [ -n "${vm_index}" ]; then
                    vm_name=$(ls "${VM_DIR}" | sed -n "${vm_index}p")
                    if [ -n "${vm_name}" ]; then
                        export_utm "${vm_name}"
                    else
                        die "Invalid VM"
                    fi
                fi
                read -rp "Press Enter to continue..." 
                ;;

            F|f)
                if [ -f "${SCRIPT_DIR}/vm-assistant-network.sh" ]; then
                    "${SCRIPT_DIR}/vm-assistant-network.sh"
                else
                    die "vm-assistant-network.sh not found"
                fi
                ;;

            G|g)
                heading "Verification de l'installation"
                for arch in ppc x86_64; do
                    command -v "qemu-system-${arch}" &>/dev/null && log "qemu-system-${arch}: ✓ trouvé" || warn "qemu-system-${arch}: ✗ non trouvé"
                done
                command -v qemu-img &>/dev/null && log "qemu-img: ✓ trouvé" || warn "qemu-img: ✗ non trouvé"
                [ "${UTM_INSTALLED}" = true ] && log "UTM.app: ✓ installé" || warn "UTM.app: ✗ non installé"
                [ -d "/Applications/Utilities/XQuartz.app" ] && log "XQuartz: ✓ installé" || warn "XQuartz: ✗ non installé"
                [ "${NETATALK_INSTALLED:-false}" = true ] && log "Netatalk: ✓ disponible" || warn "Netatalk: ✗ non disponible"
                [ "${GDB_INSTALLED:-false}" = true ] && log "GDB: ✓ disponible" || warn "GDB: ✗ non disponible"
                read -rp "Press Enter to continue..." 
                ;;

            Q|q)
                log "Goodbye!"
                exit 0
                ;;

            *)
                echo "Invalid option"
                ;;
        esac
        echo ""
    done
}

# ---------------------------------------------------------------------------
# Initialize directories
# ---------------------------------------------------------------------------
init_directories() {
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${VM_DIR}"
    mkdir -p "${DISK_DIR}"
    mkdir -p "${ISO_DIR}"
    mkdir -p "${SHARE_DIR}"
    mkdir -p "${VM_CONFIG_DIR}"
    mkdir -p "${VM_IMAGE_DIR}"
    mkdir -p "${VM_SHARED_DIR}"
    mkdir -p "${VM_LOG_DIR}"
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
detect_dependencies
init_directories

# If arguments provided, handle them
if [ $# -gt 0 ]; then
    case "$1" in
        create)
            if [ -n "$2" ]; then create_vm "$2"; else die "Usage: $0 create VMNAME"; fi
            ;;
        start)
            if [ -n "$2" ]; then start_qemu_vm "$2"; else die "Usage: $0 start VMNAME"; fi
            ;;
        edit)
            if [ -n "$2" ]; then edit_vm "$2"; else die "Usage: $0 edit VMNAME"; fi
            ;;
        stop)
            if [ -n "$2" ]; then stop_vm "$2"; else die "Usage: $0 stop VMNAME"; fi
            ;;
        delete)
            if [ -n "$2" ]; then delete_vm "$2"; else die "Usage: $0 delete VMNAME"; fi
            ;;
        list)
            list_vms
            ;;
        insert_iso)
            if [ -n "$2" ]; then insert_iso "$2"; else die "Usage: $0 insert_iso VMNAME"; fi
            ;;
        eject_iso)
            if [ -n "$2" ]; then eject_iso "$2"; else die "Usage: $0 eject_iso VMNAME"; fi
            ;;
        validate)
            if [ -n "$2" ]; then validate_vm_config "$2"; else die "Usage: $0 validate VMNAME"; fi
            ;;
        export)
            if [ -n "$2" ]; then export_utm "$2"; else die "Usage: $0 export VMNAME"; fi
            ;;
        build)
            if [ -f "${SCRIPT_DIR}/build_qemu.sh" ]; then
                "${SCRIPT_DIR}/build_qemu.sh" all
            else
                die "build_qemu.sh not found"
            fi
            ;;
        menu|"")
            show_main_menu
            ;;
        *)
            echo "Usage: $0 {create|start|edit|stop|delete|list|insert_iso|eject_iso|validate|export|build|menu} [VMNAME]"
            exit 1
            ;;
    esac
else
    show_main_menu
fi
