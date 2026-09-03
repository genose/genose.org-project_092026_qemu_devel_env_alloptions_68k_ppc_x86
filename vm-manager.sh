#!/usr/bin/env bash
# shellcheck disable=SC2054  # QEMU flags legitimately contain commas
# =============================================================================
# vm-manager.sh — UNIFIED VM Management Tool
# 
# ONE TOOL TO RULE THEM ALL:
#   ✓ Build QEMU with all retro targets + patches
#   ✓ Manage VMs (create, launch, stop, delete, configure)
#   ✓ Support for 14+ architectures (68k, PPC, x86, SPARC, ARM)
#   ✓ ISO/ROM management with dynamic discovery
#   ✓ Display backend auto-detection (cocoa, sdl, gtk, vnc)
#   ✓ GDB debugging integration
#   ✓ Network sharing (Samba, Netatalk, 9P)
#   ✓ Multi-screen support
#   ✓ SPICE support
#   ✓ UTM.app integration (macOS)
#
# Target: Complete retro & modern DEV environment
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Global Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Directories
CONFIG_DIR="${HOME}/vm_assistant"
VM_CONFIG_DIR="${SCRIPT_DIR}/vm-configs"
PATCHES_DIR="${SCRIPT_DIR}/patches"
QEMU_PREFIX="${QEMU_PREFIX:-${HOME}/.local/qemu-retro}"
QEMU_BIN_DIR="${QEMU_BIN_DIR:-${QEMU_PREFIX}/bin}"
QEMU_SRC_DIR="${QEMU_SRC_DIR:-${SCRIPT_DIR}/qemu-9.2.0}"
QEMU_BUILD_DIR="${QEMU_BUILD_DIR:-${QEMU_SRC_DIR}/build}"

# VM storage - Enhanced bundled directory structure
# VMs are stored as: ${CONFIG_DIR}/vms/${VM_NAME}_${PLATFORM}/ 
# Each VM directory contains subdirectories: conf/, qcow2/, sh/, rom/
VM_DIR="${CONFIG_DIR}/vms"
DISK_DIR="${VM_DIR}"  # Disks are now bundled within VM directories
ISO_DIR="${CONFIG_DIR}/isos"
SHARE_DIR="${CONFIG_DIR}/shares"
ROM_DIR="${CONFIG_DIR}/roms"
VM_IMAGE_DIR="${VM_IMAGE_DIR:-${HOME}/vm_assistant/images}"
VM_SHARED_DIR="${VM_SHARED_DIR:-${HOME}/vm_assistant/shares}"
VM_LOG_DIR="${VM_LOG_DIR:-${HOME}/vm_assistant/logs}"

# Defaults
DEFAULT_RAM_MB="${DEFAULT_RAM_MB:-256}"
DEFAULT_DISPLAY=""  # Auto-detected
QEMU_VERSION="${QEMU_VERSION:-9.2.0}"
QEMU_X86_COMPAT_CFLAGS="${QEMU_X86_COMPAT_CFLAGS:--march=x86-64 -mtune=westmere -mno-avx -mno-avx2}"

# Ports
DEFAULT_GDB_PORT=1234
DEFAULT_GDB_BRIDGE_PORT=2346
DEFAULT_GDB_GUEST_PORT=2345
DEFAULT_QEMU_GDB_PORT=1234
DEFAULT_SSH_PORT=2222
DEFAULT_NETATALK_PORT=548
DEFAULT_SPICE_PORT=5900
DEFAULT_VNC_PORT=5901
DEFAULT_AFP_HOST="10.0.2.2"
DEFAULT_AFP_PORT=548
DEFAULT_TLS_PROXY_HOST="10.0.2.2"
DEFAULT_TLS_PROXY_PORT=8443
DEFAULT_MACOS_SHARE_DIR="${HOME}/vm_assistant/shares"

# ---------------------------------------------------------------------------
# Colour Helpers
# ---------------------------------------------------------------------------
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_MAGENTA='\033[1;35m'
C_BLUE='\033[0;34m'

log()     { printf "${C_GREEN}[${SCRIPT_NAME}]${C_RESET} %s\n" "$*"; }
warn()    { printf "${C_YELLOW}[${SCRIPT_NAME}] WARN:${C_RESET} %s\n" "$*" >&2; }
die()     { printf "${C_RED}[${SCRIPT_NAME}] ERROR:${C_RESET} %s\n" "$*" >&2; exit 1; }
heading() { printf "\n${C_CYAN}${C_BOLD}=== %s ===${C_RESET}\n\n" "$*"; }

# ---------------------------------------------------------------------------
# Exception Handling Framework (Bash)
# ---------------------------------------------------------------------------

# Global exception handler variables
EXCEPTION_HANDLER_ENABLED=true
EXCEPTION_MESSAGES=()
EXCEPTION_CONTEXT=()

# Exception types
declare -A EXCEPTION_TYPES=(
    [ERR_ERROR]=1
    [ERR_WARNING]=2  
    [ERR_VALIDATION]=3
    [ERR_DEPENDENCY]=4
    [ERR_CONFIGURATION]=5
    [ERR_FILESYSTEM]=6
    [ERR_NETWORK]=7
    [ERR_PERMISSION]=8
    [ERR_NOT_FOUND]=9
    [ERR_ALREADY_EXISTS]=10
)

# Exception handler - can be overridden for specific use cases
handle_exception() {
    local exit_code="$1"
    local message="$2"
    local context="$3"
    local exception_type="${4:-${EXCEPTION_TYPES[ERR_ERROR]}}"
    
    # Log the exception
    case "$exception_type" in
        ${EXCEPTION_TYPES[ERR_ERROR]})
            die "${message}"
            ;;
        ${EXCEPTION_TYPES[ERR_WARNING]})
            warn "${message}"
            ;;
        ${EXCEPTION_TYPES[ERR_VALIDATION]})
            die "[VALIDATION] ${message}"
            ;;
        ${EXCEPTION_TYPES[ERR_DEPENDENCY]})
            die "[DEPENDENCY] ${message}. Please install: ${context}"
            ;;
        ${EXCEPTION_TYPES[ERR_CONFIGURATION]})
            die "[CONFIG] ${message}. Check: ${context}"
            ;;
        ${EXCEPTION_TYPES[ERR_FILESYSTEM]})
            die "[FILESYSTEM] ${message}. Path: ${context}"
            ;;
        ${EXCEPTION_TYPES[ERR_NETWORK]})
            die "[NETWORK] ${message}. URL: ${context}"
            ;;
        ${EXCEPTION_TYPES[ERR_PERMISSION]})
            die "[PERMISSION] ${message}. Need: ${context}"
            ;;
        ${EXCEPTION_TYPES[ERR_NOT_FOUND]})
            die "[NOT_FOUND] ${message}. Searched: ${context}"
            ;;
        ${EXCEPTION_TYPES[ERR_ALREADY_EXISTS]})
            die "[EXISTS] ${message}. Path: ${context}"
            ;;
        *)
            die "[EXCEPTION:${exception_type}] ${message}"
            ;;
    esac
}

# Throw an exception with type and context
throw() {
    local message="$1"
    local context="${2:-}"
    local exception_type="${3:-${EXCEPTION_TYPES[ERR_ERROR]}}"
    
    if ${EXCEPTION_HANDLER_ENABLED:-true}; then
        handle_exception "$exception_type" "$message" "$context" "$exception_type"
    else
        die "$message"
    fi
}

# Validation exception
validate_or_throw() {
    local condition="$1"
    local message="$2"
    local context="${3:-}"
    
    if ! eval "$condition"; then
        throw "$message" "$context" "${EXCEPTION_TYPES[ERR_VALIDATION]}"
    fi
}

# Dependency check exception
dependency_or_throw() {
    local command="$1"
    local message="$2"
    local install_hint="${3:-$command}"
    
    if ! command -v "$command" &>/dev/null; then
        throw "$message" "$install_hint" "${EXCEPTION_TYPES[ERR_DEPENDENCY]}"
    fi
}

# File exists check with exception
file_exists_or_throw() {
    local file_path="$1"
    local message="$2"
    
    if [[ ! -e "$file_path" ]]; then
        throw "$message" "$file_path" "${EXCEPTION_TYPES[ERR_NOT_FOUND]}"
    fi
}

# Directory exists check with exception
dir_exists_or_throw() {
    local dir_path="$1"
    local message="$2"
    
    if [[ ! -d "$dir_path" ]]; then
        throw "$message" "$dir_path" "${EXCEPTION_TYPES[ERR_NOT_FOUND]}"
    fi
}

# File writable check with exception
writable_or_throw() {
    local path="$1"
    local message="$2"
    
    if [[ ! -w "$path" ]]; then
        throw "$message" "$path" "${EXCEPTION_TYPES[ERR_PERMISSION]}"
    fi
}

# Try/catch/finally simulation using functions
# Usage:
#   try_execute \
#       command1 \
#       command2 \
#       "catch_handler" \
#       "finally_handler"
#
# Or simpler pattern with error checking:
#   if ! try_execute command1 command2; then
#       catch_handler
#   fi

# Execute commands with error handling
# Returns 0 on success, 1 on error
# Sets LAST_EXCEPTION and LAST_EXCEPTION_CONTEXT on error
LAST_EXCEPTION=""
LAST_EXCEPTION_CONTEXT=""

try_execute() {
    local commands=("$@")
    local last_command=""
    local exit_code=0
    
    # Execute all commands except last two (catch and finally handlers)
    local command_count=${#commands[@]}
    local catch_handler=""
    local finally_handler=""
    
    if [[ $command_count -ge 1 ]]; then
        # Last two arguments are catch and finally handlers (if provided)
        if [[ $command_count -ge 3 && "${commands[$((command_count-2))]}" == "catch" ]]; then
            finally_handler="${commands[$((command_count-1))]}"
            catch_handler="${commands[$((command_count-2))]}"
            command_count=$((command_count - 2))
        elif [[ $command_count -ge 2 && "${commands[$((command_count-1))]}" == "catch" ]]; then
            catch_handler="${commands[$((command_count-1))]}"
            command_count=$((command_count - 1))
        fi
        
        # Execute commands
        for ((i=0; i<command_count; i++)); do
            last_command="${commands[$i]}"
            if ! eval "${commands[$i]}"; then
                exit_code=1
                LAST_EXCEPTION="Command failed: ${last_command}"
                LAST_EXCEPTION_CONTEXT="${BASH_SOURCE[1]}:${BASH_LINENO[0]}"
                
                # Execute catch handler if provided
                if [[ -n "$catch_handler" && "$catch_handler" != "catch" ]]; then
                    # Call catch handler with exception details
                    "$catch_handler" "$LAST_EXCEPTION" "$LAST_EXCEPTION_CONTEXT"
                fi
                
                # Execute finally handler if provided
                if [[ -n "$finally_handler" && "$finally_handler" != "finally" ]]; then
                    "$finally_handler"
                fi
                
                return $exit_code
            fi
        done
        
        # Execute finally handler on success too
        if [[ -n "$finally_handler" && "$finally_handler" != "finally" ]]; then
            "$finally_handler"
        fi
    fi
    
    return 0
}

# Enable/disable exception handling globally
enable_exceptions() {
    EXCEPTION_HANDLER_ENABLED=true
    TRY_CATCH_ENABLED=true
    set -euo pipefail
}

disable_exceptions() {
    EXCEPTION_HANDLER_ENABLED=false
    TRY_CATCH_ENABLED=false
    set +euo pipefail
}

# =============================================================================
# EXCEPTION HANDLING USAGE EXAMPLES
# =============================================================================
#
# 1. Basic exception throwing:
#    throw "Something went wrong" "context info" "${EXCEPTION_TYPES[ERR_ERROR]}"
#
# 2. Validation with exception:
#    validate_or_throw "[[ -f \"$file\" ]]" "File not found: $file"
#
# 3. Dependency check with exception:
#    dependency_or_throw "qemu-img" "QEMU utilities not found"
#
# 4. File system checks:
#    file_exists_or_throw "$config_file" "Configuration file missing"
#    dir_exists_or_throw "$vm_dir" "VM directory not found"
#    writable_or_throw "$output_file" "Output file not writable"
#
# 5. Try/catch/finally pattern:
#    cleanup() { log "Cleaning up... "; }
#    error_handler() { log "Error: $1"; }
#    try_execute \
#        "rm -rf $temp_dir" \
#        "mkdir -p $output_dir" \
#        "catch" error_handler \
#        "finally" cleanup
#
# 6. Nested exception handling:
#    try_execute \
#        "validate_or_throw '[[ -n \"$name\" ]]' 'VM name cannot be empty'" \
#        "dependency_or_throw 'qemu-system-$arch' 'QEMU $arch not available'" \
#        "catch" handle_validation_error
#
# =============================================================================

# ---------------------------------------------------------------------------
# QEMU Targets Configuration
# ---------------------------------------------------------------------------
QEMU_SOFTMMU_TARGETS=(
    m68k-softmmu       # Motorola 68000 (Amiga, Atari ST, Mac 68k)
    ppc-softmmu        # PowerPC 32-bit (MacOS 7.5-9.2.2)
    ppc64-softmmu      # PowerPC 64-bit (Mac OS X)
    i386-softmmu       # x86 32-bit (HaikuOS, DOS, early Windows)
    x86_64-softmmu     # x86 64-bit (HaikuOS, modern Linux)
    sparc-softmmu      # SPARC 32-bit
    sparc64-softmmu    # SPARC 64-bit
)

QEMU_LINUX_USER_TARGETS=(
    m68k-linux-user
    ppc-linux-user
    ppc64-linux-user
    i386-linux-user
    x86_64-linux-user
)

EXTRA_CONFIG_FLAGS=(
    --enable-slirp
    --enable-vnc
    --enable-sdl
    --enable-gtk
    --enable-curses
    --enable-audio-drv-list=alsa,pa,sdl,coreaudio,dsound
    --enable-bzip2
    --enable-lzo
    --enable-snappy
    --enable-libssh
    --enable-usb-redir
    --enable-smartcard
    --enable-opengl
    --enable-virtfs
    --enable-spice
)

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------

# Resolve QEMU binary path
qemu_bin() {
    local name="$1"
    local candidates=("${QEMU_BIN_DIR}/${name}" "$(command -v "${name}" 2>/dev/null || true)")
    for c in "${candidates[@]}"; do
        [[ -x "${c}" ]] && echo "${c}" && return 0
    done
    return 1
}

# Resolve QEMU binary path with error message
qemu_bin_or_die() {
    local name="$1"
    local result
    result=$(qemu_bin "${name}") || die "Cannot find '${name}'. Build QEMU first with '${SCRIPT_NAME} build' or set QEMU_BIN_DIR."
    echo "${result}"
}

# Detect available display backend
detect_display_backend() {
    local qemu_test="${1:-qemu-system-x86_64}"
    local qemu_bin_path
    qemu_bin_path=$(qemu_bin "${qemu_test}" 2>/dev/null) || return 1
    
    local preferred_backends=()
    case "$(uname -s)" in
        Darwin)   preferred_backends=("cocoa" "dbus" "spice" "vnc" "none" "curses") ;;
        Linux)    preferred_backends=("gtk" "sdl" "spice" "vnc" "curses" "none") ;;
        *)        preferred_backends=("sdl" "gtk" "spice" "vnc" "curses" "none") ;;
    esac
    
    for backend in "${preferred_backends[@]}"; do
        if "${qemu_bin_path}" -display help 2>&1 | grep -q "${backend}"; then
            DEFAULT_DISPLAY="${backend}"
            log "Detected display backend: ${DEFAULT_DISPLAY}"
            return 0
        fi
    done
    
    DEFAULT_DISPLAY="none"
    warn "No display backend detected, defaulting to: ${DEFAULT_DISPLAY}"
}

# Get available display backends for a specific QEMU binary
get_display_backends() {
    local qemu_test="${1:-qemu-system-x86_64}"
    local qemu_bin_path
    qemu_bin_path=$(qemu_bin "${qemu_test}" 2>/dev/null) || return 1
    
    "${qemu_bin_path}" -display help 2>&1 | grep -E "^\w+" | tr ',' '\n' | tr -d ' ' | sort -u
}

# Validate display backend for a specific QEMU binary
validate_display_backend() {
    local display="$1"
    local qemu_test="${2:-qemu-system-x86_64}"
    local qemu_bin_path
    
    qemu_bin_path=$(qemu_bin "${qemu_test}" 2>/dev/null) || return 1
    
    # Always allow these backends
    case "${display}" in
        none|curses) return 0 ;;
    esac
    
    # Check if the backend is supported
    if "${qemu_bin_path}" -display help 2>&1 | grep -q "${display}"; then
        return 0
    fi
    
    return 1
}

# Ensure directory exists
ensure_dir() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

# Ask user for input with default
ask() {
    local prompt="$1" default="$2" answer
    
    # Non-interactive mode: return default immediately
    if ! is_interactive; then
        echo "${default}"
        return
    fi
    
    read -rp "$(printf '%b%s%b [%s]: ' "${C_BOLD}" "${prompt}" "${C_RESET}" "${default}")" answer
    echo "${answer:-${default}}"
}

# Ask for yes/no
is_yes() {
    case "${1,,}" in
        y|yes|true|1|on) return 0 ;;
        *) return 1 ;;
    esac
}

# Trim spaces
trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]} "}"
    echo "${value}"
}

# Merge CSV values
merge_csv_values() {
    local first second
    first=$(trim "${1:-}")
    second=$(trim "${2:-}")
    if [[ -n "${first}" && -n "${second}" ]]; then
        echo "${first},${second}"
    elif [[ -n "${first}" ]]; then
        echo "${first}"
    else
        echo "${second}"
    fi
}

# File size in bytes
file_size_bytes() {
    local path="$1"
    if stat -c '%s' "${path}" &>/dev/null; then
        stat -c '%s' "${path}"
    elif stat -f '%z' "${path}" &>/dev/null; then
        stat -f '%z' "${path}"
    else
        echo 0
    fi
}

# Check if running in an interactive terminal
is_interactive() {
    # Check if stdin is connected to a terminal
    if [[ -t 0 ]]; then
        return 0
    fi
    # Check if we're running in a terminal
    if [[ -t 1 ]]; then
        return 0
    fi
    return 1
}

# Ask for RAM size with validation (supports plain MiB or M/G suffixes)
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

# Pick a disk image from platform directory
pick_image() {
    local platform="$1"
    local start_dir=""
    
    # Non-interactive mode: use default directory and auto-scan
    if ! is_interactive; then
        start_dir="${VM_IMAGE_DIR}/${platform}"
        mkdir -p "${start_dir}" 2>/dev/null || true
        
        # Auto-select first disk image
        local images=()
        while IFS= read -r -d $'\0' f; do
            images+=("$f")
        done < <(find "${start_dir}" -maxdepth 1 \( -name '*.img' -o -name '*.qcow2' -o -name '*.iso' -o -name '*.dsk' -o -name '*.hda' \) -print0 2>/dev/null | sort -z)
        
        if [[ ${#images[@]} -eq 0 ]]; then
            warn "No disk images found in ${start_dir}"
            echo ""
            return
        fi
        
        # Return first image found
        log "Auto-selected: $(basename "${images[0]}")"
        echo "${images[0]}"
        return
    else
        # Enhanced UX: Ask user which directory to start with
        read -rp "Enter directory to scan for disk images [${VM_IMAGE_DIR}/${platform}]: " start_dir
        start_dir="${start_dir:-${VM_IMAGE_DIR}/${platform}}"
        
        # Validate directory exists and user wants to proceed
        if [[ ! -d "${start_dir}" ]]; then
            warn "Directory does not exist: ${start_dir}"
            read -rp "Do you want to navigate to another directory? (y/n) [y]: " navigate_choice
            navigate_choice="${navigate_choice:-y}"
            if [[ "${navigate_choice}" =~ ^[yY] ]]; then
                pick_image "${platform}"
            fi
            return 1
        fi
        
        read -rp "Scan directory ${start_dir} for disk images? (y/n) [y]: " confirm_scan
        confirm_scan="${confirm_scan:-y}"
        
        if [[ "${confirm_scan}" != "y" ]]; then
            return 0
        fi
        
        mkdir -p "${start_dir}" 2>/dev/null || true
        
        local images=()
        while IFS= read -r -d $'\0' f; do
            images+=("$f")
        done < <(find "${start_dir}" -maxdepth 1 \( -name '*.img' -o -name '*.qcow2' -o -name '*.iso' -o -name '*.dsk' -o -name '*.hda' \) -print0 2>/dev/null | sort -z)

        if [[ ${#images[@]} -eq 0 ]]; then
            warn "No disk images found in ${start_dir}"
            local create
            create=$(ask "Create a new blank 2 GiB image? (yes/no)" "yes")
            if is_yes "${create}"; then
                local imgname
                imgname=$(ask "Image filename" "${platform}-disk.qcow2")
                local size
                size=$(ask "Image size (e.g. 512M, 2G)" "2G")
                "$(qemu_bin qemu-img 2>/dev/null || echo qemu-img)" create -f qcow2 "${start_dir}/${imgname}" "${size}"
                echo "${start_dir}/${imgname}"
            else
                echo ""
            fi
            return
        fi

        printf '\n%s Available disk images:\n' "${C_BOLD}"
        local i=0
        for img in "${images[@]}"; do
            printf '  %d) %s\n' "$((++i))" "$(basename "${img}")"
        done
        printf '%s\n' "${C_RESET}"

        local choice
        choice=$(ask "Select image number" "1")
        if [[ ! "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#images[@]} )); then
            warn "Invalid image selection '${choice}'"
            echo ""
        else
            echo "${images[$((choice - 1))]}"
        fi
        
        # Allow navigation to other directories (only in interactive mode)
        read -rp "Scan another directory? (y/n) [n]: " scan_another
        scan_another="${scan_another:-n}"
        if [[ "${scan_another}" =~ ^[yY] ]]; then
            pick_image "${platform}"
        fi
    fi
}

# Pick a CDROM/ISO image
pick_cdrom() {
    local platform="$1"
    local start_dir=""
    
    # Non-interactive mode: use default directory and auto-scan
    if ! is_interactive; then
        start_dir="${VM_IMAGE_DIR}/${platform}"
        mkdir -p "${start_dir}" 2>/dev/null || true
        
        # Auto-select first ISO image
        local isos=()
        while IFS= read -r -d $'\0' f; do
            isos+=("$f")
        done < <(find "${start_dir}" -maxdepth 2 \( -name '*.iso' -o -name '*.ISO' -o -name '*.img' -o -name '*.IMG' -o -name '*.dmg' -o -name '*.DMG' \) -print0 2>/dev/null | sort -z)
        
        if [[ ${#isos[@]} -eq 0 ]]; then
            warn "No ISO/CD images found in ${start_dir}"
            echo ""
            return
        fi
        
        # Return first ISO found
        log "Auto-selected: $(basename "${isos[0]}")"
        echo "${isos[0]}"
        return
    else
        # Enhanced UX: Ask user which directory to start with
        read -rp "Enter directory to scan for ISO images [${VM_IMAGE_DIR}/${platform}]: " start_dir
        start_dir="${start_dir:-${VM_IMAGE_DIR}/${platform}}"
        
        # Validate directory exists and user wants to proceed
        if [[ ! -d "${start_dir}" ]]; then
            warn "Directory does not exist: ${start_dir}"
            read -rp "Do you want to navigate to another directory? (y/n) [y]: " navigate_choice
            navigate_choice="${navigate_choice:-y}"
            if [[ "${navigate_choice}" =~ ^[yY] ]]; then
                pick_cdrom "${platform}"
            fi
            return 1
        fi
        
        read -rp "Scan directory ${start_dir} for ISO images? (y/n) [y]: " confirm_scan
        confirm_scan="${confirm_scan:-y}"
        
        if [[ "${confirm_scan}" != "y" ]]; then
            log "ISO scan cancelled."
            return 0
        fi
        
        mkdir -p "${start_dir}" 2>/dev/null || true
        
        local isos=()
        while IFS= read -r -d $'\0' f; do
            isos+=("$f")
        done < <(find "${start_dir}" -maxdepth 2 \( -name '*.iso' -o -name '*.ISO' -o -name '*.img' -o -name '*.IMG' -o -name '*.dmg' -o -name '*.DMG' \) -print0 2>/dev/null | sort -z)

        if [[ ${#isos[@]} -eq 0 ]]; then
            warn "No ISO/CD images found in ${start_dir}"
            local manual_path
            manual_path=$(ask "Enter full path to ISO (or leave blank to skip)" "")
            echo "${manual_path}"
            return
        fi

        printf '\n%s Available CD/ISO images:\n' "${C_BOLD}"
        printf '  0) None / skip\n'
        local i=0
        for iso in "${isos[@]}"; do
            printf '  %d) %s\n' "$((++i))" "$(basename "${iso}")"
        done
        printf '%s\n' "${C_RESET}"

        local choice
        choice=$(ask "Select ISO number" "0")
        if [[ "${choice}" == "0" || -z "${choice}" ]]; then
            echo ""
        elif [[ ! "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#isos[@]} )); then
            warn "Invalid ISO selection '${choice}'"
            echo ""
        else
            echo "${isos[$((choice - 1))]}"
        fi
        
        # Allow navigation to other directories (only in interactive mode)
        read -rp "Scan another directory? (y/n) [n]: " scan_another
        scan_another="${scan_another:-n}"
        if [[ "${scan_another}" =~ ^[yY] ]]; then
            pick_cdrom "${platform}"
        fi
    fi
}

# Prepare MacOS integration (shared dir, clipboard, AFP, TLS)
prepare_macos_integration() {
    local share_dir="$1" afp_endpoint="$2" tls_endpoint="$3"
    local shared_dir clipboard_dir
    shared_dir=$(ensure_shared_dir "${share_dir}")
    clipboard_dir="${shared_dir}/clipboard"
    mkdir -p "${clipboard_dir}"

    log "Prepared Mac host share at ${shared_dir}"
    log "Clipboard exchange path: ${clipboard_dir}"
    log "Netatalk/AFP endpoint for the guest: ${afp_endpoint}"
    log "TLS proxy endpoint for the guest: ${tls_endpoint}"
    log "Package-manager note: classic Mac guests typically consume host services prepared via MacPorts or Homebrew."
}

# Append extra display devices (multi-screen support)
append_extra_display_devices() {
    local -n _display_cmd="$1"
    local spec
    spec=$(trim "${2:-}")
    [[ -n "${spec}" ]] || return 0

    local IFS=';'
    local -a devices=()
    read -r -a devices <<< "${spec}"

    local device
    for device in "${devices[@]}"; do
        device=$(trim "${device}")
        [[ -n "${device}" ]] || continue
        _display_cmd+=(-device "${device}")
    done
}

# Append firmware/ROM attachment
append_firmware_attachment() {
    local -n _firmware_cmd="$1"
    local firmware_path="$2"
    local firmware_mode="${3:-auto}"
    local firmware_label="${4:-firmware/ROM}"
    firmware_path=$(trim "${firmware_path}")
    firmware_mode="${firmware_mode,,}"

    [[ -n "${firmware_path}" ]] || return 0
    if [[ ! -f "${firmware_path}" ]]; then
        warn "Skipping ${firmware_label}: file not found: ${firmware_path}"
        return 0
    fi

    local resolved_mode="${firmware_mode}"
    case "${resolved_mode}" in
        ""|auto|bios|pflash|none) ;;
        *)
            warn "Unknown firmware mode '${firmware_mode}' for ${firmware_label}; using auto detection."
            resolved_mode="auto"
            ;;
    esac

    if [[ -z "${resolved_mode}" || "${resolved_mode}" == "auto" ]]; then
        local size_bytes
        size_bytes=$(file_size_bytes "${firmware_path}")
        if [[ "${size_bytes}" =~ ^[0-9]+$ ]] && (( size_bytes > 1048576 )); then
            resolved_mode="pflash"
            log "Firmware image > 1 MiB detected — attaching ${firmware_label} via pflash."
        else
            resolved_mode="bios"
        fi
    fi

    case "${resolved_mode}" in
        bios)
            _firmware_cmd+=(-bios "${firmware_path}")
            ;;
        pflash)
            _firmware_cmd+=(-drive "if=pflash,format=raw,readonly=on,file=${firmware_path}")
            ;;
        none)
            ;;
    esac
}

# Append user network with port forwarding and SMB
append_user_network() {
    local -n _net_array="$1"
    local model="${2:-}"
    local forwards="${3:-}"
    local smb_dir="${4:-}"

    local nic="user"
    if [[ -n "${model}" ]]; then
        nic+=",model=${model}"
    fi
    if [[ -n "${smb_dir}" ]]; then
        nic+=",smb=${smb_dir}"
    fi

    if [[ -n "${forwards}" ]]; then
        local -a pairs
        local pair host guest
        IFS=',' read -r -a pairs <<<"${forwards}"
        for pair in "${pairs[@]}"; do
            pair=$(trim "${pair}")
            [[ -z "${pair}" ]] && continue
            if [[ "${pair}" =~ ^([0-9]+):([0-9]+)$ ]]; then
                host="${BASH_REMATCH[1]}"
                guest="${BASH_REMATCH[2]}"
                nic+=",hostfwd=tcp::${host}-:${guest}"
            else
                warn "Ignoring invalid TCP forward '${pair}' (expected hostPort:guestPort)."
            fi
        done
    fi

    _net_array=(-nic "${nic}")
}

# Ask for TCP port forwards
ask_port_forwards() {
    local default_value="${1:-}"
    ask "TCP forwards host:guest (comma-separated, blank to skip)" "${default_value}"
}

# Ask for GDB bridge forward
ask_gdb_bridge_forward() {
    local default_port="${1:-${DEFAULT_GDB_PORT}}"
    local enable
    enable=$(ask "Expose a guest GDB/gdbserver bridge? (yes/no)" "no")
    if ! is_yes "${enable}"; then
        echo ""
        return
    fi

    local host_port guest_port
    host_port=$(ask "Host TCP port for the GDB bridge" "${default_port}")
    guest_port=$(ask "Guest TCP port for gdbserver" "${DEFAULT_GDB_GUEST_PORT}")
    echo "${host_port}:${guest_port}"
}

# QEMU GDB stub flags
qemu_gdb_flags() {
    local -n _dbg_array="$1"
    local enable
    enable=$(ask "Expose the QEMU GDB stub? (yes/no)" "no")
    if ! is_yes "${enable}"; then
        _dbg_array=()
        return
    fi

    local gdb_port wait
    gdb_port=$(ask "QEMU GDB stub TCP port" "${DEFAULT_QEMU_GDB_PORT}")
    wait=$(ask "Pause CPUs at startup for debugger attach? (yes/no)" "no")

    _dbg_array=(-gdb "tcp::${gdb_port}")
    if is_yes "${wait}"; then
        _dbg_array+=(-S)
    fi
}

# Display/audio flags generator
display_flags() {
    local -n _df_array="$1"
    local display="${2:-${DEFAULT_DISPLAY}}"
    
    # If display is empty or not set, try to detect it
    if [[ -z "${display}" || "${display}" == "" ]]; then
        detect_display_backend "${3:-qemu-system-x86_64}"
        display="${DEFAULT_DISPLAY}"
    fi
    
    # Validate the display backend for the target QEMU
    local qemu_target="${3:-qemu-system-x86_64}"
    if ! validate_display_backend "${display}" "${qemu_target}"; then
        warn "Display backend '${display}' is not supported by ${qemu_target}. Falling back to detected default."
        detect_display_backend "${qemu_target}"
        display="${DEFAULT_DISPLAY}"
    fi
    
    case "${display}" in
        sdl)    _df_array=(-display sdl    -audiodev sdl,id=snd0)  ;;
        gtk)    _df_array=(-display gtk    -audiodev pa,id=snd0)   ;;
        cocoa)  _df_array=(-display cocoa  -audiodev coreaudio,id=snd0) ;;
        vnc)    _df_array=(-display vnc=:0 -audiodev none,id=snd0) ;;
        spice)  _df_array=(-spice port=${DEFAULT_SPICE_PORT},disable-ticketing -audiodev spice,id=snd0) ;;
        curses) _df_array=(-display curses -audiodev none,id=snd0) ;;
        none)   _df_array=(-display none   -audiodev none,id=snd0) ;;
        *)      _df_array=(-display "${display}" -audiodev none,id=snd0) ;;
    esac
}

# CPU selection helpers
ask_m68k_cpu() {
    local default_cpu="${1:-m68040}"
    ask "68k CPU (m68000/m68010/m68020/m68030/m68040)" "${default_cpu}"
}

ask_ppc_cpu() {
    local default_cpu="${1:-7455}"
    ask "PowerPC CPU (601/604/7455)" "${default_cpu}"
}

# Ask for SMP topology
ask_ppc_smp() {
    local default_sockets="${1:-1}" default_cores="${2:-1}"
    local sockets cores
    sockets=$(ask "CPU sockets (1 = single, 2 = dual like G4 MDD / G5 Dual)" "${default_sockets}")
    cores=$(ask "Cores per socket" "${default_cores}")
    local total=$(( sockets * cores ))
    printf '%d,sockets=%d,cores=%d' "${total}" "${sockets}" "${cores}"
}

# Config path helper
config_path() {
    local name="$1"
    echo "${VM_CONFIG_DIR}/${name}.env"
}

# Ensure shared directory exists
ensure_shared_dir() {
    local path="${1:-${VM_SHARED_DIR}}"
    mkdir -p "${path}"
    echo "${path}"
}

# Initialize all required directories
init_directories() {
    heading "Initializing VM Assistant Directories"
    
    local dirs=(
        "${CONFIG_DIR}"
        "${VM_CONFIG_DIR}"
        "${VM_DIR}"
        "${DISK_DIR}"
        "${ISO_DIR}"
        "${VM_IMAGE_DIR}"
        "${VM_SHARED_DIR}"
        "${VM_LOG_DIR}"
        "${ROM_DIR}"
        "${SHARE_DIR}"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            log "Creating directory: ${dir}"
            mkdir -p "${dir}"
        else
            log "Directory exists: ${dir}"
        fi
    done
    
    log "All directories initialized successfully"
}

# Find qemu-img binary
qemu_img_bin() {
    local name="qemu-img"
    local candidates=("${QEMU_BIN_DIR}/${name}" "$(command -v "${name}" 2>/dev/null || true)")
    for c in "${candidates[@]}"; do
        [[ -x "${c}" ]] && echo "${c}" && return 0
    done
    return 1
}

# Check if QEMU has a specific feature
qemu_has_feature() {
    local feature="$1"
    local qemu_test="${2:-qemu-system-x86_64}"
    local qemu_bin_path
    
    qemu_bin_path=$(qemu_bin "${qemu_test}") || return 1
    
    case "${feature}" in
        slirp)    "${qemu_bin_path}" -device help 2>&1 | grep -q "slirp" ;;
        vnc)      "${qemu_bin_path}" -display help 2>&1 | grep -q "vnc" ;;
        sdl)      "${qemu_bin_path}" -display help 2>&1 | grep -q "sdl" ;;
        gtk)      "${qemu_bin_path}" -display help 2>&1 | grep -q "gtk" ;;
        spice)    "${qemu_bin_path}" -spice help 2>&1 | grep -q "spice" ;;
        virgl)    "${qemu_bin_path}" -device help 2>&1 | grep -q "virgl" ;;
        kvm)      [[ -e /dev/kvm ]] && "${qemu_bin_path}" -accel help 2>&1 | grep -q "kvm" ;;
        *)
            "${qemu_bin_path}" -device help 2>&1 | grep -qi "${feature}" || \
            "${qemu_bin_path}" -display help 2>&1 | grep -qi "${feature}" || \
            return 1
            ;;
    esac
}

# Detect available QEMU capabilities
detect_qemu_capabilities() {
    log "Detecting QEMU capabilities..."
    
    local features=("slirp" "vnc" "sdl" "gtk" "spice" "virgl" "kvm")
    local available_features=()
    
    for feature in "${features[@]}"; do
        if qemu_has_feature "${feature}"; then
            available_features+=("${feature}")
            log "  ✓ ${feature}"
        else
            log "  ✗ ${feature} (not available)"
        fi
    done
    
    # Export detected features
    export DETECTED_QEMU_FEATURES="${available_features[*]}"
    
    return 0
}

# Detect system dependencies for VM management
detect_dependencies() {
    # Alias for verify_dependencies
    verify_dependencies "$@"
}

# ---------------------------------------------------------------------------
# Architecture Detection Functions (from build_qemu.sh)
# ---------------------------------------------------------------------------

# Check if host is x86 architecture
host_is_x86() {
    case "$(uname -m)" in
        x86_64|amd64|i386|i486|i586|i686) return 0 ;;
        *) return 1 ;;
    esac
}

# List all QEMU softmmu targets
list_all_softmmu_targets() {
    local targets_dir="${QEMU_SRC_DIR}/configs/targets"
    [[ -d "${targets_dir}" ]] || return 1

    find "${targets_dir}" -maxdepth 1 -type f -name '*-softmmu.mak' \
        -exec sh -c 'for file_path in "$@"; do basename "$file_path" .mak; done' sh {} + \
        | sort
}

# Resolve QEMU targets based on host architecture
resolve_qemu_targets() {
    local targets=()

    if host_is_x86; then
        if mapfile -t targets < <(list_all_softmmu_targets) && [[ ${#targets[@]} -gt 0 ]]; then
            log "x86 host detected — enabling all qemu-system-* targets."
        else
            warn "Could not enumerate all softmmu targets from ${QEMU_SRC_DIR}; falling back to retro defaults."
            targets=("${QEMU_SOFTMMU_TARGETS[@]}")
        fi
    else
        targets=("${QEMU_SOFTMMU_TARGETS[@]}")
    fi

    if [[ "$(uname -s)" == "Linux" ]]; then
        targets+=("${QEMU_LINUX_USER_TARGETS[@]}")
    fi

    printf '%s\n' "${targets[@]}"
}

# Configure x86 compatibility flags for older macOS
configure_x86_compat() {
    host_is_x86 || return 0
    [[ -n "${QEMU_X86_COMPAT_CFLAGS}" ]] || return 0

    export CFLAGS="${CFLAGS:+${CFLAGS} }${QEMU_X86_COMPAT_CFLAGS}"
    export CXXFLAGS="${CXXFLAGS:+${CXXFLAGS} }${QEMU_X86_COMPAT_CFLAGS}"
    log "Using x86 compatibility flags: ${QEMU_X86_COMPAT_CFLAGS}"
}

# ---------------------------------------------------------------------------
# QEMU Build Functions (from build_qemu.sh)

configure_x86_compat() {
    [[ "$(uname -m)" =~ x86_64|amd64|i386|i486|i586|i686 ]] || return 0
    [[ -n "${QEMU_X86_COMPAT_CFLAGS}" ]] || return 0
    export CFLAGS="${CFLAGS:+${CFLAGS} }${QEMU_X86_COMPAT_CFLAGS}"
    export CXXFLAGS="${CXXFLAGS:+${CXXFLAGS} }${QEMU_X86_COMPAT_CFLAGS}"
    log "Using x86 compatibility flags: ${QEMU_X86_COMPAT_CFLAGS}"
}

check_build_deps() {
    local missing=()
    local deps=(git curl tar make ninja pkg-config python3 gcc g++ flex bison)
    for d in "${deps[@]}"; do
        command -v "$d" &>/dev/null || missing+=("$d")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing build dependencies: ${missing[*]}"
        case "$(uname -s)" in
            Linux)
                warn "On Debian/Ubuntu: sudo apt-get install build-essential git ninja-build pkg-config python3-pip libglib2.0-dev libpixman-1-dev libsdl2-dev libgtk-3-dev libvte-2.91-dev libslirp-dev libbz2-dev liblzo2-dev libsnappy-dev libssh-dev libusbredirhost-dev libcacard-dev libepoxy-dev libncurses-dev libspice-server-dev libspice-protocol-dev"
                ;;
            Darwin)
                warn "On macOS: brew install ninja pkg-config glib pixman sdl2 gtk+3 libslirp spice-protocol spice-gtk"
                ;;
            *)
                warn "On Fedora/RHEL: sudo dnf install @development-tools ninja-build glib2-devel pixman-devel SDL2-devel gtk3-devel slirp-devel bzip2-devel lzo-devel snappy-devel libssh-devel usbredir-devel openssl-devel spice-protocol spice-server-devel"
                ;;
        esac
        die "Install the missing dependencies before continuing."
    fi
}

download_qemu() {
    if [[ -d "${QEMU_SRC_DIR}" ]]; then
        if [[ -f "${QEMU_SRC_DIR}/.git" || -d "${QEMU_SRC_DIR}/.git" ]]; then
            log "Source directory exists (submodule): ${QEMU_SRC_DIR}"
            local repo_root
            repo_root=$(git -C "${QEMU_SRC_DIR}" rev-parse --show-superproject-working-tree 2>/dev/null || true)
            [[ -n "${repo_root}" ]] && git -C "${repo_root}" submodule update --init -- "${QEMU_SRC_DIR}"
        fi
        return 0
    fi
    log "Downloading QEMU ${QEMU_VERSION}..."
    local tarball="qemu-${QEMU_VERSION}.tar.xz"
    curl -fL --progress-bar -o "/tmp/${tarball}" "https://download.qemu.org/${tarball}"
    log "Extracting tarball..."
    tar -xf "/tmp/${tarball}" -C "$(dirname "${QEMU_SRC_DIR}")"
    rm -f "/tmp/${tarball}"
}

apply_patches() {
    [[ -d "${QEMU_SRC_DIR}" ]] || die "Source directory not found: ${QEMU_SRC_DIR}. Run download first."
    [[ -d "${PATCHES_DIR}" ]] || { log "No patches directory; skipping."; return 0; }
    
    local subdirs=("general" "m68k" "ppc" "sparc")
    local all_patches=()
    
    for sub in "${subdirs[@]}"; do
        [[ -d "${PATCHES_DIR}/${sub}" ]] && {
            while IFS= read -r -d '' p; do
                all_patches+=("${p}")
            done < <(find "${PATCHES_DIR}/${sub}" -maxdepth 1 -name "*.patch" -print0 | sort -z)
        }
    done
    
    while IFS= read -r -d '' p; do
        all_patches+=("${p}")
    done < <(find "${PATCHES_DIR}" -maxdepth 1 -name "*.patch" -print0 | sort -z)
    
    [[ ${#all_patches[@]} -eq 0 ]] && { log "No patches found; skipping."; return 0; }
    
    log "Applying ${#all_patches[@]} patch(es)..."
    local applied=0 skipped=0
    for patch in "${all_patches[@]}"; do
        local name=$(basename "${patch}")
        if git -C "${QEMU_SRC_DIR}" apply --check --reverse "${patch}" &>/dev/null; then
            log "  [already applied] ${name}"
            ((skipped++)) || true
            continue
        fi
        if git -C "${QEMU_SRC_DIR}" apply --check "${patch}" &>/dev/null; then
            git -C "${QEMU_SRC_DIR}" apply "${patch}" || die "Failed to apply: ${patch}"
            log "  [applied] ${name}"
            ((applied++)) || true
        else
            warn "  [skipped - does not apply] ${name}"
            ((skipped++)) || true
        fi
    done
    log "Patches: ${applied} applied, ${skipped} skipped."
}

configure_qemu() {
    log "Configuring QEMU..."
    [[ -d "${QEMU_SRC_DIR}" ]] || die "Source not found: ${QEMU_SRC_DIR}"
    mkdir -p "${QEMU_BUILD_DIR}"
    cd "${QEMU_BUILD_DIR}"
    
    local resolved_targets=()
    mapfile -t resolved_targets < <(resolve_qemu_targets)
    local target_list=$(printf '%s,' "${resolved_targets[@]}"); target_list="${target_list%,}"
    configure_x86_compat
    
    "${QEMU_SRC_DIR}/configure" \
        --prefix="${QEMU_INSTALL_PREFIX}" \
        --target-list="${target_list}" \
        "${EXTRA_CONFIG_FLAGS[@]}" \
        2>&1 | tee configure.log
}

build_qemu() {
    log "Building QEMU with $(nproc) parallel jobs..."
    cd "${QEMU_BUILD_DIR}"
    ninja -j"$(nproc)" 2>&1 | tee build.log
}

install_qemu() {
    log "Installing QEMU to ${QEMU_INSTALL_PREFIX}..."
    cd "${QEMU_BUILD_DIR}"
    ninja install 2>&1 | tee install.log
    log "Done. Add to PATH: export PATH=\"${QEMU_INSTALL_PREFIX}/bin:\">${PATH}\""
}

# ---------------------------------------------------------------------------
# VM Management Functions (from vm-assistant-unified.sh)
# ---------------------------------------------------------------------------

# Validate VM configuration
validate_vm_config() {
    local config_file="$1"
    [[ -f "$1" ]] || return 1
    
    local errors=0
    local warnings=0
    
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(trim "$key")
        value=$(trim "$value")
        
        case "$key" in
            QEMU_BIN)
                [[ -x "$value" || -x "$(command -v "$value" 2>/dev/null)" ]] || {
                    echo "ERROR: QEMU binary not found: ${value}"
                    ((errors++))
                }
                ;;
            HDD_IMAGE|CDROM_IMAGE|BIOS_FILE)
                [[ -f "$value" || -z "$value" ]] || {
                    echo "ERROR: File not found: ${key}=${value}"
                    ((errors++))
                }
                ;;
            RAM_MB)
                [[ "$value" =~ ^[0-9]+$ ]] || {
                    echo "ERROR: Invalid RAM value: ${value}"
                    ((errors++))
                }
                ;;
        esac
    done < "${config_file}"
    
    [[ $errors -eq 0 ]] && return 0 || return 1
}

# Edit Option C: Debug & Network settings for VM
edit_vm_option_c() {
    local config_file="$1"
    
    # Load current config if it exists
    if [[ -f "${config_file}" ]]; then
        source "${config_file}" 2>/dev/null || true
    fi
    
    heading "Option C: Debug & Network Settings"
    echo "Current settings:"
    echo "  GDB: ${ENABLE_GDB:-n} ${GDB_PORT:+port=$GDB_PORT}"
    echo "  SSH: ${ENABLE_SSH:-n} ${SSH_PORT:+port=$SSH_PORT}"
    echo "  Netatalk: ${ENABLE_NETATALK:-n} ${NETATALK_SHARE_NAME:+share=$NETATALK_SHARE_NAME}"
    echo ""
    
    # GDB Configuration
    local enable_gdb
    enable_gdb=$(ask "Enable GDB debugging" "${ENABLE_GDB:-n}")
    
    local gdb_port=""
    if [[ "$enable_gdb" == "y" ]]; then
        gdb_port=$(ask "GDB port" "${GDB_PORT:-${DEFAULT_GDB_PORT}}")
    fi
    
    # SSH Configuration
    local enable_ssh
    enable_ssh=$(ask "Enable SSH port forwarding" "${ENABLE_SSH:-n}")
    
    local ssh_port=""
    if [[ "$enable_ssh" == "y" ]]; then
        ssh_port=$(ask "SSH port (host side)" "${SSH_PORT:-${DEFAULT_SSH_PORT}}")
    fi
    
    # Netatalk Configuration
    local enable_netatalk
    enable_netatalk=$(ask "Enable Netatalk (AppleShare)" "${ENABLE_NETATALK:-n}")
    
    local netatalk_share_name=""
    local share_dir=""
    if [[ "$enable_netatalk" == "y" ]]; then
        netatalk_share_name=$(ask "Netatalk share name" "${NETATALK_SHARE_NAME:-VM_Share}")
        share_dir=$(ask "Share directory path" "${SHARED_DIR:-${DEFAULT_MACOS_SHARE_DIR}}")
    fi
    
    # Update configuration file
    local updates=(
        "ENABLE_GDB=${enable_gdb}"
        "GDB_PORT=${gdb_port}"
        "ENABLE_SSH=${enable_ssh}"
        "SSH_PORT=${ssh_port}"
        "ENABLE_NETATALK=${enable_netatalk}"
        "NETATALK_SHARE_NAME=${netatalk_share_name}"
        "SHARED_DIR=${share_dir}"
    )
    
    for update in "${updates[@]}"; do
        local key="${update%%=*}"
        local value="${update#*=}"
        if grep -q "^${key}=" "${config_file}" 2>/dev/null; then
            sed -i.bak "s|^${key}=.*|${key}=\"${value}\"|" "${config_file}"
        else
            echo "${key}=\"${value}\"" >> "${config_file}"
        fi
    done
    
    log "Option C settings updated successfully"
}

# Create a new VM configuration
create_vm_config() {
    local vm_name="$1"
    local platform="$2"
    
    # Validate required parameters
    validate_or_throw "[[ -n \"${vm_name}\" ]]" "VM name is required" "${EXCEPTION_TYPES[ERR_VALIDATION]}"
    validate_or_throw "[[ -n \"${platform}\" ]]" "Platform is required" "${EXCEPTION_TYPES[ERR_VALIDATION]}"
    
    # Enhanced bundled directory structure: ~/vm_assistant/vms/VM_NAME_PLATFORM/
    local vm_base_dir="${VM_DIR}/${vm_name}_${platform}"
    local config_dir="${vm_base_dir}/conf"
    local disk_dir="${vm_base_dir}/qcow2"
    local scripts_dir="${vm_base_dir}/sh"
    local roms_dir="${vm_base_dir}/rom"
    
    # Create directories with exception handling
    for dir in "${config_dir}" "${disk_dir}" "${scripts_dir}" "${roms_dir}"; do
        if ! ensure_dir "${dir}"; then
            throw "Failed to create directory: ${dir}" "${dir}" "${EXCEPTION_TYPES[ERR_FILESYSTEM]}"
        fi
    done
    
    local config_file="${config_dir}/${vm_name}.conf"
    
    # Copy template if available, with error handling
    if [[ -f "${VM_CONFIG_DIR}/${platform}.env" ]]; then
        if ! cp "${VM_CONFIG_DIR}/${platform}.env" "${config_file}" 2>/dev/null; then
            throw "Failed to copy template: ${VM_CONFIG_DIR}/${platform}.env" "${config_file}" "${EXCEPTION_TYPES[ERR_FILESYSTEM]}"
        fi
        log "Created VM config from template: ${config_file}"
    else
        # Create basic config with error handling
        local config_content="# VM Configuration: ${vm_name}
# Platform: ${platform}
QEMU_BIN=qemu-system-${platform}
MACHINE=pc
CPU=host
RAM_MB=2048
HDD_IMAGE=${disk_dir}/${vm_name}.qcow2
DISPLAY_BACKEND=${DEFAULT_DISPLAY}
NETWORK_MODEL=e1000

# Option C: Debug & Network Settings
ENABLE_GDB=n
GDB_PORT=${DEFAULT_GDB_PORT}
ENABLE_SSH=n
SSH_PORT=${DEFAULT_SSH_PORT}
ENABLE_NETATALK=n
NETATALK_SHARE_NAME=VM_${vm_name}
SHARED_DIR=${DEFAULT_MACOS_SHARE_DIR}"
        
        if ! echo "${config_content}" > "${config_file}" 2>/dev/null; then
            throw "Failed to write configuration file: ${config_file}" "${config_file}" "${EXCEPTION_TYPES[ERR_FILESYSTEM]}"
        fi
        log "Created basic VM config: ${config_file}"
    fi
    
    echo "${config_file}"
}

# Create a disk image
# Parameters: vm_name platform [disk_size] [disk_format]
# Creates disk in VM's qcow2 subdirectory: ~/vm_assistant/vms/VM_NAME_PLATFORM/qcow2/
create_disk() {
    local vm_name="$1"
    local platform="$2"
    local disk_size="${3:-40G}"
    local disk_format="${4:-qcow2}"
    
    # Use exception framework for validation
    validate_or_throw "[[ -n \"${platform}\" ]]" "Platform is required for create_disk" "${EXCEPTION_TYPES[ERR_VALIDATION]}"
    
    # Enhanced structure: VM_DIR/VM_NAME_PLATFORM/qcow2/
    local vm_dir="${VM_DIR}/${vm_name}_${platform}"
    local disk_dir="${vm_dir}/qcow2"
    local disk_path="${disk_dir}/${vm_name}.qcow2"
    
    # Ensure directory exists with exception handling
    if ! ensure_dir "${disk_dir}"; then
        throw "Failed to create disk directory: ${disk_dir}" "${disk_dir}" "${EXCEPTION_TYPES[ERR_FILESYSTEM]}"
    fi
    
    # Check for qemu-img dependency
    local qemu_img
    if ! qemu_img=$(qemu_bin "qemu-img" 2>/dev/null); then
        dependency_or_throw "qemu-img" "qemu-img not found. Install QEMU utilities" "${EXCEPTION_TYPES[ERR_DEPENDENCY]}"
    fi
    
    # Check if disk already exists
    if [[ -f "${disk_path}" ]]; then
        warn "Disk already exists: ${disk_path}"
        return 0
    fi
    
    # Create disk with exception handling
    log "Creating disk: ${disk_path} (${disk_size}, ${disk_format})"
    
    if ! "${qemu_img}" create -f "${disk_format}" "${disk_path}" "${disk_size}" 2>/dev/null; then
        # Clean up if disk creation failed
        if [[ ! -f "${disk_path}" && -d "${disk_dir}" ]]; then
            rmdir "${disk_dir}" 2>/dev/null || true
        fi
        throw "Failed to create disk image" "${disk_path}" "${EXCEPTION_TYPES[ERR_FILESYSTEM]}"
    fi
    
    log "Disk created successfully."
}

# List available ISOs
list_isos() {
    local start_dir=""
    
    # Non-interactive mode: use default directory and auto-scan
    if ! is_interactive; then
        start_dir="${ISO_DIR}"
        heading "Available ISOs in ${start_dir}"
        
        local found=0
        local iso_dirs=("${start_dir}")
        
        for dir in "${iso_dirs[@]}"; do
            [[ -d "${dir}" ]] || continue
            log "Directory: ${dir}"
            while IFS= read -r -d '' iso_file; do
                log "  ${found}) $(basename "${iso_file}") [${iso_file}]"
                ((found++)) || true
            done < <(find "${dir}" -maxdepth 1 -type f \( -name "*.iso" -o -name "*.ISO" -o -name "*.dmg" -o -name "*.DMG" \) -print0 2>/dev/null | sort -z)
        done
        
        [[ $found -eq 0 ]] && warn "No ISOs found in ${start_dir}"
    else
        # Interactive mode: ask user for input
        read -rp "Enter directory to scan for ISOs [${ISO_DIR}]: " start_dir
        start_dir="${start_dir:-${ISO_DIR}}"
        
        # Validate directory exists and user wants to proceed
        if [[ ! -d "${start_dir}" ]]; then
            warn "Directory does not exist: ${start_dir}"
            read -rp "Do you want to navigate to another directory? (y/n) [y]: " navigate_choice
            navigate_choice="${navigate_choice:-y}"
            if [[ "${navigate_choice}" =~ ^[yY] ]]; then
                list_isos
            fi
            return 1
        fi
        
        read -rp "Scan directory ${start_dir} for ISOs? (y/n) [y]: " confirm_scan
        confirm_scan="${confirm_scan:-y}"
        
        if [[ "${confirm_scan}" =~ ^[yY] ]]; then
            heading "Available ISOs in ${start_dir}"
            
            local found=0
            local iso_dirs=("${start_dir}")
            
            for dir in "${iso_dirs[@]}"; do
                [[ -d "${dir}" ]] || continue
                log "Directory: ${dir}"
                while IFS= read -r -d '' iso_file; do
                    log "  ${found}) $(basename "${iso_file}") [${iso_file}]"
                    ((found++)) || true
                done < <(find "${dir}" -maxdepth 1 -type f \( -name "*.iso" -o -name "*.ISO" -o -name "*.dmg" -o -name "*.DMG" \) -print0 2>/dev/null | sort -z)
            done
            
            [[ $found -eq 0 ]] && warn "No ISOs found in ${start_dir}"
            
            # Allow navigation to other directories (only in interactive mode)
            if is_interactive; then
                read -rp "Scan another directory? (y/n) [n]: " scan_another
                scan_another="${scan_another:-n}"
                if [[ "${scan_another}" =~ ^[yY] ]]; then
                    list_isos
                fi
            fi
        else
            log "ISO scan cancelled."
        fi
    fi
    
    return 0
}

# Select an ISO interactively
select_iso() {
    local choice start_dir=""
    
    # Non-interactive mode: use default directory
    if ! is_interactive; then
        start_dir="${ISO_DIR}"
    else
        # Enhanced UX: Ask user which directory to start with
        log "Select ISO file for VM"
        log "------------------------"
        read -rp "Enter directory to scan for ISOs [${ISO_DIR}]: " start_dir
        start_dir="${start_dir:-${ISO_DIR}}"
    fi
    
    # Validate directory exists
    if [[ ! -d "${start_dir}" ]]; then
        warn "Directory does not exist: ${start_dir}"
        
        # Non-interactive mode: just return error
        if ! is_interactive; then
            return 1
        else
            read -rp "Do you want to browse to another directory? (y/n) [y]: " navigate_choice
            navigate_choice="${navigate_choice:-y}"
            if [[ "${navigate_choice}" =~ ^[yY] ]]; then
                select_iso
                return $?
            else
                return 1
            fi
        fi
    fi
    
    # Non-interactive mode: auto-select first ISO if available
    if ! is_interactive; then
        local iso_files=()
        while IFS= read -r -d '' iso_file; do
            iso_files+=("$iso_file")
        done < <(find "${start_dir}" -maxdepth 1 -type f \( -name "*.iso" -o -name "*.ISO" -o -name "*.dmg" -o -name "*.DMG" \) -print0 2>/dev/null | sort -z)
        
        if [[ ${#iso_files[@]} -eq 0 ]]; then
            warn "No ISOs found in ${start_dir}"
            return 1
        fi
        
        # Return first ISO found
        log "Auto-selected: $(basename "${iso_files[0]}")"
        echo "${iso_files[0]}"
        return 0
    fi
    
    # Interactive mode only from here
    if is_interactive; then
        heading "Available ISOs in ${start_dir}"
        
        # List ISOs in the selected directory
        local i=0
        local iso_files=()
        while IFS= read -r -d '' iso_file; do
            iso_files+=("$iso_file")
            local file_size=$(file_size_bytes "${iso_file}")
            local human_size
            if (( file_size >= 1073741824 )); then
                human_size="$((file_size / 1073741824))G"
            elif (( file_size >= 1048576 )); then
                human_size="$((file_size / 1048576))M"
            else
                human_size="${file_size}B"
            fi
            log "  [${i}] $(basename "${iso_file}") (${human_size})"
            ((i++)) || true
        done < <(find "${start_dir}" -maxdepth 1 -type f \( -name "*.iso" -o -name "*.ISO" -o -name "*.dmg" -o -name "*.DMG" \) -print0 2>/dev/null | sort -z)
        
        if [[ $i -eq 0 ]]; then
            warn "No ISOs found in ${start_dir}"
            read -rp "Try another directory? (y/n) [y]: " try_another
            try_another="${try_another:-y}"
            if [[ "${try_another}" =~ ^[yY] ]]; then
                select_iso
                return $?
            else
                return 1
            fi
        fi
        
        log ""
        read -rp "Select ISO [0-$(($i-1))] or enter full path: " choice
        
        if [[ "${choice}" =~ ^[0-9]+$ ]]; then
            # Select by number
            if [[ $choice -lt $i && $choice -ge 0 ]]; then
                log "Selected: $(basename "${iso_files[$choice]}")"
                echo "${iso_files[$choice]}"
                return 0
            else
                warn "Invalid ISO selection. Please choose a number between 0 and $(($i-1))."
                read -rp "Try again? (y/n) [y]: " retry_choice
                retry_choice="${retry_choice:-y}"
                if [[ "${retry_choice}" =~ ^[yY] ]]; then
                    select_iso
                    return $?
                else
                    return 1
                fi
            fi
        elif [[ -f "${choice}" ]]; then
            # Direct path
            log "Selected: $(basename "${choice}")"
            echo "${choice}"
            return 0
        else
            warn "ISO not found: ${choice}"
            read -rp "Try again? (y/n) [y]: " retry_choice
            retry_choice="${retry_choice:-y}"
            if [[ "${retry_choice}" =~ ^[yY] ]]; then
                select_iso
                return $?
            else
                return 1
            fi
        fi
    else
        # Non-interactive mode: we should never reach here since we handled it earlier
        warn "Non-interactive mode should have been handled earlier"
        return 1
    fi
}

# Select a disk image interactively
select_disk() {
    local choice start_dir=""
    
    # Non-interactive mode: use default directory
    if ! is_interactive; then
        start_dir="${DISK_DIR}"
        
        # Auto-select first disk image if available
        local disk_files=()
        while IFS= read -r -d '' disk_file; do
            disk_files+=("$disk_file")
        done < <(find "${start_dir}" -maxdepth 1 -type f \( -name "*.qcow2" -o -name "*.QCOW2" -o -name "*.img" -o -name "*.IMG" -o -name "*.raw" -o -name "*.RAW" -o -name "*.hda" -o -name "*.HDA" -o -name "*.dsk" -o -name "*.DSK" \) -print0 2>/dev/null | sort -z)
        
        if [[ ${#disk_files[@]} -eq 0 ]]; then
            warn "No disk images found in ${start_dir}"
            return 1
        fi
        
        # Return first disk found
        log "Auto-selected: $(basename "${disk_files[0]}")"
        echo "${disk_files[0]}"
        return 0
    else
        # Enhanced UX: Ask user which directory to start with
        log "Select Disk Image for VM"
        log "--------------------------"
        read -rp "Enter directory to scan for disk images [${DISK_DIR}]: " start_dir
        start_dir="${start_dir:-${DISK_DIR}}"
        
        # Validate directory exists
        if [[ ! -d "${start_dir}" ]]; then
            warn "Directory does not exist: ${start_dir}"
            read -rp "Do you want to browse to another directory? (y/n) [y]: " navigate_choice
            navigate_choice="${navigate_choice:-y}"
            if [[ "${navigate_choice}" =~ ^[yY] ]]; then
                select_disk
                return $?
            else
                return 1
            fi
        fi
        
        heading "Available Disk Images in ${start_dir}"
        
        # List disk images in the selected directory
        local i=0
        local disk_files=()
        while IFS= read -r -d '' disk_file; do
            disk_files+=("$disk_file")
            local file_size=$(file_size_bytes "${disk_file}")
            local human_size
            if (( file_size >= 1073741824 )); then
                human_size="$((file_size / 1073741824))G"
            elif (( file_size >= 1048576 )); then
                human_size="$((file_size / 1048576))M"
            else
                human_size="${file_size}B"
            fi
            log "  [${i}] $(basename "${disk_file}") (${human_size})"
            ((i++)) || true
        done < <(find "${start_dir}" -maxdepth 1 -type f \( -name "*.qcow2" -o -name "*.QCOW2" -o -name "*.img" -o -name "*.IMG" -o -name "*.raw" -o -name "*.RAW" -o -name "*.hda" -o -name "*.HDA" -o -name "*.dsk" -o -name "*.DSK" \) -print0 2>/dev/null | sort -z)
        
        if [[ $i -eq 0 ]]; then
            warn "No disk images found in ${start_dir}"
            read -rp "Try another directory? (y/n) [y]: " try_another
            try_another="${try_another:-y}"
            if [[ "${try_another}" =~ ^[yY] ]]; then
                select_disk
                return $?
            else
                return 1
            fi
        fi
        
        log ""
        read -rp "Select disk image [0-$(($i-1))] or enter full path: " choice
        
        if [[ "${choice}" =~ ^[0-9]+$ ]]; then
            # Select by number
            if [[ $choice -lt $i && $choice -ge 0 ]]; then
                log "Selected: $(basename "${disk_files[$choice]}")"
                echo "${disk_files[$choice]}"
                return 0
            else
                warn "Invalid disk selection. Please choose a number between 0 and $(($i-1))."
                read -rp "Try again? (y/n) [y]: " retry_choice
                retry_choice="${retry_choice:-y}"
                if [[ "${retry_choice}" =~ ^[yY] ]]; then
                    select_disk
                    return $?
                else
                    return 1
                fi
            fi
        elif [[ -f "${choice}" ]]; then
            # Direct path
            log "Selected: $(basename "${choice}")"
            echo "${choice}"
            return 0
        else
            warn "Disk image not found: ${choice}"
            read -rp "Try again? (y/n) [y]: " retry_choice
            retry_choice="${retry_choice:-y}"
            if [[ "${retry_choice}" =~ ^[yY] ]]; then
                select_disk
                return $?
            else
                return 1
            fi
        fi
    fi
}

# Select a ROM file interactively
select_rom() {
    local choice start_dir=""
    
    # Non-interactive mode: use default directory
    if ! is_interactive; then
        start_dir="${ROM_DIR}"
        
        # Auto-select first ROM if available
        local rom_files=()
        while IFS= read -r -d '' rom_file; do
            rom_files+=("$rom_file")
        done < <(find "${start_dir}" -maxdepth 1 -type f \( -name "*.rom" -o -name "*.ROM" -o -name "*.bin" -o -name "*.BIN" \) -print0 2>/dev/null | sort -z)
        
        if [[ ${#rom_files[@]} -eq 0 ]]; then
            warn "No ROM files found in ${start_dir}"
            return 1
        fi
        
        # Return first ROM found
        log "Auto-selected: $(basename "${rom_files[0]}")"
        echo "${rom_files[0]}"
        return 0
    else
        # Enhanced UX: Ask user which directory to start with
        log "Select ROM File for VM"
        log "----------------------"
        read -rp "Enter directory to scan for ROM files [${ROM_DIR}]: " start_dir
        start_dir="${start_dir:-${ROM_DIR}}"
        
        # Validate directory exists
        if [[ ! -d "${start_dir}" ]]; then
            warn "Directory does not exist: ${start_dir}"
            read -rp "Do you want to browse to another directory? (y/n) [y]: " navigate_choice
            navigate_choice="${navigate_choice:-y}"
            if [[ "${navigate_choice}" =~ ^[yY] ]]; then
                select_rom
                return $?
            else
                return 1
            fi
        fi
        
        heading "Available ROM Files in ${start_dir}"
        
        # List ROM files in the selected directory
        local i=0
        local rom_files=()
        while IFS= read -r -d '' rom_file; do
            rom_files+=("$rom_file")
            local file_size=$(file_size_bytes "${rom_file}")
            local human_size
            if (( file_size >= 1073741824 )); then
                human_size="$((file_size / 1073741824))G"
            elif (( file_size >= 1048576 )); then
                human_size="$((file_size / 1048576))M"
            else
                human_size="${file_size}B"
            fi
            log "  [${i}] $(basename "${rom_file}") (${human_size})"
            ((i++)) || true
        done < <(find "${start_dir}" -maxdepth 1 -type f \( -name "*.rom" -o -name "*.ROM" -o -name "*.bin" -o -name "*.BIN" \) -print0 2>/dev/null | sort -z)
        
        if [[ $i -eq 0 ]]; then
            warn "No ROM files found in ${start_dir}"
            read -rp "Try another directory? (y/n) [y]: " try_another
            try_another="${try_another:-y}"
            if [[ "${try_another}" =~ ^[yY] ]]; then
                select_rom
                return $?
            else
                return 1
            fi
        fi
        
        log ""
        read -rp "Select ROM file [0-$(($i-1))] or enter full path: " choice
        
        if [[ "${choice}" =~ ^[0-9]+$ ]]; then
            # Select by number
            if [[ $choice -lt $i && $choice -ge 0 ]]; then
                log "Selected: $(basename "${rom_files[$choice]}")"
                echo "${rom_files[$choice]}"
                return 0
            else
                warn "Invalid ROM selection. Please choose a number between 0 and $(($i-1))."
                read -rp "Try again? (y/n) [y]: " retry_choice
                retry_choice="${retry_choice:-y}"
                if [[ "${retry_choice}" =~ ^[yY] ]]; then
                    select_rom
                    return $?
                else
                    return 1
                fi
            fi
        elif [[ -f "${choice}" ]]; then
            # Direct path
            log "Selected: $(basename "${choice}")"
            echo "${choice}"
            return 0
        else
            warn "ROM file not found: ${choice}"
            read -rp "Try again? (y/n) [y]: " retry_choice
            retry_choice="${retry_choice:-y}"
            if [[ "${retry_choice}" =~ ^[yY] ]]; then
                select_rom
                return $?
            else
                return 1
            fi
        fi
    fi
}

# List VMs with enhanced UX
list_vms() {
    heading "Available Virtual Machines"
    
    [[ -d "${VM_DIR}" ]] || { 
        warn "No VMs found. VM directory: ${VM_DIR}"
        log "To create a VM: ${SCRIPT_NAME} create"
        return 1; 
    }
    
    local i=0
    local vm_info=()  # Store VM info for later use
    
    # Search for .conf files in VM directories (vms/VM_NAME_PLATFORM/conf/)
    while IFS= read -r -d '' vm_conf; do
        local vm_dir=$(dirname "$(dirname "${vm_conf}")")  # Get VM base directory
        local vm_name=$(basename "${vm_dir}" | sed 's/_.*//')  # Extract VM name (remove _PLATFORM)
        local platform=$(basename "${vm_dir}" | sed 's/^[^_]*_//')  # Extract platform
        
        # Check if disk exists
        local disk_path="${vm_dir}/qcow2/${vm_name}.qcow2"
        local disk_status="✓"
        [[ -f "${disk_path}" ]] || disk_status="✗"
        
        # Check if config exists
        local config_status="✓"
        [[ -f "${vm_conf}" ]] || config_status="✗"
        
        # Store VM info
        vm_info+=("${vm_dir}" "${vm_name}" "${platform}" "${disk_status}" "${config_status}")
        
        # Display VM info
        log "  [${i}] ${vm_name} (${platform}) [Disk: ${disk_status} | Config: ${config_status}]"
        ((i++)) || true
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    if [[ $i -eq 0 ]]; then
        warn "No VM configurations found in ${VM_DIR}/"
        log ""
        log "To create a new VM:"
        log "  ${SCRIPT_NAME} create"
        log ""
        log "Supported platforms: ppc, ppc64, x86_64, m68k, sparc, sparc64, i386, arm, arm64"
        return 1
    else
        log ""
        log "Total: ${i} VM(s) found"
    fi
}

# Launch a VM
launch_vm() {
    local vm_name="$1"
    local config_file=""
    
    # Search for config file in the new directory structure (vms/VM_NAME_PLATFORM/conf/)
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            config_file="$file"
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
    
    [[ -f "${config_file}" ]] || die "VM config not found: ${vm_name}.conf"
    
    # Load configuration
    source "${config_file}"
    
    # Validate
    validate_vm_config "${config_file}" || die "Invalid VM configuration"
    
    # Resolve QEMU binary
    local qemu
    qemu=$(qemu_bin_or_die "${QEMU_BIN:-qemu-system-x86_64}")
    
    # Build QEMU command
    local cmd=(
        "${qemu}"
        -machine "${MACHINE:-pc}"
        -cpu "${CPU:-host}"
        -m "${RAM_MB:-2048}"
        -display "${DISPLAY_BACKEND:-${DEFAULT_DISPLAY}}"
    )
    
    # Add disk
    [[ -n "${HDD_IMAGE:-}" && -f "${HDD_IMAGE}" ]] && cmd+=(-hda "${HDD_IMAGE}")
    
    # Add CDROM if specified
    [[ -n "${CDROM_IMAGE:-}" && -f "${CDROM_IMAGE}" ]] && cmd+=(-cdrom "${CDROM_IMAGE}")
    
    # Add network
    cmd+=(-nic user,model="${NETWORK_MODEL:-e1000}")
    
    # Option C: GDB debugging support
    if [[ "${ENABLE_GDB:-n}" == "y" ]]; then
        local gdb_port="${GDB_PORT:-${DEFAULT_GDB_PORT}}"
        cmd+=(-gdb "tcp::${gdb_port}" -S)
        log "GDB debugging active on port: ${gdb_port}"
        log "Connect with: ${GDB_BIN:-gdb-multiarch} -ex 'target remote localhost:${gdb_port}'"
    fi
    
    # Option C: SSH port forwarding
    if [[ "${ENABLE_SSH:-n}" == "y" ]]; then
        local ssh_port="${SSH_PORT:-${DEFAULT_SSH_PORT}}"
        cmd+=(-netdev "user,id=sshnet0,hostfwd=tcp::${ssh_port}-:22")
        cmd+=(-device "virtio-net-pci,netdev=sshnet0")
        log "SSH forwarding active: host:${ssh_port} -> guest:22"
        log "Connect with: ssh user@localhost -p ${ssh_port}"
    fi
    
    # Add other devices
    cmd+=(-device usb-kbd -device usb-mouse -rtc base=localtime)
    
    # Option C: Start Netatalk if enabled
    if [[ "${ENABLE_NETATALK:-n}" == "y" ]]; then
        local netatalk_share_name="${NETATALK_SHARE_NAME:-VM_${vm_name}}"
        local share_dir="${SHARED_DIR:-${DEFAULT_MACOS_SHARE_DIR}}"
        detect_netatalk
        if [[ "$NETATALK_INSTALLED" == true ]]; then
            if start_netatalk_share "$netatalk_share_name" "$share_dir"; then
                log "Netatalk share started: $netatalk_share_name"
                log "Share available via: afp://$(hostname):${DEFAULT_NETATALK_PORT}/$netatalk_share_name"
            else
                warn "Netatalk failed to start - continuing without AppleShare"
            fi
        else
            warn "Netatalk not installed - install with: brew install netatalk or sudo port install netatalk"
        fi
    fi
    
    log "Launching VM: ${vm_name}"
    log "Command: ${cmd[*]}"
    
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/${vm_name}-$(date +%Y%m%d-%H%M%S).log"
}

# Delete a VM
delete_vm() {
    local vm_name="$1"
    local config_file=""
    
    # Search for config file in the new directory structure (vms/VM_NAME_PLATFORM/conf/)
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            config_file="$file"
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
    
    [[ -f "${config_file}" ]] || die "VM not found: ${vm_name}"
    
    # Load config to get disk path
    source "${config_file}"
    
    log "Deleting VM: ${vm_name}"
    
    # Get the VM base directory (parent of parent of config file: vms/VM_NAME_PLATFORM/)
    local vm_base_dir=$(dirname "$(dirname "${config_file}")")
    
    # Remove the entire VM directory (includes conf/, qcow2/, sh/, rom/)
    if [[ -d "${vm_base_dir}" ]]; then
        log "Removing VM directory: ${vm_base_dir}"
        rm -rf "${vm_base_dir}"
        log "VM directory deleted successfully."
    else
        log "VM directory not found: ${vm_base_dir}"
    fi
    
    log "VM deleted successfully."
}

# Create a new VM with enhanced UX
create_vm() {
    local vm_name vm_type disk_size iso_path
    
    # This function requires interactive mode
    if ! is_interactive; then
        warn "create_vm function requires interactive mode"
        return 1
    fi
    
    heading "Create New Virtual Machine"
    log "This will create a new VM with bundled directory structure:"
    log "  ~/vm_assistant/vms/VM_NAME_PLATFORM/"
    log "    ├── conf/          # Configuration files"
    log "    ├── qcow2/        # Disk images"
    log "    ├── sh/           # Scripts"
    log "    └── rom/          # ROM files"
    log ""
    
    vm_name=$(ask "VM name (no spaces, e.g., macos9, haiku)" "")
    [[ -z "${vm_name}" ]] && die "VM name cannot be empty"
    
    # Validate VM name doesn't contain invalid characters
    if [[ "${vm_name}" =~ [^a-zA-Z0-9_-] ]]; then
        warn "VM name should only contain alphanumeric characters, underscores, and hyphens"
        confirm_name=$(ask "Continue with this name anyway?" "n")
        if [[ "${confirm_name}" != "y" ]]; then
            create_vm
            return
        fi
    fi
    
    # Check if VM already exists
    local existing_vm_dir="${VM_DIR}/${vm_name}"
    if [[ -d "${existing_vm_dir}" ]]; then
        warn "A VM directory already exists: ${existing_vm_dir}"
        overwrite_choice=$(ask "Overwrite existing VM?" "n")
        if [[ "${overwrite_choice}" =~ ^[yY] ]]; then
            log "Removing existing VM..."
            rm -rf "${existing_vm_dir}"
        else
            retry_choice=$(ask "Choose a different name?" "y")
            if [[ "${retry_choice}" =~ ^[yY] ]]; then
                create_vm
                return
            else
                return 1
            fi
        fi
    fi
    
    vm_type=$(ask "VM type (ppc/ppc64/x86_64/m68k/sparc)" "ppc")
    
    # Validate platform
    case "${vm_type}" in
        ppc|ppc64|x86_64|m68k|sparc|sparc64|i386|arm|arm64)
            # Valid platform
            ;;
        *)
            warn "Invalid platform. Please choose from: ppc, ppc64, x86_64, m68k, sparc, sparc64, i386, arm, arm64"
            retry_platform=$(ask "Try again?" "y")
            if [[ "${retry_platform}" =~ ^[yY] ]]; then
                create_vm
                return
            else
                return 1
            fi
            ;;
    esac
    
    disk_size=$(ask "Disk size (e.g., 40G, 20G, 100G)" "40G")
    
    log ""
    log "Creating VM: ${vm_name} (Platform: ${vm_type}, Disk: ${disk_size})"
    log "Destination: ${VM_DIR}/${vm_name}_${vm_type}/"
    
    # Create config
    log "  → Creating configuration..."
    create_vm_config "${vm_name}" "${vm_type}"
    
    # Create disk in VM-specific directory
    log "  → Creating disk image..."
    create_disk "${vm_name}" "${vm_type}" "${disk_size}" "qcow2"
    
    log ""
    log "✅ VM created successfully!"
    log "   Configuration: ${VM_DIR}/${vm_name}_${vm_type}/conf/${vm_name}.conf"
    log "   Disk Image:    ${VM_DIR}/${vm_name}_${vm_type}/qcow2/${vm_name}.qcow2"
    log ""
    log "To launch: ${SCRIPT_NAME} launch ${vm_name}"
    log "To configure: ${SCRIPT_NAME} edit ${vm_name}"
}

# ---------------------------------------------------------------------------
# Platform-Specific Launch Functions (from vm_assist.sh)
# ---------------------------------------------------------------------------

launch_macos_68k() {
    heading "MacOS 68k (System 7.x / Mac OS 8.x)"
    log "Machine: QEMU q800 (Motorola 68040, up to 256 MB RAM)"
    log "Reference config: $(config_path "macos-68k")"

    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-m68k")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 512M / 4G)" "128")
    local cpu
    cpu=$(ask_m68k_cpu "m68040")
    local disk
    disk=$(pick_image "macos-68k")
    local cdrom
    cdrom=$(pick_cdrom "macos-68k")
    local display
    display=$(ask "Display (cocoa/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';', e.g. nubus-macfb;nubus-macfb)" "")
    local shared_dir
    shared_dir=$(ask "Host Mac share/export path" "${DEFAULT_MACOS_SHARE_DIR}")
    local afp_endpoint
    afp_endpoint=$(ask "Netatalk/AFP endpoint for the guest" "${DEFAULT_AFP_HOST}:${DEFAULT_AFP_PORT}")
    local tls_proxy
    tls_proxy=$(ask "TLS proxy endpoint for the guest" "${DEFAULT_TLS_PROXY_HOST}:${DEFAULT_TLS_PROXY_PORT}")
    local port_forwards
    port_forwards=$(ask_port_forwards "")
    local gdb_forward
    gdb_forward=$(ask_gdb_bridge_forward "${DEFAULT_GDB_BRIDGE_PORT}")
    local combined_forwards
    combined_forwards=$(merge_csv_values "${port_forwards}" "${gdb_forward}")
    local firmware_path
    firmware_path=$(ask "Optional ROM / firmware path (blank to skip)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi

    local -a dflags; display_flags dflags "${display}" "${qemu}" "qemu-system-m68k"
    local -a netflags; append_user_network netflags "dp83932" "${combined_forwards}"
    local -a dbgflags; qemu_gdb_flags dbgflags

    prepare_macos_integration "${shared_dir}" "${afp_endpoint}" "${tls_proxy}"

    local cmd=(
        "${qemu}"
        -machine q800
        -m "${ram}"
        -cpu "${cpu}"
        "${dflags[@]}"
        "${netflags[@]}"
        -rtc base=localtime
        "${dbgflags[@]}"
    )

    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"

    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi
    if [[ -n "${cdrom}" ]]; then
        cmd+=(-cdrom "${cdrom}" -boot d)
    fi

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/macos-68k-$(date +%Y%m%d-%H%M%S).log"
}

launch_macos_ppc() {
    heading "MacOS PPC (Mac OS 7.5.2 – 9.2.2, G3/G4)"
    log "Machine: QEMU mac99 (PowerPC G3/G4)"
    log "Note: You need a Mac ROM image (Old World: 'mac.rom') or Apple firmware."
    log "Place it in: ${VM_IMAGE_DIR}/macos-ppc/"
    log "Dual-processor tip: choose 2 sockets to emulate a G4 MDD (7455×2)."
    log "Reference config: $(config_path "macos-ppc")"

    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-ppc")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 512M / 4G)" "256")
    local cpu
    cpu=$(ask_ppc_cpu "7455")
    local smp_flags
    smp_flags=$(ask_ppc_smp "1" "1")
    local disk
    disk=$(pick_image "macos-ppc")
    local cdrom
    cdrom=$(pick_cdrom "macos-ppc")
    local display
    display=$(ask "Display (cocoa/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';', e.g. secondary-vga,vgamem_mb=16;secondary-vga,vgamem_mb=16)" "")
    local shared_dir
    shared_dir=$(ask "Host Mac share/export path" "${DEFAULT_MACOS_SHARE_DIR}")
    local afp_endpoint
    afp_endpoint=$(ask "Netatalk/AFP endpoint for the guest" "${DEFAULT_AFP_HOST}:${DEFAULT_AFP_PORT}")
    local tls_proxy
    tls_proxy=$(ask "TLS proxy endpoint for the guest" "${DEFAULT_TLS_PROXY_HOST}:${DEFAULT_TLS_PROXY_PORT}")
    local port_forwards
    port_forwards=$(ask_port_forwards "")
    local gdb_forward
    gdb_forward=$(ask_gdb_bridge_forward "${DEFAULT_GDB_BRIDGE_PORT}")
    local combined_forwards
    combined_forwards=$(merge_csv_values "${port_forwards}" "${gdb_forward}")
    local firmware_path
    firmware_path=$(ask "Path to ROM / firmware file (leave blank for OpenBIOS)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi

    local -a dflags; display_flags dflags "${display}" "${qemu}" "qemu-system-ppc64"
    local -a netflags; append_user_network netflags "sungem" "${combined_forwards}"
    local -a dbgflags; qemu_gdb_flags dbgflags

    prepare_macos_integration "${shared_dir}" "${afp_endpoint}" "${tls_proxy}"

    local cmd=(
        "${qemu}"
        -machine mac99,via=pmu
        -m "${ram}"
        -cpu "${cpu}"
        -smp "${smp_flags}"
        "${dflags[@]}"
        -device VGA,vgamem_mb=16
        -device usb-kbd
        -device usb-mouse
        "${netflags[@]}"
        -rtc base=localtime
        "${dbgflags[@]}"
    )

    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"
    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi
    if [[ -n "${cdrom}" ]]; then
        cmd+=(-cdrom "${cdrom}" -boot d)
    fi

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/macos-ppc-$(date +%Y%m%d-%H%M%S).log"
}

launch_macos_ppc64() {
    heading "MacOS PPC G5 (Mac OS X, ppc64)"
    log "Machine: QEMU mac99 (PowerPC 970/G5)"
    log "Reference config: $(config_path "macos-ppc64")"

    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-ppc64")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 512M / 4G)" "2048")
    local cpu
    cpu=$(ask "CPU (970/970fx/970mp):" "970fx")
    local smp_flags
    smp_flags=$(ask_ppc_smp "2" "1")
    local disk
    disk=$(pick_image "macos-ppc64")
    local cdrom
    cdrom=$(pick_cdrom "macos-ppc64")
    local display
    display=$(ask "Display (cocoa/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';', e.g. secondary-vga,vgamem_mb=32;secondary-vga,vgamem_mb=32)" "")
    local port_forwards
    port_forwards=$(ask_port_forwards "")
    local gdb_forward
    gdb_forward=$(ask_gdb_bridge_forward "${DEFAULT_GDB_BRIDGE_PORT}")
    local combined_forwards
    combined_forwards=$(merge_csv_values "${port_forwards}" "${gdb_forward}")
    local firmware_path
    firmware_path=$(ask "Path to ROM / firmware file (leave blank for OpenBIOS)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi

    local -a dflags; display_flags dflags "${display}" "${qemu}"
    local -a netflags; append_user_network netflags "sungem" "${combined_forwards}"
    local -a dbgflags; qemu_gdb_flags dbgflags

    local cmd=(
        "${qemu}"
        -machine mac99,via=pmu
        -m "${ram}"
        -cpu "${cpu}"
        -smp "${smp_flags}"
        "${dflags[@]}"
        -device VGA,vgamem_mb=64
        -device usb-kbd
        -device usb-mouse
        "${netflags[@]}"
        -rtc base=localtime
        "${dbgflags[@]}"
    )

    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"
    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi
    if [[ -n "${cdrom}" ]]; then
        cmd+=(-cdrom "${cdrom}" -boot d)
    fi

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/macos-ppc64-$(date +%Y%m%d-%H%M%S).log"
}

launch_haiku() {
    heading "HaikuOS (x86 / x86_64)"
    log "Download Haiku nightlies or releases from https://www.haiku-os.org/get-haiku"
    log "Reference config: $(config_path "haiku")"

    local arch
    arch=$(ask "Architecture (i386/x86_64)" "x86_64")
    local qemu
    if [[ "${arch}" == "i386" ]]; then
        qemu=$(qemu_bin_or_die "qemu-system-i386")
    else
        qemu=$(qemu_bin_or_die "qemu-system-x86_64")
    fi

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 512M / 4G)" "512")
    local disk
    disk=$(pick_image "haiku-${arch}")
    local cdrom
    cdrom=$(pick_cdrom "haiku-${arch}")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
    local kvm
    kvm=$(ask "Enable KVM hardware acceleration? (yes/no)" "yes")
    local cores
    cores=$(ask "CPU cores" "2")
    local shared_dir
    shared_dir=$(ask "Shared directory path (VirtFS/9P)" "${VM_SHARED_DIR}")
    shared_dir=$(ensure_shared_dir "${shared_dir}")
    local port_forwards
    port_forwards=$(ask_port_forwards "")
    local gdb_forward
    gdb_forward=$(ask_gdb_bridge_forward "${DEFAULT_GDB_BRIDGE_PORT}")
    local combined_forwards
    combined_forwards=$(merge_csv_values "${port_forwards}" "${gdb_forward}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';', e.g. secondary-vga,vgamem_mb=32;secondary-vga,vgamem_mb=32)" "")
    local firmware_path
    firmware_path=$(ask "Optional ROM / firmware path (blank to skip)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi

    local -a dflags; display_flags dflags "${display}" "${qemu}" "qemu-system-${arch}"
    local -a netflags; append_user_network netflags "e1000" "${combined_forwards}"
    local -a dbgflags; qemu_gdb_flags dbgflags

    local cmd=(
        "${qemu}"
        -machine q35
        -m "${ram}"
        -smp "${cores}"
        "${dflags[@]}"
        -device VGA,vgamem_mb=32
        -device usb-ehci
        -device usb-kbd
        -device usb-mouse
        "${netflags[@]}"
        -rtc base=localtime
        -virtfs local,path="${shared_dir}",mount_tag=shared,security_model=mapped-xattr
        "${dbgflags[@]}"
    )

    if is_yes "${kvm}" && [[ -e /dev/kvm ]]; then
        cmd+=(-enable-kvm -cpu host)
    else
        cmd+=(-cpu qemu64)
    fi

    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"
    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi
    if [[ -n "${cdrom}" ]]; then
        cmd+=(-cdrom "${cdrom}" -boot d)
    fi

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/haiku-${arch}-$(date +%Y%m%d-%H%M%S).log"
}

launch_linux() {
    heading "Linux VM"
    log "Generic Linux launch for various architectures."
    log "Reference config: $(config_path "linux")"

    local arch
    arch=$(ask "Architecture (x86_64/arm64/i386/ppc64/m68k):" "x86_64")
    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-${arch}")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 512M / 4G)" "2048")
    local cores
    cores=$(ask "CPU cores" "2")
    local disk
    disk=$(pick_image "linux-${arch}")
    local cdrom
    cdrom=$(pick_cdrom "linux-${arch}")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
    local kvm
    kvm=$(ask "Enable KVM hardware acceleration? (yes/no)" "yes")
    local smb_share
    smb_share=$(ask "Optional host SMB share path for the guest" "")
    if [[ -n "${smb_share}" ]]; then
        smb_share=$(ensure_shared_dir "${smb_share}")
    fi
    local port_forwards
    port_forwards=$(ask_port_forwards "")
    local gdb_forward
    gdb_forward=$(ask_gdb_bridge_forward "${DEFAULT_GDB_BRIDGE_PORT}")
    local combined_forwards
    combined_forwards=$(merge_csv_values "${port_forwards}" "${gdb_forward}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';', e.g. secondary-vga,vgamem_mb=16;secondary-vga,vgamem_mb=16)" "")
    local firmware_path
    firmware_path=$(ask "Optional ROM / firmware path (blank to skip)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi

    local -a dflags; display_flags dflags "${display}" "${qemu}" "qemu-system-${arch}"
    local -a netflags
    local nic_model="e1000"
    case "${arch}" in
        ppc64) nic_model="sungem" ;;
        m68k) nic_model="dp83932" ;;
        *) nic_model="e1000" ;;
    esac
    append_user_network netflags "${nic_model}" "${combined_forwards}" "${smb_share}"
    local -a dbgflags; qemu_gdb_flags dbgflags

    local cmd=(
        "${qemu}"
        -machine q35
        -m "${ram}"
        -smp "${cores}"
        "${dflags[@]}"
        -device VGA,vgamem_mb=16
        -device usb-ehci
        -device usb-kbd
        -device usb-mouse
        "${netflags[@]}"
        -rtc base=localtime
        "${dbgflags[@]}"
    )

    if is_yes "${kvm}" && [[ -e /dev/kvm ]]; then
        cmd+=(-enable-kvm -cpu host)
    else
        cmd+=(-cpu host)
    fi

    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"
    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi
    if [[ -n "${cdrom}" ]]; then
        cmd+=(-cdrom "${cdrom}" -boot d)
    fi

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/linux-${arch}-$(date +%Y%m%d-%H%M%S).log"
}

# ---------------------------------------------------------------------------
# PLATFORM: Atari ST / STE / TT / Falcon (m68k)
# ---------------------------------------------------------------------------
launch_atari() {
    heading "Atari ST / STE / TT / Falcon (68k)"
    log "Best experience: use Hatari emulator for cycle-accurate Atari emulation."
    log "This script provides a basic QEMU m68k launch."

    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-m68k")

    # Prefer Hatari if installed
    if command -v hatari &>/dev/null; then
        log "Hatari found — launching Hatari for best Atari compatibility."
        local disk
        disk=$(pick_image "atari")
        if [[ -z "${disk}" ]]; then
            warn "No Atari disk or harddrive path selected; skipping Hatari launch."
            return
        fi
        local tos_img
        tos_img=$(ask "Path to TOS ROM image" "${VM_IMAGE_DIR}/atari/tos.img")
        # Hatari GEMDOS mode expects a host directory, so pass the parent folder.
        hatari --tos "${tos_img}" --harddrive "$(dirname "${disk}")" &
        return
    fi

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix; guest/machine limits still apply)" "14")
    local cpu
    cpu=$(ask_m68k_cpu "m68040")
    local disk
    disk=$(pick_image "atari")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';')" "")
    local firmware_path
    firmware_path=$(ask "Optional ROM / firmware path for QEMU fallback (blank to skip)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi

    local -a dflags; display_flags dflags "${display}" "${qemu}" "qemu-system-m68k"

    local cmd=(
        "${qemu}"
        -machine virt
        -m "${ram}"
        -cpu "${cpu}"
        "${dflags[@]}"
        -nic user
        -rtc base=localtime
    )
    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"
    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/atari-$(date +%Y%m%d-%H%M%S).log"
}

# ---------------------------------------------------------------------------
# PLATFORM: Commodore Amiga (m68k)
# QEMU does not emulate Amiga hardware natively; launch AROS/UAE wrapper
# ---------------------------------------------------------------------------
launch_amiga() {
    heading "Commodore Amiga (68k)"
    log "QEMU does not natively emulate Amiga custom chips (Agnus, Denise, Paula)."
    log "Options: 1) AROS Research OS (open-source AmigaOS-compatible) via QEMU"
    log "         2) FS-UAE / WinUAE (most accurate) — install separately"

    local choice
    choice=$(ask "Launch (1) AROS via QEMU or (2) FS-UAE" "1")

    if [[ "${choice}" == "2" ]]; then
        if command -v fs-uae &>/dev/null; then
            log "Launching FS-UAE …"
            fs-uae &
        else
            die "fs-uae not found. Install it with your package manager: sudo apt install fs-uae"
        fi
        return
    fi

    # AROS via QEMU m68k
    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-m68k")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 512M / 4G)" "128")
    local cpu
    cpu=$(ask_m68k_cpu "m68040")
    local disk
    disk=$(pick_image "amiga-aros")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';')" "")
    local firmware_path
    firmware_path=$(ask "Optional ROM / firmware path (blank to skip)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi

    local -a dflags; display_flags dflags "${display}" "${qemu}"

    local cmd=(
        "${qemu}"
        -machine virt
        -m "${ram}"
        -cpu "${cpu}"
        "${dflags[@]}"
        -nic user
        -rtc base=localtime
    )
    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"
    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/amiga-$(date +%Y%m%d-%H%M%S).log"
}

# ---------------------------------------------------------------------------
# PLATFORM: Solaris x86 / x86_64
# ---------------------------------------------------------------------------
launch_solaris_x86() {
    heading "Solaris x86"
    log "Suitable for Solaris 8/9/10 x86 install media and related illumos-family experiments."
    log "Reference config: $(config_path "solaris-x86")"

    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-i386")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 1024M / 4G)" "1024")
    local cores
    cores=$(ask "CPU cores" "2")
    local disk
    disk=$(pick_image "solaris-x86")
    local cdrom
    cdrom=$(pick_cdrom "solaris-x86")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
    local smb_share
    smb_share=$(ask "Optional host SMB share path for the guest" "")
    if [[ -n "${smb_share}" ]]; then
        smb_share=$(ensure_shared_dir "${smb_share}")
    fi
    local port_forwards
    port_forwards=$(ask_port_forwards "")
    local gdb_forward
    gdb_forward=$(ask_gdb_bridge_forward "${DEFAULT_GDB_BRIDGE_PORT}")
    local combined_forwards
    combined_forwards=$(merge_csv_values "${port_forwards}" "${gdb_forward}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';', e.g. secondary-vga,vgamem_mb=16;secondary-vga,vgamem_mb=16)" "")
    local firmware_path
    firmware_path=$(ask "Optional ROM / firmware path (blank to skip)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi

    local -a dflags; display_flags dflags "${display}" "${qemu}"
    local -a netflags; append_user_network netflags "e1000" "${combined_forwards}" "${smb_share}"
    local -a dbgflags; qemu_gdb_flags dbgflags

    local cmd=(
        "${qemu}"
        -machine pc
        -cpu pentium3
        -m "${ram}"
        -smp "${cores}"
        "${dflags[@]}"
        -device VGA,vgamem_mb=16
        -device usb-kbd
        -device usb-mouse
        "${netflags[@]}"
        -rtc base=localtime
        "${dbgflags[@]}"
    )
    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"

    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi
    if [[ -n "${cdrom}" ]]; then
        cmd+=(-cdrom "${cdrom}" -boot d)
    fi

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/solaris-x86-$(date +%Y%m%d-%H%M%S).log"
}

# ---------------------------------------------------------------------------
# PLATFORM: Solaris SPARC
# ---------------------------------------------------------------------------
launch_solaris_sparc() {
    heading "Solaris SPARC"
    log "Suitable for sun4u-era Solaris/SPARC media; requires qemu-system-sparc64."
    log "Reference config: $(config_path "solaris-sparc")"

    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-sparc64")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 1024M / 4G)" "1024")
    local disk
    disk=$(pick_image "solaris-sparc")
    local cdrom
    cdrom=$(pick_cdrom "solaris-sparc")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
    local port_forwards
    port_forwards=$(ask_port_forwards "")
    local gdb_forward
    gdb_forward=$(ask_gdb_bridge_forward "${DEFAULT_GDB_BRIDGE_PORT}")
    local combined_forwards
    combined_forwards=$(merge_csv_values "${port_forwards}" "${gdb_forward}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';', e.g. tcx;tcx)" "")
    local firmware_path
    firmware_path=$(ask "Optional ROM / firmware path (blank to skip)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi

    local -a dflags; display_flags dflags "${display}" "${qemu}"
    local -a netflags; append_user_network netflags "sunhme" "${combined_forwards}"
    local -a dbgflags; qemu_gdb_flags dbgflags

    local cmd=(
        "${qemu}"
        -machine sun4u
        -cpu "TI UltraSparc IIi"
        -m "${ram}"
        "${dflags[@]}"
        "${netflags[@]}"
        -rtc base=localtime
        "${dbgflags[@]}"
    )
    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"

    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi
    if [[ -n "${cdrom}" ]]; then
        cmd+=(-cdrom "${cdrom}" -boot d)
    fi

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/solaris-sparc-$(date +%Y%m%d-%H%M%S).log"
}

# ---------------------------------------------------------------------------
# PLATFORM: Windows XP
# ---------------------------------------------------------------------------
launch_windows_xp() {
    heading "Windows XP"
    log "Reference config: $(config_path "windows-xp")"

    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-i386")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 1024M / 4G)" "1024")
    local cores
    cores=$(ask "CPU cores" "2")
    local disk
    disk=$(pick_image "windows-xp")
    local cdrom
    cdrom=$(pick_cdrom "windows-xp")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
    local smb_share
    smb_share=$(ask "Optional host SMB share path for the guest" "${VM_SHARED_DIR}")
    if [[ -n "${smb_share}" ]]; then
        smb_share=$(ensure_shared_dir "${smb_share}")
    fi
    local port_forwards
    port_forwards=$(ask_port_forwards "")
    local gdb_forward
    gdb_forward=$(ask_gdb_bridge_forward "${DEFAULT_GDB_BRIDGE_PORT}")
    local combined_forwards
    combined_forwards=$(merge_csv_values "${port_forwards}" "${gdb_forward}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';', e.g. secondary-vga,vgamem_mb=16;secondary-vga,vgamem_mb=16)" "")
    local firmware_path
    firmware_path=$(ask "Optional ROM / firmware path (blank to skip)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi

    local -a dflags; display_flags dflags "${display}" "${qemu}"
    local -a netflags; append_user_network netflags "rtl8139" "${combined_forwards}" "${smb_share}"
    local -a dbgflags; qemu_gdb_flags dbgflags

    local cmd=(
        "${qemu}"
        -machine pc
        -cpu pentium3
        -m "${ram}"
        -smp "${cores}"
        "${dflags[@]}"
        -device VGA,vgamem_mb=16
        -device usb-ehci
        -device usb-kbd
        -device usb-mouse
        "${netflags[@]}"
        -rtc base=localtime
        "${dbgflags[@]}"
    )
    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"

    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi
    if [[ -n "${cdrom}" ]]; then
        cmd+=(-cdrom "${cdrom}" -boot d)
    fi

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/windows-xp-$(date +%Y%m%d-%H%M%S).log"
}

# ---------------------------------------------------------------------------
# PLATFORM: OpenStep x86
# ---------------------------------------------------------------------------
launch_openstep() {
    heading "OpenStep x86"
    log "Reference config: $(config_path "openstep")"

    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-i386")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 256M / 4G)" "256")
    local disk
    disk=$(pick_image "openstep")
    local cdrom
    cdrom=$(pick_cdrom "openstep")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
    local smb_share
    smb_share=$(ask "Optional host SMB share path for the guest" "")
    if [[ -n "${smb_share}" ]]; then
        smb_share=$(ensure_shared_dir "${smb_share}")
    fi
    local port_forwards
    port_forwards=$(ask_port_forwards "")
    local gdb_forward
    gdb_forward=$(ask_gdb_bridge_forward "${DEFAULT_GDB_BRIDGE_PORT}")
    local combined_forwards
    combined_forwards=$(merge_csv_values "${port_forwards}" "${gdb_forward}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';', e.g. secondary-vga,vgamem_mb=8;secondary-vga,vgamem_mb=8)" "")
    local firmware_path
    firmware_path=$(ask "Optional ROM / firmware path (blank to skip)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi

    local -a dflags; display_flags dflags "${display}" "${qemu}"
    local -a netflags; append_user_network netflags "ne2k_pci" "${combined_forwards}" "${smb_share}"
    local -a dbgflags; qemu_gdb_flags dbgflags

    local cmd=(
        "${qemu}"
        -machine pc
        -cpu pentium
        -m "${ram}"
        "${dflags[@]}"
        -device VGA,vgamem_mb=8
        "${netflags[@]}"
        -rtc base=localtime
        "${dbgflags[@]}"
    )
    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"

    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi
    if [[ -n "${cdrom}" ]]; then
        cmd+=(-cdrom "${cdrom}" -boot d)
    fi

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/openstep-$(date +%Y%m%d-%H%M%S).log"
}

# ---------------------------------------------------------------------------
# PLATFORM: Custom / Generic QEMU
# ---------------------------------------------------------------------------
launch_custom() {
    heading "Custom QEMU invocation"

    local arch
    arch=$(ask "QEMU system emulator (e.g. x86_64, i386, m68k, ppc, ppc64, sparc64, arm, arm64)" "x86_64")
    arch="${arch#qemu-system-}"
    [[ "${arch}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Invalid QEMU emulator suffix '${arch}'. Use values like x86_64, i386, m68k, ppc, or ppc64."
    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-${arch}")

    local machine
    machine=$(ask "Machine type (leave blank for default)" "")
    local cpu
    cpu=$(ask "CPU model (leave blank for default)" "")
    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 512M / 4G)" "${DEFAULT_RAM_MB}")
    local disk
    disk=$(pick_image "custom-${arch}")
    local cdrom
    cdrom=$(pick_cdrom "custom-${arch}")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses/none)" "${DEFAULT_DISPLAY}")
    local user_network
    user_network=$(ask "Enable user-mode networking? (yes/no)" "yes")
    local network_model
    network_model=$(ask "Network model (leave blank for user networking default)" "")
    local share_mode
    share_mode=$(ask "Shared folder mode (none/virtfs/smb)" "none")
    local shared_dir=""
    if [[ "${share_mode}" == "virtfs" || "${share_mode}" == "smb" ]]; then
        shared_dir=$(ask "Shared directory path" "${VM_SHARED_DIR}")
        shared_dir=$(ensure_shared_dir "${shared_dir}")
    fi
    local port_forwards
    port_forwards=$(ask_port_forwards "")
    local gdb_forward
    gdb_forward=$(ask_gdb_bridge_forward "${DEFAULT_GDB_BRIDGE_PORT}")
    local combined_forwards
    combined_forwards=$(merge_csv_values "${port_forwards}" "${gdb_forward}")
    local extra_displays
    extra_displays=$(ask "Extra display devices (blank to skip; separate multiple devices with ';', e.g. secondary-vga,vgamem_mb=16;VGA)" "")
    local firmware_path
    firmware_path=$(ask "Optional ROM / firmware path (blank to skip)" "")
    local firmware_mode="auto"
    if [[ -n "${firmware_path}" ]]; then
        firmware_mode=$(ask "Firmware attach mode (auto/bios/pflash)" "auto")
    fi
    local extra
    extra=$(ask "Extra QEMU flags (space-separated simple flags without values containing spaces)" "")

    local -a dflags; display_flags dflags "${display}" "${qemu}"
    local -a dbgflags; qemu_gdb_flags dbgflags
    local -a netflags=()
    if is_yes "${user_network}"; then
        if [[ "${share_mode}" == "smb" ]]; then
            append_user_network netflags "${network_model}" "${combined_forwards}" "${shared_dir}"
        else
            append_user_network netflags "${network_model}" "${combined_forwards}"
        fi
    fi
    # shellcheck disable=SC2206
    local -a extra_arr=()
    if [[ -n "${extra}" ]]; then
        # Word-split intentionally; values with spaces must be passed via env config files
        read -r -a extra_arr <<<"${extra}"
        local opt
        for opt in "${extra_arr[@]}"; do
            if [[ "${opt}" =~ ^-(drive|netdev|nic|machine|cpu|m|bios|device|smp|cdrom|hda|virtfs)$ ]]; then
                warn "Extra flag '${opt}' can override first-class launcher options."
            fi
        done
    fi

    local cmd=("${qemu}" -m "${ram}" "${dflags[@]}")
    [[ -n "${machine}" ]] && cmd+=(-machine "${machine}")
    [[ -n "${cpu}" ]]     && cmd+=(-cpu "${cpu}")
    [[ ${#netflags[@]} -gt 0 ]] && cmd+=("${netflags[@]}")
    [[ -n "${disk}" ]]    && cmd+=(-hda "${disk}")
    [[ -n "${cdrom}" ]]   && cmd+=(-cdrom "${cdrom}" -boot d)
    if [[ "${share_mode}" == "virtfs" && -n "${shared_dir}" ]]; then
        cmd+=(-virtfs "local,path=${shared_dir},mount_tag=shared,security_model=mapped-xattr")
    fi
    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"
    [[ ${#dbgflags[@]} -gt 0 ]] && cmd+=("${dbgflags[@]}")
    [[ ${#extra_arr[@]} -gt 0 ]] && cmd+=("${extra_arr[@]}")

    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/custom-${arch}-$(date +%Y%m%d-%H%M%S).log"
}

# ---------------------------------------------------------------------------
# UTM.app Integration
# ---------------------------------------------------------------------------

# Detect UTM.app installation
detect_utm() {
    if [[ -d "/Applications/UTM.app" ]]; then
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
# Option C: Debug & Network Sharing Functions
# ---------------------------------------------------------------------------

# Detect Netatalk (AppleShare) installation
detect_netatalk() {
    if command -v afpd &>/dev/null; then
        NETATALK_INSTALLED=true
        NETATALK_BIN="afpd"
    elif [[ -x "/opt/local/sbin/afpd" ]]; then
        NETATALK_INSTALLED=true
        NETATALK_BIN="/opt/local/sbin/afpd"
    elif [[ -x "/usr/local/sbin/afpd" ]]; then
        NETATALK_INSTALLED=true
        NETATALK_BIN="/usr/local/sbin/afpd"
    else
        NETATALK_INSTALLED=false
        NETATALK_BIN=""
    fi
    export NETATALK_INSTALLED NETATALK_BIN
}

# Detect GDB installation
detect_gdb() {
    if command -v gdb &>/dev/null; then
        GDB_INSTALLED=true
        GDB_BIN="gdb"
    elif command -v ggdb &>/dev/null; then
        GDB_INSTALLED=true
        GDB_BIN="ggdb"
    else
        GDB_INSTALLED=false
        GDB_BIN=""
    fi
    export GDB_INSTALLED GDB_BIN
}

# Find Netatalk/afpd binary
find_afpd_bin() {
    if command -v afpd &> /dev/null; then
        echo "$(command -v afpd)"
    elif [[ -x "/opt/local/sbin/afpd" ]]; then
        echo "/opt/local/sbin/afpd"
    elif [[ -x "/usr/local/sbin/afpd" ]]; then
        echo "/usr/local/sbin/afpd"
    else
        echo ""
    fi
}

# Start Netatalk share for AppleShare file sharing
start_netatalk_share() {
    local share_name="$1"
    local share_path="$2"
    local netatalk_config="/tmp/vm-assistant-netatalk.conf"

    detect_netatalk
    if [[ "$NETATALK_INSTALLED" != true ]]; then
        warn "Netatalk not installed. Install with: brew install netatalk or sudo port install netatalk"
        return 1
    fi

    mkdir -p "$share_path"

    cat > "$netatalk_config" << EOF
[Global]
  mimic model = RackMac
  uam list = uams_guest.so,uams_dhx.so,uams_dhx2.so
  guest account = guest
  log file = /tmp/vm-assistant-netatalk.log
  max connections = 20

[$share_name]
  path = $share_path
  valid users = @* guest
  rwlist = @* guest
  file perm = 0664
  directory perm = 0775
  cnid scheme = dbd
  aapl use sentry = no
EOF

    log "Starting Netatalk with config: $netatalk_config"
    log "Share: $share_name -> $share_path"

    # Kill any existing afpd
    pkill afpd 2>/dev/null || true
    sleep 1

    # Create private directory if needed
    mkdir -p /tmp/samba_private
    export ATLKD_PRI_DIR=/tmp/samba_private

    # Start afpd with custom config
    sudo "$NETATALK_BIN" -F "$netatalk_config" -d 2>>/tmp/vm-assistant-netatalk.log &
    local afpd_pid=$!
    echo "$afpd_pid" > /tmp/vm-assistant-netatalk.pid

    log "Netatalk started with PID: $afpd_pid"
    log "Share available via: afp://$(hostname):${DEFAULT_NETATALK_PORT}/$share_name"

    sleep 2
    if ps -p "$afpd_pid" > /dev/null 2>&1; then
        return 0
    else
        warn "Failed to start Netatalk. See /tmp/vm-assistant-netatalk.log"
        return 1
    fi
}

# Stop Netatalk share
stop_netatalk_share() {
    if [[ -f /tmp/vm-assistant-netatalk.pid ]]; then
        local pid=$(cat /tmp/vm-assistant-netatalk.pid)
        kill "$pid" 2>/dev/null || true
        rm -f /tmp/vm-assistant-netatalk.pid
        log "Netatalk stopped"
    fi
}

# Configure Netatalk with proper config files
configure_netatalk() {
    heading "Configuring Netatalk (AFP)"
    
    detect_netatalk
    if [[ "$NETATALK_INSTALLED" != true ]]; then
        warn "Netatalk not installed. Install with: brew install netatalk or sudo port install netatalk"
        return 1
    fi
    
    local current_user=$(whoami)
    local netatalk_config=""
    
    # Determine config location
    if [[ -d "/opt/local/etc/netatalk" ]]; then
        netatalk_config="/opt/local/etc/netatalk/afpd.conf"
    elif [[ -d "/usr/local/etc/netatalk" ]]; then
        netatalk_config="/usr/local/etc/netatalk/afpd.conf"
    else
        netatalk_config="${CONFIG_DIR}/netatalk/afpd.conf"
        ensure_dir "$(dirname "$netatalk_config")"
    fi
    
    # Backup existing config
    if [[ -f "$netatalk_config" ]]; then
        cp "$netatalk_config" "${netatalk_config}.bak.$(date +%Y%m%d%H%M%S)"
        log "Backed up existing config to: ${netatalk_config}.bak.*"
    fi
    
    ensure_dir "$(dirname "$netatalk_config")"
    
    # Create Netatalk configuration
    cat > "$netatalk_config" << EOF
[Global]
   mimic model = RackMac
   vol preset = VM_Shares
   max connections = 10

[VM_Shares]
   path = ${SHARED_DIR}
   cnidscheme = dbd
   vol size limit = 0
   valid users = ${current_user}
   rwlist = ${current_user}

[VM_Disks]
   path = ${DISK_DIR}
   cnidscheme = dbd
   vol size limit = 0
   valid users = ${current_user}
   rwlist = ${current_user}

[VM_ISOs]
   path = ${ISO_DIR}
   cnidscheme = dbd
   vol size limit = 0
   valid users = ${current_user}
   rolist = ${current_user}
EOF
    
    # Create AppleVolumes.default
    local apple_volumes_dir="$(dirname "$netatalk_config")"
    local apple_volumes="${apple_volumes_dir}/AppleVolumes.default"
    ensure_dir "$apple_volumes_dir"
    
    cat > "$apple_volumes" << EOF
${SHARED_DIR} "VM RAMDISK" options:usedots,noadouble
${DISK_DIR} "VM Disques" options:usedots,noadouble
${ISO_DIR} "VM ISOs" options:usedots,noadouble,ro
EOF
    
    log "Netatalk configuration created: $netatalk_config"
    log "AppleVolumes configuration created: $apple_volumes"
    
    # Try to start Netatalk via launchd
    local netatalk_launchd_plist=""
    if [[ -f "/Library/LaunchDaemons/org.macports.afpd.plist" ]]; then
        netatalk_launchd_plist="/Library/LaunchDaemons/org.macports.afpd.plist"
    elif [[ -f "/Library/LaunchDaemons/org.netatalk.afpd.plist" ]]; then
        netatalk_launchd_plist="/Library/LaunchDaemons/org.netatalk.afpd.plist"
    fi
    
    if [[ -n "$netatalk_launchd_plist" ]]; then
        log "Using launchd for Netatalk..."
        if launchctl print "system/org.macports.afpd" &>/dev/null || \
           launchctl print "system/org.netatalk.afpd" &>/dev/null; then
            sudo launchctl unload "$netatalk_launchd_plist" 2>/dev/null
            sleep 1
        fi
        sudo launchctl load "$netatalk_launchd_plist"
        log "Netatalk started via launchd"
    else
        local afpd_bin=$(find_afpd_bin)
        if [[ -z "$afpd_bin" ]]; then
            warn "afpd binary not found"
            return 1
        fi
        log "Manual Netatalk startup..."
        if pgrep -x "afpd" &>/dev/null; then
            sudo killall afpd 2>/dev/null || true
            sleep 1
        fi
        sudo "$afpd_bin" -F "$netatalk_config" 2>/dev/null &
        log "Netatalk started manually"
    fi
    
    return 0
}

# Find Samba binary
find_smbd_bin() {
    if command -v smbd &> /dev/null; then
        echo "$(command -v smbd)"
    elif [[ -x "/opt/local/sbin/smbd" ]]; then
        echo "/opt/local/sbin/smbd"
    elif [[ -x "/usr/local/sbin/smbd" ]]; then
        echo "/usr/local/sbin/smbd"
    else
        echo ""
    fi
}

# Configure Samba with proper config files
configure_samba() {
    heading "Configuring Samba"
    
    if ! command -v smbd &>/dev/null; then
        warn "Samba not installed. Install with: brew install samba or sudo port install samba4"
        return 1
    fi
    
    local current_user=$(whoami)
    local samba_config=""
    local system_smbd=""
    
    # Handle system smbd
    if pgrep -x "smbd" &>/dev/null; then
        system_smbd=$(ps aux | grep "[s]mbd" | grep -v grep | head -1 | awk '{print $NF}')
        if [[ "$system_smbd" == "/usr/sbin/smbd"* ]]; then
            log "System smbd detected, disabling..."
            if [[ -f "/System/Library/LaunchDaemons/com.apple.smbd.plist" ]]; then
                sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist 2>/dev/null || true
                sleep 1
            fi
            sudo killall /usr/sbin/smbd 2>/dev/null || true
            sleep 1
            samba_config="${CONFIG_DIR}/samba/smb.conf"
            ensure_dir "$(dirname "$samba_config")"
            log "System Samba service disabled"
        fi
    fi
    
    # Determine config path
    if [[ -z "$samba_config" ]]; then
        if [[ -d "/opt/local/etc/samba" && -w "/opt/local/etc/samba" ]]; then
            samba_config="/opt/local/etc/samba/smb.conf"
        elif [[ -d "/usr/local/etc/samba" && -w "/usr/local/etc/samba" ]]; then
            samba_config="/usr/local/etc/samba/smb.conf"
        else
            samba_config="${CONFIG_DIR}/samba/smb.conf"
            ensure_dir "$(dirname "$samba_config")"
        fi
    fi
    
    # Backup existing config
    if [[ -f "$samba_config" ]]; then
        cp "$samba_config" "${samba_config}.bak.$(date +%Y%m%d%H%M%S)"
        log "Backed up existing Samba config"
    fi
    
    ensure_dir "$(dirname "$samba_config")"
    
    # Create Samba private directory
    local samba_private_dir="/tmp/samba_private"
    ensure_dir "$samba_private_dir"
    sudo chmod 1777 "$samba_private_dir" 2>/dev/null || true
    sudo chown root:wheel "$samba_private_dir" 2>/dev/null || true
    log "Samba private directory: $samba_private_dir"
    
    # Handle Homebrew Samba
    if [[ -d "/usr/local/Cellar/samba" ]]; then
        local samba_version=$(ls /usr/local/Cellar/samba/ | grep -E '^[0-9]+\.[0-9]+' | sort -V | tail -1)
        if [[ -n "$samba_version" ]]; then
            local homebrew_samba_private="/usr/local/Cellar/samba/${samba_version}/private"
            if [[ ! -L "$homebrew_samba_private" && ! -d "$homebrew_samba_private" ]]; then
                sudo mkdir -p "$(dirname "$homebrew_samba_private")" 2>/dev/null || true
                sudo ln -sf "$samba_private_dir" "$homebrew_samba_private" 2>/dev/null || true
                log "Symbolic link: $homebrew_samba_private -> $samba_private_dir"
            fi
        fi
    fi
    
    # Create Samba configuration
    local netbios_name=$(hostname | cut -c1-15)
    cat > "$samba_config" << EOF
[global]
   workgroup = WORKGROUP
   server string = VM Assistant Samba Server
   netbios name = ${netbios_name}
   security = user
   map to guest = bad user
   guest account = ${current_user}
   dns proxy = no
   private dir = ${samba_private_dir}
   lock directory = ${samba_private_dir}
   pid directory = ${samba_private_dir}
   log file = ${samba_private_dir}/log.smbd

[VM_Shares]
   comment = VM Assistant Share
   path = ${SHARED_DIR}
   browsable = yes
   read only = no
   guest ok = yes
   create mask = 0777
   directory mask = 0777
   force user = ${current_user}

[VM_Disks]
   comment = VM Disks
   path = ${DISK_DIR}
   browsable = yes
   read only = no
   guest ok = yes
   create mask = 0777
   directory mask = 0777
   force user = ${current_user}

[VM_ISOs]
   comment = VM ISOs
   path = ${ISO_DIR}
   browsable = yes
   read only = yes
   guest ok = yes
   create mask = 0755
   directory mask = 0755
   force user = ${current_user}
EOF
    
    log "Samba configuration created: $samba_config"
    log "Start Samba with: sudo smbd -D -s $samba_config"
    
    return 0
}

# ---------------------------------------------------------------------------
# Dependency Checking Functions (from vm-assistant-macports.sh)
# ---------------------------------------------------------------------------

# Check if MacPorts is installed
check_macports() {
    if command -v port &>/dev/null; then
        return 0
    elif [[ -d "/opt/local" && -f "/opt/local/bin/port" ]]; then
        return 0
    else
        return 1
    fi
}

# Check if Homebrew is installed
check_homebrew() {
    if command -v brew &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Verify all dependencies
verify_dependencies() {
    heading "Dependency Verification"
    
    local missing_deps=()
    local found_deps=()
    
    # Check package managers
    if check_macports; then
        log "✓ MacPorts is installed"
        found_deps+=("MacPorts")
    else
        warn "✗ MacPorts is not installed"
        missing_deps+=("MacPorts")
    fi
    
    if check_homebrew; then
        log "✓ Homebrew is installed"
        found_deps+=("Homebrew")
    else
        warn "✗ Homebrew is not installed"
        missing_deps+=("Homebrew")
    fi
    
    # Check QEMU binaries
    local qemu_deps=(
        "qemu-system-x86_64"
        "qemu-system-i386"
        "qemu-system-ppc"
        "qemu-system-ppc64"
        "qemu-system-m68k"
        "qemu-system-arm"
        "qemu-system-sparc"
        "qemu-system-sparc64"
    )
    
    local qemu_installed=false
    for qemu_bin in "${qemu_deps[@]}"; do
        if command -v "$qemu_bin" &>/dev/null; then
            log "✓ Found: $qemu_bin"
            qemu_installed=true
        fi
    done
    
    if ! $qemu_installed; then
        warn "✗ No QEMU versions found"
        missing_deps+=("QEMU")
    fi
    
    # Check other dependencies
    local other_deps=("samba" "netatalk" "XQuartz")
    
    for dep in "${other_deps[@]}"; do
        case $dep in
            "samba")
                if command -v smbd &>/dev/null; then
                    log "✓ Samba is installed"
                else
                    warn "✗ Samba is not installed"
                    missing_deps+=("Samba")
                fi
                ;;
            "netatalk")
                if command -v afpd &>/dev/null; then
                    log "✓ Netatalk is installed"
                else
                    warn "✗ Netatalk is not installed"
                    missing_deps+=("Netatalk")
                fi
                ;;
            "XQuartz")
                if [[ -d "/Applications/Utilities/XQuartz.app" ]]; then
                    log "✓ XQuartz is installed"
                else
                    warn "✗ XQuartz is not installed"
                    missing_deps+=("XQuartz")
                fi
                ;;
        esac
    done
    
    # Check UTM.app
    if [[ -d "/Applications/UTM.app" ]]; then
        log "✓ UTM.app is installed"
    else
        warn "✗ UTM.app is not installed"
        missing_deps+=("UTM.app")
    fi
    
    # Summary
    echo ""
    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        log "✅ All dependencies are installed!"
        return 0
    else
        warn "❌ Missing dependencies: ${missing_deps[*]}"
        if [[ " ${missing_deps[*]} " == *"MacPorts"* || " ${missing_deps[*]} " == *"Homebrew"* ]]; then
            echo ""
            log "Install package managers:"
            log "  MacPorts: https://www.macports.org/install.php"
            log "  Homebrew: https://brew.sh"
        fi
        return 1
    fi
}

# Configure XQuartz for X11 display
configure_xquartz() {
    heading "Configuring XQuartz"
    
    if [[ ! -d "/Applications/Utilities/XQuartz.app" ]]; then
        warn "XQuartz not installed"
        log "Download from: https://www.xquartz.org"
        return 1
    fi
    
    [[ ! -f "$HOME/.Xauthority" ]] && touch "$HOME/.Xauthority" && chmod 600 "$HOME/.Xauthority"
    export DISPLAY=":0"
    
    xhost +local: &>/dev/null || xhost +local:
    log "XQuartz configured for local connections"
    
    if pgrep -x "Xquartz" &>/dev/null; then
        log "XQuartz is running"
    else
        warn "XQuartz is not running"
        log "Start with: open -a XQuartz"
    fi
    return 0
}

# Configure RAM disk for sharing
configure_ramdisk() {
    heading "Configuring RAMDISK"
    ensure_dir "$SHARE_DIR"
    sudo chmod 1777 "$SHARE_DIR" 2>/dev/null || true
    sudo chown root:wheel "$SHARE_DIR" 2>/dev/null || true
    
    local disk_usage=$(df -h "$SHARE_DIR" 2>/dev/null | tail -1 | awk '{print $4}')
    [[ -n "$disk_usage" ]] && log "Available space: $disk_usage"
    log "RAMDISK configured: $SHARE_DIR"
    return 0
}

# Test individual Samba connection with mounting
test_samba_connection() {
    local host="$1"
    local share="$2"
    local username="$3"
    local password="$4"
    
    heading "Testing Samba Connection: smb://$host/$share"
    
    if ! command -v smbutil &>/dev/null; then
        warn "smbutil not found. Install Samba client."
        return 1
    fi
    
    # Test connection
    if smbutil statshares -a "$username" -p "$password" "//$host" 2>/dev/null | grep -q "$share"; then
        log "✓ Samba connection successful"
        
        # Test mounting
        local mount_point="/tmp/vm_test_samba_$$"
        mkdir -p "$mount_point"
        if mount_smbfs -N -d 777 "//${username}@${host}/${share}" "$mount_point" 2>/dev/null; then
            log "✓ Samba mount successful"
            ls -la "$mount_point" | head -5
            umount "$mount_point" 2>/dev/null || true
            rmdir "$mount_point" 2>/dev/null || true
            return 0
        else
            warn "✗ Samba mount failed (but connection OK)"
            rmdir "$mount_point" 2>/dev/null || true
            return 1
        fi
    else
        warn "✗ Samba connection failed"
        return 1
    fi
}

# Test individual Netatalk connection with mounting
test_netatalk_connection() {
    local host="$1"
    local share="$2"
    
    heading "Testing Netatalk Connection: afp://$host/$share"
    
    # Test with mount_afp
    if command -v mount_afp &>/dev/null; then
        local mount_point="/tmp/vm_test_afp_$$"
        mkdir -p "$mount_point"
        if mount_afp "afp://$host/$share" "$mount_point" 2>/dev/null; then
            log "✓ Netatalk connection successful"
            ls -la "$mount_point" | head -5
            umount "$mount_point" 2>/dev/null || true
            rmdir "$mount_point" 2>/dev/null || true
            return 0
        else
            warn "✗ Netatalk mount failed"
            rmdir "$mount_point" 2>/dev/null || true
            return 1
        fi
    else
        warn "mount_afp not found. Try: open afp://$host/$share"
        return 1
    fi
}

# Test individual SSH connection
test_ssh_connection() {
    local host="$1"
    local port="$2"
    
    heading "Testing SSH Connection: $host:$port"
    
    if ! command -v ssh &>/dev/null; then
        warn "SSH client not found"
        return 1
    fi
    
    if ssh -p "$port" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" echo "SSH_TEST_OK" 2>/dev/null | grep -q "SSH_TEST_OK"; then
        log "✓ SSH connection successful"
        return 0
    else
        warn "✗ SSH connection failed"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Backup and Restore Functions (from vm-assistant.sh)
# ---------------------------------------------------------------------------

# Create backup of all configurations
backup_configurations() {
    heading "Backup Configurations"
    
    local backup_dir="${SCRIPT_DIR}/backups"
    local backup_file="${backup_dir}/vm-assistant-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    ensure_dir "${backup_dir}"
    
    log "Creating backup of ${CONFIG_DIR} to ${backup_file}"
    
    if tar -czf "${backup_file}" "${CONFIG_DIR}" 2>/dev/null; then
        log "✅ Backup created: ${backup_file}"
        return 0
    else
        warn "❌ Failed to create backup"
        return 1
    fi
}

# List available backups
list_backups() {
    heading "Available Backups"
    
    local backup_dir="${SCRIPT_DIR}/backups"
    local backups=()
    
    if [[ -d "${backup_dir}" ]]; then
        while IFS= read -r -d '' backup_file; do
            [[ "$backup_file" == *.tar.gz ]] && backups+=("$backup_file")
        done < <(find "${backup_dir}" -maxdepth 1 -type f -name "vm-assistant-backup-*.tar.gz" -print0 2>/dev/null)
        
        if [[ ${#backups[@]} -gt 0 ]]; then
            local i=1
            for backup in "${backups[@]}"; do
                echo "  [$i] $(basename "$backup")"
                ((i++)) || true
            done
        else
            log "No backups found"
        fi
    else
        log "No backup directory found"
    fi
}

# Restore from backup
restore_configuration() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        warn "Backup not found: $backup_file"
        return 1
    fi
    
    heading "Restore Configuration from $backup_file"
    
    # Remove current config
    if [[ -d "${CONFIG_DIR}" ]]; then
        log "Removing current configuration..."
        rm -rf "${CONFIG_DIR}"
    fi
    
    # Restore from backup
    log "Restoring configuration..."
    if tar -xzf "$backup_file" -C "$HOME" 2>/dev/null; then
        log "✅ Configuration restored from: $backup_file"
        return 0
    else
        warn "❌ Failed to restore configuration"
        return 1
    fi
}

# Backup and restore interactive menu
backup_restore_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "backup_restore_menu function requires interactive mode"
        return 1
    fi
    
    heading "Backup and Restore Menu"
    
    echo "Available backups:"
    list_backups
    
    local backup_dir="${SCRIPT_DIR}/backups"
    local backups=()
    
    if [[ -d "${backup_dir}" ]]; then
        while IFS= read -r -d '' backup_file; do
            [[ "$backup_file" == *.tar.gz ]] && backups+=("$backup_file")
        done < <(find "${backup_dir}" -maxdepth 1 -type f -name "vm-assistant-backup-*.tar.gz" -print0 2>/dev/null)
    fi
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log "No backups available to restore"
        return 0
    fi
    
    echo ""
    backup_choice=$(ask "Select backup to restore (number)" "")
    
    if [[ -n "$backup_choice" && "$backup_choice" =~ ^[0-9]+$ && $backup_choice -ge 1 && $backup_choice -le ${#backups[@]} ]]; then
        restore_configuration "${backups[$((backup_choice-1))]}"
    else
        log "No backup selected"
    fi
}

# ---------------------------------------------------------------------------
# Connection Testing Functions
# Test all sharing services (Samba, Netatalk, local)
test_sharing_services() {
    heading "Sharing Services Test"
    
    local share_name="${NETATALK_SHARE_NAME:-VM_Shares}"
    local volatile_hd="${HOME}/vm_assistant/shares"
    local results=()
    local ip_address
    
    # Get local IP address (non-loopback)
    if command -v ifconfig &>/dev/null; then
        ip_address=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
    else
        ip_address="localhost"
    fi
    
    echo "Local IP: ${ip_address:-Not detected}"
    echo ""
    
    # Test 1: Local share
    echo "[1] Local share (${volatile_hd})..."
    if [[ -d "${volatile_hd}" && -w "${volatile_hd}" ]]; then
        log "✓ Local share: OK"
        results+=("✓ Local share: OK")
    else
        warn "✗ Local share: FAILED"
        results+=("✗ Local share: FAILED")
    fi
    
    # Test 2: Samba
    echo ""
    echo "[2] Samba..."
    if pgrep -x "smbd" &>/dev/null; then
        log "✓ smbd is running"
        results+=("✓ smbd is running")
        
        if command -v smbclient &>/dev/null; then
            if smbclient -L localhost -U% 2>/dev/null | grep -q "${share_name}"; then
                log "✓ Samba shares visible"
                results+=("✓ Samba shares visible")
            else
                warn "✗ Samba shares not visible"
                results+=("✗ Samba shares not visible")
            fi
            
            if smbclient "//localhost/${share_name}" -U"$(whoami)" -N -c "ls" 2>/dev/null | grep -q "blocks"; then
                log "✓ Access to ${share_name}: OK"
                results+=("✓ Access to ${share_name}: OK")
            else
                warn "⚠️  Access to ${share_name}: needs authentication"
                results+=("⚠️  Access to ${share_name}: needs authentication")
            fi
        fi
    else
        warn "✗ smbd is not running"
        results+=("✗ smbd is not running")
    fi
    
    # Test 3: Netatalk
    echo ""
    echo "[3] Netatalk..."
    if pgrep -x "afpd" &>/dev/null; then
        log "✓ afpd is running"
        results+=("✓ afpd is running")
        
        if command -v afpclient &>/dev/null; then
            if afpclient -l localhost 2>/dev/null | grep -q "${share_name}"; then
                log "✓ Netatalk shares visible"
                results+=("✓ Netatalk shares visible")
            else
                warn "✗ Netatalk shares not visible"
                results+=("✗ Netatalk shares not visible")
            fi
        else
            warn "⚠️  afpclient not available - cannot test Netatalk shares"
            results+=("⚠️  afpclient not available - cannot test Netatalk shares")
        fi
    else
        warn "✗ afpd is not running"
        results+=("✗ afpd is not running")
    fi
    
    # Display access information
    echo ""
    echo "Access URLs:"
    if [[ -n "${ip_address}" ]]; then
        log "  Samba: smb://${ip_address}/${share_name}"
        log "  AFP:    afp://${ip_address}/${share_name}"
    else
        log "  Samba: smb://localhost/${share_name}"
        log "  AFP:    afp://localhost/${share_name}"
    fi
    log "  Local:  ${volatile_hd}"
    
    # Summary
    echo ""
    heading "Test Summary"
    for result in "${results[@]}"; do
        echo "  ${result}"
    done
    
    return 0
}

# Download ISO from predefined URLs or custom URL
download_iso() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "download_iso function requires interactive mode"
        return 1
    fi
    
    heading "Download ISO Image"
    
    ensure_dir "${ISO_DIR}"
    
    local iso_urls=(
        "https://cdimage.debian.org/mirror/cdimage/archive/11.6.0/amd64/iso-dvd/debian-11.6.0-amd64-DVD-1.iso|Debian 11.6.0 amd64"
        "https://cdimage.ubuntu.com/releases/22.04/release/ubuntu-22.04-desktop-amd64.iso|Ubuntu 22.04 Desktop"
        "https://archlinux.org/iso/latest/archlinux-x86_64.iso|Arch Linux Latest"
        "https://download.freebsd.org/ftp/releases/amd64/amd64/ISO-IMAGES/13.2/FreeBSD-13.2-RELEASE-amd64-disc1.iso|FreeBSD 13.2"
        "https://cdn.netbsd.org/pub/NetBSD/NetBSD-10.0/amd64cd.iso|NetBSD 10.0"
        "https://download.opensuse.org/tumbleweed/iso/openSUSE-Tumbleweed-DVD-x86_64-Current.iso|openSUSE Tumbleweed"
        "https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04-desktop-amd64.iso|Ubuntu 24.04 Desktop"
        "https://cdimage.ubuntu.com/releases/jammy/release/ubuntu-22.04.4-desktop-amd64.iso|Ubuntu 22.04.4 Desktop"
    )
    
    log "Predefined ISO URLs:"
    log "-------------------"
    for i in "${!iso_urls[@]}"; do
        IFS='|' read -r url desc <<< "${iso_urls[$i]}"
        log "  [$((i+1))] $desc"
    done
    
    log ""
    url_choice=$(ask "Select ISO (number), enter custom URL, or press Enter to cancel" "")
    
    if [[ -z "$url_choice" ]]; then
        log "ISO download cancelled."
        return 0
    fi
    
    local iso_url=""
    local iso_name=""
    
    if [[ "$url_choice" =~ ^[0-9]+$ ]] && [ "$url_choice" -ge 1 ] && [ "$url_choice" -le ${#iso_urls[@]} ]; then
        IFS='|' read -r iso_url iso_name <<< "${iso_urls[$((url_choice-1))]}"
    elif [[ "$url_choice" == http* || "$url_choice" == ftp* ]]; then
        iso_url="$url_choice"
        iso_name=$(basename "$url_choice")
    else
        warn "Invalid choice"
        return 1
    fi
    
    local output_file="${ISO_DIR}/${iso_name}"
    
    # Check if file already exists
    if [[ -f "$output_file" ]]; then
        overwrite=$(ask "File already exists: ${output_file}. Overwrite?" "n")
        if [[ "$overwrite" != "y" ]]; then
            log "Download cancelled."
            return 0
        fi
    fi
    
    log "Downloading: ${iso_url}"
    log "Destination: ${output_file}"
    
    if command -v curl &> /dev/null; then
        curl -L -o "$output_file" "$iso_url" -# || {
            die "Download failed"
        }
    elif command -v wget &> /dev/null; then
        wget -O "$output_file" "$iso_url" || {
            die "Download failed"
        }
    else
        die "Neither curl nor wget found. Please install one of them."
    fi
    
    log "ISO downloaded successfully: ${output_file}"
    return 0
}

# Detect available ISOs across multiple directories
detect_available_isos() {
    heading "Detecting Available ISOs"
    
    local search_dirs=(
        "${ISO_DIR}"
        "${VM_IMAGE_DIR}"
        "${HOME}/Downloads"
        "${SCRIPT_DIR}"
    )
    
    local global_available_isos=()
    local global_available_isos_paths=()
    
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log "Scanning: ${dir}"
            while IFS= read -r -d "" file; do
                if [[ "$file" == *.iso ]] || [[ "$file" == *.ISO ]] || [[ "$file" == *.dmg ]] || [[ "$file" == *.DMG ]]; then
                    local filename=$(basename "$file")
                    local size=$(du -h "$file" 2>/dev/null | cut -f1)
                    local description="$filename ($size)"
                    
                    # Detect ISO type
                    case "$filename" in
                        *"Mac"*|*"mac"*|*"OSX"*|*"Snow Leopard"*|*"Leopard"*) 
                            description="[Mac OS] $filename ($size)" ;;
                        *"Windows"*|*"win"*|*"Win"*) 
                            description="[Windows] $filename ($size)" ;;
                        *"Linux"*|*"linux"*|*"Ubuntu"*|*"Debian"*|*"Fedora"*|*"Arch"*) 
                            description="[Linux] $filename ($size)" ;;
                        *"DOS"*|*"dos"*|*"MS-DOS"*) 
                            description="[DOS] $filename ($size)" ;;
                        *"FreeBSD"*|*"BSD"*) 
                            description="[BSD] $filename ($size)" ;;
                        *"Solaris"*|*"solaris"*) 
                            description="[Solaris] $filename ($size)" ;;
                        *"Haiku"*|*"haiku"*) 
                            description="[Haiku] $filename ($size)" ;;
                        *"Atari"*|*"atari"*) 
                            description="[Atari] $filename ($size)" ;;
                        *"Amiga"*|*"amiga"*) 
                            description="[Amiga] $filename ($size)" ;;
                    esac
                    
                    # Avoid duplicates
                    local already_found=false
                    for existing_path in "${global_available_isos_paths[@]}"; do
                        if [[ "$existing_path" == "$file" ]]; then
                            already_found=true
                            break
                        fi
                    done
                    
                    if [[ "$already_found" == false ]]; then
                        global_available_isos+=("$description")
                        global_available_isos_paths+=("$file")
                    fi
                fi
            done < <(find "$dir" -maxdepth 2 -type f \( -name "*.iso" -o -name "*.ISO" -o -name "*.dmg" -o -name "*.DMG" \) -print0 2>/dev/null)
        fi
    done
    
    if [[ ${#global_available_isos_paths[@]} -eq 0 ]]; then
        log "No ISOs found in any directory."
        return 1
    else
        log "Found ${#global_available_isos_paths[@]} ISO(s):"
        for i in "${!global_available_isos_paths[@]}"; do
            log "  [$((i+1))] ${global_available_isos[$i]}"
        done
        return 0
    fi
}

# Detect available architectures from installed QEMU
detect_available_architectures() {
    heading "Detecting Available QEMU Architectures"
    
    log "Checking for installed QEMU system emulators..."
    
    local available_archs=()
    local arch_descriptions=()
    
    # Check for various QEMU system emulators
    local qemu_archs=(
        "m68k:Motorola 68000 (Amiga, Atari ST, Mac 68k)"
        "ppc:PowerPC 32-bit (MacOS 7.5-9.2.2)"
        "ppc64:PowerPC 64-bit (Mac OS X)"
        "i386:x86 32-bit (DOS, early Windows)"
        "x86_64:x86 64-bit (Modern Linux, Windows)"
        "sparc:SPARC 32-bit"
        "sparc64:SPARC 64-bit"
        "arm:ARM 32-bit"
        "arm64:ARM 64-bit (Raspberry Pi, modern systems)"
        "mips:MIPS architecture"
        "mips64:MIPS 64-bit"
        "riscv32:RISC-V 32-bit"
        "riscv64:RISC-V 64-bit"
        "sh4:SuperH SH-4"
        "xtensa:Xtensa architecture"
    )
    
    for arch_entry in "${qemu_archs[@]}"; do
        IFS=':' read -r arch desc <<< "$arch_entry"
        if command -v "qemu-system-${arch}" &> /dev/null; then
            available_archs+=("$arch")
            arch_descriptions+=("$desc")
        fi
    done
    
    if [[ ${#available_archs[@]} -eq 0 ]]; then
        log "No QEMU system emulators found."
        return 1
    else
        log "Available architectures (${#available_archs[@]}):"
        for i in "${!available_archs[@]}"; do
            log "  ${available_archs[$i]} - ${arch_descriptions[$i]}"
        done
        return 0
    fi
}

# Export VM to UTM format
export_utm() {
    local vm_name="$1"
    local vm_base_dir=""
    local config_file=""
    
    # Search for VM config in the new structure (vms/VM_NAME_PLATFORM/conf/)
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            config_file="$file"
            vm_base_dir=$(dirname "$(dirname "${config_file}")")  # Get VM base directory
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)

    [[ -d "${vm_base_dir}" ]] || die "VM directory not found: ${vm_name}"
    [[ -f "${config_file}" ]] || die "VM config not found: ${vm_name}.conf"

    source "${config_file}"

    # Determine UTM architecture
    local utm_arch=""
    case "${QEMU_ARCH:-${arch}}" in
        ppc|ppc64)   utm_arch="ppc" ;;
        x86_64|i386) utm_arch="x86_64" ;;
        arm64|arm)   utm_arch="arm64" ;;
        sparc64|sparc) utm_arch="sparc64" ;;
        *) die "Unsupported architecture for UTM: ${QEMU_ARCH:-${arch}}" ;;
    esac

    # Determine UTM OS type
    local utm_os_type="linux"
    case "${QEMU_OS:-${os}}" in
        macos9|macos-9)     utm_os_type="macOS9" ;;
        macosx|macos-x)     utm_os_type="macOS10.4" ;;
        macos)             utm_os_type="macOS10.5" ;;
        haiku)             utm_os_type="haiku" ;;
        windows|windows-xp) utm_os_type="windows" ;;
        dos)               utm_os_type="dos" ;;
        *)                 utm_os_type="linux" ;;
    esac

    # Create UTM config JSON
    local utm_config_file="${conf_dir}/config.json"
    
    log "Exporting UTM configuration to: ${utm_config_file}"
    
    # Create a basic UTM configuration
    cat > "${utm_config_file}" << EOF
{
  "name": "${vm_name}",
  "target": "${utm_arch}",
  "operatingSystem": "${utm_os_type}",
  "memory": ${QEMU_RAM:-${ram}},
  "hardware": {
    "cpuCores": ${QEMU_SMP:-1},
    "network": {
      "mode": "shared",
      "interface": "${QEMU_NETWORK_MODEL:-e1000}"
    }
  },
  "removableMedia": {
    "cdrom": {
      "imagePath": "${QEMU_CDROM:-}"
    }
  },
  "sharing": {
    "enabled": true,
    "directory": "${VM_SHARED_DIR}"
  }
}
EOF

    log "UTM configuration exported to: ${utm_config_file}"
    log "You can import this in UTM.app by:"
    log "1. Open UTM.app"
    log "2. Click '+' to create new VM"
    log "3. Select 'Import Existing Virtual Machine'"
    log "4. Choose the exported configuration"
}

# Create UTM VM configuration
create_utm_vm() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "create_utm_vm function requires interactive mode"
        return 1
    fi
    
    heading "Creating UTM VM"
    
    detect_utm || { warn "UTM.app not found. Please install UTM.app from https://mac.getutm.app/"; return 1; }

    local vm_name
    vm_name=$(ask "VM name" "")
    [[ -z "${vm_name}" ]] && { warn "VM name cannot be empty"; return 1; }

    # VM directory - use new bundled structure with platform
    # We'll determine the platform from the architecture selection later
    local vm_platform=""
    local vm_dir=""

    # OS Type
    echo "Select OS Type:"
    echo "  1) macOS 9"
    echo "  2) macOS 10.4 (Tiger)"
    echo "  3) macOS 10.5 (Leopard)"
    echo "  4) Linux"
    echo "  5) Windows"
    echo "  6) DOS"
    utm_os_type_choice=$(ask "OS Type" "1")
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

    # Architecture
    echo "Select Architecture:"
    echo "  1) PowerPC (ppc)"
    echo "  2) x86_64"
    echo "  3) ARM64"
    echo "  4) ARM"
    echo "  5) SPARC"
    echo "  6) SPARC64"
    utm_arch_choice=$(ask "Architecture" "1")
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

    # Create VM directory with platform and subdirectories
    vm_platform="${utm_architecture}"
    vm_base_dir="${VM_DIR}/${vm_name}_${vm_platform}"
    vm_dir="${vm_base_dir}"
    local conf_dir="${vm_base_dir}/conf"
    local qcow2_dir="${vm_base_dir}/qcow2"
    local sh_dir="${vm_base_dir}/sh"
    local rom_dir="${vm_base_dir}/rom"
    
    mkdir -p "${conf_dir}" "${qcow2_dir}" "${sh_dir}" "${rom_dir}"
    log "Creating UTM VM in: ${vm_base_dir}"

    # Display mode
    utm_display_choice=$(ask "Display Mode (1=GUI/2=Terminal)" "1")
    local utm_display=""
    case ${utm_display_choice} in
        1) utm_display="gui" ;;
        2) utm_display="terminal" ;;
        *) utm_display="gui" ;;
    esac

    # File sharing
    utm_sharing=$(ask "Enable file sharing" "n")
    local utm_sharing_path=""
    if [[ "${utm_sharing}" == "y" ]]; then
        utm_sharing_path_input=$(ask "Share path" "${SHARE_DIR}")
        utm_sharing_path="${utm_sharing_path_input:-${SHARE_DIR}}"
    fi

    # Clipboard sharing
    utm_clipboard=$(ask "Enable clipboard sharing" "n")

    # Memory
    local utm_memory
    utm_memory=$(ask_ram_size "RAM size (MiB)" "512")

    # CPU cores
    local utm_cores
    utm_cores=$(ask "CPU cores" "1")

    # Network
    utm_vnc=$(ask "Enable VNC" "n")
    local utm_vnc_port=5900
    if [[ "${utm_vnc}" == "y" ]]; then
        utm_vnc_port_input=$(ask "VNC port" "${utm_vnc_port}")
        utm_vnc_port="${utm_vnc_port_input:-${utm_vnc_port}}"
    fi

    # Create UTM configuration file
    local utm_config_file="${conf_dir}/config.json"
    cat > "${utm_config_file}" << EOF
{
  "name": "${vm_name}",
  "target": "${utm_architecture}",
  "operatingSystem": "${utm_os_type}",
  "memory": ${utm_memory},
  "hardware": {
    "cpuCores": ${utm_cores},
    "network": {
      "mode": "shared"
    }
  },
  "removableMedia": {},
  "sharing": {
    "enabled": ${utm_sharing},
    "directory": "${utm_sharing_path}",
    "clipboard": ${utm_clipboard}
  },
  "console": {
    "display": "${utm_display}"
  }
}
EOF

    # Save VM metadata
    cat > "${conf_dir}/metadata.env" << EOF
UTM_VM=true
UTM_ARCH=${utm_architecture}
UTM_OS_TYPE=${utm_os_type}
UTM_DISPLAY=${utm_display}
UTM_SHARING_ENABLED=${utm_sharing}
UTM_SHARING_PATH=${utm_sharing_path}
UTM_CLIPBOARD=${utm_clipboard}
UTM_MEMORY=${utm_memory}
UTM_CORES=${utm_cores}
EOF

    log "UTM VM configuration created at: ${vm_base_dir}"
    log "To use in UTM.app:"
    log "1. Copy the directory to: ${HOME}/Library/Containers/com.utmapp.UTM/Data/Documents/"
    log "2. Import the VM in UTM.app"
}

# ---------------------------------------------------------------------------
# ISO Management Functions
# ---------------------------------------------------------------------------

# Insert ISO into existing VM configuration
insert_iso() {
    local vm_name="$1"
    local config_file=""
    
    # Search for config file in the new directory structure (vms/VM_NAME_PLATFORM/conf/)
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            config_file="$file"
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
    
    [[ -f "${config_file}" ]] || die "VM config not found: ${vm_name}.conf"
    
    log "Select ISO to insert into VM: ${vm_name}"
    local selected_iso
    selected_iso=$(pick_cdrom "")
    [[ -z "${selected_iso}" ]] && { warn "No ISO selected"; return 1; }
    
    # Update the VM configuration
    if grep -q "^CDROM_IMAGE=" "${config_file}" 2>/dev/null; then
        sed -i.bak "s|^CDROM_IMAGE=.*|CDROM_IMAGE=\"${selected_iso}\"|" "${config_file}"
    else
        echo "CDROM_IMAGE=\"${selected_iso}\"" >> "${config_file}"
    fi
    
    # Add boot from CDROM if not present
    if ! grep -q "BOOT_DEFAULT=" "${config_file}" 2>/dev/null; then
        echo "BOOT_DEFAULT=d" >> "${config_file}"
    fi
    
    log "ISO inserted: ${selected_iso}"
    log "VM will boot from CDROM on next startup"
}

# Eject ISO from VM configuration
eject_iso() {
    local vm_name="$1"
    local config_file=""
    
    # Search for config file in the new directory structure (vms/VM_NAME_PLATFORM/conf/)
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            config_file="$file"
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
    
    [[ -f "${config_file}" ]] || die "VM config not found: ${vm_name}.conf"
    
    # Clear the ISO configuration
    if grep -q "^CDROM_IMAGE=" "${config_file}" 2>/dev/null; then
        sed -i.bak "s|^CDROM_IMAGE=.*|CDROM_IMAGE=\"\"|" "${config_file}"
    else
        echo "CDROM_IMAGE=\"\"" >> "${config_file}"
    fi
    
    # Remove boot from CDROM if it was set
    if grep -q "BOOT_DEFAULT=d" "${config_file}" 2>/dev/null; then
        sed -i.bak "s|^BOOT_DEFAULT=d.*|BOOT_DEFAULT=c|" "${config_file}"
    fi
    
    log "ISO ejected from VM: ${vm_name}"
    log "VM will boot from hard disk on next startup"
}

# ---------------------------------------------------------------------------
# Additional VM Management Functions
# ---------------------------------------------------------------------------

# Stop a running VM
stop_vm() {
    local vm_name="$1"
    local vm_dir=""
    
    # Search for VM directory in the new structure
    while IFS= read -r -d '' dir; do
        if [[ -f "${dir}/${vm_name}.conf" ]]; then
            vm_dir="$dir"
            break
        fi
    done < <(find "${CONFIG_DIR}" -type d -print0 2>/dev/null)

    [[ -d "${vm_dir}" ]] || die "VM not found: ${vm_name}"

    local pid_file="${vm_dir}/pid"
    if [[ -f "${pid_file}" ]]; then
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
    else
        # Try to find QEMU process by VM name or config
        local config_file="${vm_dir}/${vm_name}.conf"
        if [[ -f "${config_file}" ]]; then
            local qemu_pids
            qemu_pids=$(pgrep -f "qemu-system" 2>/dev/null || true)
            if [[ -n "${qemu_pids}" ]]; then
                log "Found QEMU processes: ${qemu_pids}"
                if is_interactive; then
                    confirm=$(ask "Kill all QEMU processes for ${vm_name}?" "N")
                else
                    confirm="N"
                fi
                if [[ "${confirm:-N}" =~ ^[yY] ]]; then
                    kill ${qemu_pids} 2>/dev/null || true
                    log "Sent termination signal to QEMU processes"
                fi
            else
                warn "No running QEMU processes found for VM: ${vm_name}"
            fi
        else
            warn "No running process found for VM: ${vm_name}"
        fi
    fi

    log "VM ${vm_name} stop command completed"
    return 0
}

# Create VM configuration templates
create_vm_template() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "create_vm_template function requires interactive mode"
        return 1
    fi
    
    heading "Create VM Configuration Template"
    
    echo "Available templates:"
    echo "  [1] MacOS 9 (PPC) - 512MB RAM, mac99 machine"
    echo "  [2] MacOS X 10.4 (PPC64) - 1GB RAM, mac99 machine"
    echo "  [3] MacOS X 10.5 (PPC64) - 2GB RAM, mac99 machine"
    echo "  [4] HaikuOS (x86_64) - 512MB RAM, q35 machine"
    echo "  [5] Ubuntu Linux (x86_64) - 2GB RAM, q35 machine"
    echo "  [6] Windows XP (i386) - 1GB RAM, pc machine"
    echo "  [7] Solaris 10 (x86) - 1GB RAM, pc machine"
    echo "  [8] Solaris 10 (SPARC) - 1GB RAM, sun4u machine"
    echo "  [9] Custom configuration"
    echo ""
    
    template_choice=$(ask "Select template" "1")
    
    local vm_name
    vm_name=$(ask "VM name" "")
    [[ -z "${vm_name}" ]] && { warn "VM name cannot be empty"; return 1; }
    
    local template_file="${VM_CONFIG_DIR}/${vm_name}.env"
    mkdir -p "${VM_CONFIG_DIR}"
    
    case "${template_choice}" in
        1)
            # MacOS 9 (PPC)
            cat > "${template_file}" << EOF
# MacOS 9 Template (PPC)
QEMU_BIN=qemu-system-ppc
MACHINE=mac99,via=pmu
CPU=7455
RAM_MB=512
DISPLAY_BACKEND=cocoa
NETWORK_MODEL=sungem
HDD_IMAGE=${VM_IMAGE_DIR}/macos-ppc/macos9.qcow2
CDROM_IMAGE=
QEMU_ARGS=
EOF
            ;;
        2)
            # MacOS X 10.4 (PPC64)
            cat > "${template_file}" << EOF
# MacOS X 10.4 Tiger Template (PPC64)
QEMU_BIN=qemu-system-ppc64
MACHINE=mac99,via=pmu
CPU=970fx
RAM_MB=1024
DISPLAY_BACKEND=cocoa
NETWORK_MODEL=sungem
HDD_IMAGE=${VM_IMAGE_DIR}/macos-ppc64/macos104.qcow2
CDROM_IMAGE=
QEMU_ARGS=
EOF
            ;;
        3)
            # MacOS X 10.5 (PPC64)
            cat > "${template_file}" << EOF
# MacOS X 10.5 Leopard Template (PPC64)
QEMU_BIN=qemu-system-ppc64
MACHINE=mac99,via=pmu
CPU=970fx
RAM_MB=2048
DISPLAY_BACKEND=cocoa
NETWORK_MODEL=sungem
HDD_IMAGE=${VM_IMAGE_DIR}/macos-ppc64/macos105.qcow2
CDROM_IMAGE=
QEMU_ARGS=
EOF
            ;;
        4)
            # HaikuOS (x86_64)
            cat > "${template_file}" << EOF
# HaikuOS Template (x86_64)
QEMU_BIN=qemu-system-x86_64
MACHINE=q35
CPU=host
RAM_MB=512
DISPLAY_BACKEND=cocoa
NETWORK_MODEL=e1000
HDD_IMAGE=${VM_IMAGE_DIR}/haiku/haiku.qcow2
CDROM_IMAGE=
QEMU_ARGS=-enable-kvm
EOF
            ;;
        5)
            # Ubuntu Linux (x86_64)
            cat > "${template_file}" << EOF
# Ubuntu Linux Template (x86_64)
QEMU_BIN=qemu-system-x86_64
MACHINE=q35
CPU=host
RAM_MB=2048
DISPLAY_BACKEND=cocoa
NETWORK_MODEL=e1000
HDD_IMAGE=${VM_IMAGE_DIR}/linux/ubuntu.qcow2
CDROM_IMAGE=
QEMU_ARGS=-enable-kvm
EOF
            ;;
        6)
            # Windows XP (i386)
            cat > "${template_file}" << EOF
# Windows XP Template (i386)
QEMU_BIN=qemu-system-i386
MACHINE=pc
CPU=pentium3
RAM_MB=1024
DISPLAY_BACKEND=cocoa
NETWORK_MODEL=rtl8139
HDD_IMAGE=${VM_IMAGE_DIR}/windows-xp/windows_xp.qcow2
CDROM_IMAGE=
QEMU_ARGS=
EOF
            ;;
        7)
            # Solaris 10 (x86)
            cat > "${template_file}" << EOF
# Solaris 10 Template (x86)
QEMU_BIN=qemu-system-i386
MACHINE=pc
CPU=pentium3
RAM_MB=1024
DISPLAY_BACKEND=cocoa
NETWORK_MODEL=e1000
HDD_IMAGE=${VM_IMAGE_DIR}/solaris-x86/solaris10.qcow2
CDROM_IMAGE=
QEMU_ARGS=
EOF
            ;;
        8)
            # Solaris 10 (SPARC)
            cat > "${template_file}" << EOF
# Solaris 10 Template (SPARC)
QEMU_BIN=qemu-system-sparc64
MACHINE=sun4u
CPU=TI UltraSparc IIi
RAM_MB=1024
DISPLAY_BACKEND=cocoa
NETWORK_MODEL=sunhme
HDD_IMAGE=${VM_IMAGE_DIR}/solaris-sparc/solaris10.qcow2
CDROM_IMAGE=
QEMU_ARGS=
EOF
            ;;
        9)
            create_vm
            return 0
            ;;
        *)
            warn "Invalid template selection"
            return 1
            ;;
    esac
    
    log "VM template created: ${template_file}"
    log "You can now launch the VM with: ${SCRIPT_NAME} launch ${vm_name}"
}

# List available ROM files
list_roms() {
    local start_dir=""
    
    # Non-interactive mode: use default directory and auto-scan
    if ! is_interactive; then
        start_dir="${ROM_DIR}"
        heading "Available ROM Files in ${start_dir}"
        
        local global_available_roms_paths=()
        local index=1
        local selected_rom=""

        log "Scanning for ROM files..."
        
        if [[ -d "${start_dir}" ]]; then
            while IFS= read -r -d '' file; do
                case "${file}" in
                    *.rom|*.ROM|*.bin|*.BIN)
                        # Check for duplicates
                        local already_found=false
                        for existing in "${global_available_roms_paths[@]}"; do
                            if [[ "$existing" = "$file" ]]; then
                                already_found=true
                                break
                            fi
                        done
                        if [[ "$already_found" = false ]]; then
                            global_available_roms_paths+=("$file")
                            echo "  [${index}] $(basename "$file")"
                            ((index++))
                        fi
                        ;;
                esac
            done < <(find "${start_dir}" -type f \( -iname "*.rom" -o -iname "*.bin" \) -print0 2>/dev/null)
        fi
        
        if [[ ${#global_available_roms_paths[@]} -gt 0 ]]; then
            : # Do nothing, files found
        else
            log "No ROM files found in ${start_dir}."
        fi
    else
        # Interactive mode: ask user for input
        read -rp "Enter directory to scan for ROM files [${ROM_DIR}]: " start_dir
        start_dir="${start_dir:-${ROM_DIR}}"
        
        # Validate directory exists and user wants to proceed
        if [[ ! -d "${start_dir}" ]]; then
            warn "Directory does not exist: ${start_dir}"
            read -rp "Do you want to navigate to another directory? (y/n) [y]: " navigate_choice
            navigate_choice="${navigate_choice:-y}"
            if [[ "${navigate_choice}" =~ ^[yY] ]]; then
                list_roms
            fi
            return 1
        fi
        
        read -rp "Scan directory ${start_dir} for ROM files? (y/n) [y]: " confirm_scan
        confirm_scan="${confirm_scan:-y}"
        
        if [[ "${confirm_scan}" =~ ^[yY] ]]; then
            heading "Available ROM Files in ${start_dir}"
            
            local global_available_roms_paths=()
            local index=1
            local selected_rom=""

            log "Scanning for ROM files..."

            if [[ -d "${start_dir}" ]]; then
                while IFS= read -r -d '' file; do
                    case "${file}" in
                        *.rom|*.ROM|*.bin|*.BIN)
                            # Check for duplicates
                            local already_found=false
                            for existing in "${global_available_roms_paths[@]}"; do
                                if [[ "$existing" = "$file" ]]; then
                                    already_found=true
                                    break
                                fi
                            done
                            if [[ "$already_found" = false ]]; then
                                global_available_roms_paths+=("$file")
                                echo "  [${index}] $(basename "$file")"
                                ((index++))
                            fi
                            ;;
                    esac
                done < <(find "${start_dir}" -type f \( -iname "*.rom" -o -iname "*.bin" \) -print0 2>/dev/null)
            fi

            if [[ ${#global_available_roms_paths[@]} -gt 0 ]]; then
                read -rp "Select a ROM [1-${#global_available_roms_paths[@]}] (or press Enter to skip): " selected_index
                if [[ -n "${selected_index}" && "${selected_index}" =~ ^[0-9]+$ && ${selected_index} -le ${#global_available_roms_paths[@]} && ${selected_index} -gt 0 ]]; then
                    selected_rom="${global_available_roms_paths[$((selected_index-1))]}"
                    log "Selected ROM: ${selected_rom}"
                    echo "${selected_rom}"
                    return 0
                else
                    log "No ROM selected."
                    echo ""
                    return 0
                fi
            else
                log "No ROM files found in ${start_dir}."
            fi
            
            # Allow navigation to other directories
            read -rp "Scan another directory? (y/n) [n]: " scan_another
            scan_another="${scan_another:-n}"
            if [[ "${scan_another}" =~ ^[yY] ]]; then
                list_roms
            fi
        else
            log "ROM scan cancelled."
        fi
    fi
    
    return 0
}

# List available disk images
list_disks() {
    local start_dir=""
    
    # Non-interactive mode: use default directory and auto-scan
    if ! is_interactive; then
        start_dir="${DISK_DIR}"
        heading "Available Disk Images in ${start_dir}"
        
        local disks=()
        while IFS= read -r -d '' file; do
            disks+=("$file")
        done < <(find "${start_dir}" -type f \( -iname "*.qcow2" -o -iname "*.img" -o -iname "*.raw" -o -iname "*.hda" -o -iname "*.dsk" \) -print0 2>/dev/null | sort -z)
        
        if [[ ${#disks[@]} -eq 0 ]]; then
            warn "No disk images found in ${start_dir}"
            return 0
        fi
        
        local index=1
        for disk in "${disks[@]}"; do
            local disk_size
            disk_size=$(file_size_bytes "${disk}")
            local human_size
            if (( disk_size >= 1073741824 )); then
                human_size="$((disk_size / 1073741824))G"
            elif (( disk_size >= 1048576 )); then
                human_size="$((disk_size / 1048576))M"
            else
                human_size="${disk_size}B"
            fi
            echo "  [${index}] $(basename "${disk}") (${human_size})"
            ((index++))
        done
    else
        # Interactive mode: ask user for input
        read -rp "Enter directory to scan for disk images [${DISK_DIR}]: " start_dir
        start_dir="${start_dir:-${DISK_DIR}}"
        
        # Validate directory exists and user wants to proceed
        if [[ ! -d "${start_dir}" ]]; then
            warn "Directory does not exist: ${start_dir}"
            read -rp "Do you want to navigate to another directory? (y/n) [y]: " navigate_choice
            navigate_choice="${navigate_choice:-y}"
            if [[ "${navigate_choice}" =~ ^[yY] ]]; then
                list_disks
            fi
            return 1
        fi
        
        read -rp "Scan directory ${start_dir} for disk images? (y/n) [y]: " confirm_scan
        confirm_scan="${confirm_scan:-y}"
        
        if [[ "${confirm_scan}" =~ ^[yY] ]]; then
            heading "Available Disk Images in ${start_dir}"
            
            local disks=()
            while IFS= read -r -d '' file; do
                disks+=("$file")
            done < <(find "${start_dir}" -type f \( -iname "*.qcow2" -o -iname "*.img" -o -iname "*.raw" -o -iname "*.hda" -o -iname "*.dsk" \) -print0 2>/dev/null | sort -z)
            
            if [[ ${#disks[@]} -eq 0 ]]; then
                warn "No disk images found in ${start_dir}"
            else
                local index=1
                for disk in "${disks[@]}"; do
                    local disk_size
                    disk_size=$(file_size_bytes "${disk}")
                    local human_size
                    if (( disk_size >= 1073741824 )); then
                        human_size="$((disk_size / 1073741824))G"
                    elif (( disk_size >= 1048576 )); then
                        human_size="$((disk_size / 1048576))M"
                    else
                        human_size="${disk_size}B"
                    fi
                    echo "  [${index}] $(basename "${disk}") (${human_size})"
                    ((index++))
                done
            fi
            
            # Allow navigation to other directories
            read -rp "Scan another directory? (y/n) [n]: " scan_another
            scan_another="${scan_another:-n}"
            if [[ "${scan_another}" =~ ^[yY] ]]; then
                list_disks
            fi
        else
            log "Disk scan cancelled."
        fi
    fi
    
    return 0
}

# Edit VM configuration
edit_vm() {
    local vm_name="$1"
    local config_file=""
    
    # This function requires interactive mode
    if ! is_interactive; then
        warn "edit_vm function requires interactive mode"
        return 1
    fi
    
    # Search for config file in the new directory structure (vms/VM_NAME_PLATFORM/conf/)
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            config_file="$file"
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
    
    [[ -f "${config_file}" ]] || die "VM config not found: ${vm_name}.conf"
    
    heading "Editing VM Configuration: ${vm_name}"
    
    while true; do
        clear || echo ""
        echo "Edit VM Configuration: ${vm_name}"
        echo "================================"
        echo "Current Configuration:"
        echo "--------------------------------"
        
        # Display current configuration
        if [[ -f "${config_file}" ]]; then
            local line
            while IFS= read -r line; do
                [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue
                echo "  ${line}"
            done < "${config_file}"
        fi
        
        echo ""
        echo "Edit Options:"
        echo "  [1] Edit configuration file manually"
        echo "  [2] Change RAM size"
        echo "  [3] Change CPU"
        echo "  [4] Change disk image"
        echo "  [5] Change CDROM/ISO"
        echo "  [6] Change display settings"
        echo "  [7] Option C: Debug & Network settings (GDB/SSH/Netatalk)"
        echo "  [8] Save and exit"
        echo "  [9] Exit without saving"
        echo ""
        
        choice=$(ask "Select option" "8")
        
        case "${choice}" in
            1)
                log "Opening configuration file in editor..."
                ${EDITOR:-nano} "${config_file}"
                ;;
            2)
                local new_ram
                new_ram=$(ask_ram_size "New RAM size (MiB or suffix)" "${RAM_MB:-256}")
                if grep -q "^RAM_MB=" "${config_file}" 2>/dev/null; then
                    sed -i.bak "s|^RAM_MB=.*|RAM_MB=\"${new_ram}\"|" "${config_file}"
                else
                    echo "RAM_MB=\"${new_ram}\"" >> "${config_file}"
                fi
                log "RAM updated to: ${new_ram}"
                ;;
            3)
                local new_cpu
                new_cpu=$(ask "New CPU model" "${CPU:-host}")
                if grep -q "^CPU=" "${config_file}" 2>/dev/null; then
                    sed -i.bak "s|^CPU=.*|CPU=\"${new_cpu}\"|" "${config_file}"
                else
                    echo "CPU=\"${new_cpu}\"" >> "${config_file}"
                fi
                log "CPU updated to: ${new_cpu}"
                ;;
            4)
                local new_disk
                new_disk=$(pick_image "")
                if [[ -n "${new_disk}" ]]; then
                    if grep -q "^HDD_IMAGE=" "${config_file}" 2>/dev/null; then
                        sed -i.bak "s|^HDD_IMAGE=.*|HDD_IMAGE=\"${new_disk}\"|" "${config_file}"
                    else
                        echo "HDD_IMAGE=\"${new_disk}\"" >> "${config_file}"
                    fi
                    log "Disk image updated to: ${new_disk}"
                fi
                ;;
            5)
                local new_cdrom
                new_cdrom=$(pick_cdrom "")
                if [[ -n "${new_cdrom}" ]]; then
                    if grep -q "^CDROM_IMAGE=" "${config_file}" 2>/dev/null; then
                        sed -i.bak "s|^CDROM_IMAGE=.*|CDROM_IMAGE=\"${new_cdrom}\"|" "${config_file}"
                    else
                        echo "CDROM_IMAGE=\"${new_cdrom}\"" >> "${config_file}"
                    fi
                    log "CDROM updated to: ${new_cdrom}"
                else
                    # Clear CDROM
                    if grep -q "^CDROM_IMAGE=" "${config_file}" 2>/dev/null; then
                        sed -i.bak "s|^CDROM_IMAGE=.*|CDROM_IMAGE=\"\"|" "${config_file}"
                    fi
                    log "CDROM cleared"
                fi
                ;;
            6)
                local new_display
                new_display=$(ask "New display backend" "${DISPLAY_BACKEND:-${DEFAULT_DISPLAY}}")
                if grep -q "^DISPLAY_BACKEND=" "${config_file}" 2>/dev/null; then
                    sed -i.bak "s|^DISPLAY_BACKEND=.*|DISPLAY_BACKEND=\"${new_display}\"|" "${config_file}"
                else
                    echo "DISPLAY_BACKEND=\"${new_display}\"" >> "${config_file}"
                fi
                log "Display backend updated to: ${new_display}"
                ;;
            7)
                # Option C: Debug & Network settings
                edit_vm_option_c "${config_file}"
                ;;
            8)
                log "Configuration saved"
                return 0
                ;;
            9|q|quit|exit)
                log "Edit cancelled, no changes saved"
                return 1
                ;;
            *)
                warn "Invalid option"
                ;;
        esac
        
        if is_interactive; then
            read -rp "Press Enter to continue..." _
        fi
    done
}

# ---------------------------------------------------------------------------
# Disk Image Management
# ---------------------------------------------------------------------------

create_disk_image() {
    local name=$(ask "Disk name" "")
    local size=$(ask "Disk size (e.g., 20G, 50G):" "20G")
    local fmt=$(ask "Format (qcow2/raw):" "qcow2")
    local disk_path="${DISK_DIR}/${name}.${fmt}"
    
    ensure_dir "${DISK_DIR}"
    
    local qemu_img
    qemu_img=$(qemu_bin "qemu-img")
    
    log "Creating disk: ${disk_path} (${size}, ${fmt})"
    "${qemu_img}" create -f "${fmt}" "${disk_path}" "${size}"
    log "Disk created."
}

convert_disk_image() {
    local src=$(ask "Source image path" "")
    local dest=$(ask "Destination path" "")
    local dest_fmt=$(ask "Destination format (qcow2/raw/vmdk):" "qcow2")
    
    [[ -f "${src}" ]] || die "Source not found: ${src}"
    
    local qemu_img
    qemu_img=$(qemu_bin "qemu-img")
    
    log "Converting ${src} to ${dest} (${dest_fmt})"
    "${qemu_img}" convert -p -O "${dest_fmt}" "${src}" "${dest}"
    log "Conversion complete."
}

resize_disk_image() {
    local disk=$(ask "Disk image path" "")
    local new_size=$(ask "New size (e.g., +1G, 50G):" "+1G")
    
    [[ -f "${disk}" ]] || die "Disk not found: ${disk}"
    
    local qemu_img
    qemu_img=$(qemu_bin "qemu-img")
    
    log "Resizing ${disk} to ${new_size}"
    "${qemu_img}" resize "${disk}" "${new_size}"
    log "Resize complete."
}

# ---------------------------------------------------------------------------
# Main Menu System
# ---------------------------------------------------------------------------

show_main_menu() {
    # Main menu requires interactive mode
    if ! is_interactive; then
        warn "Main menu requires interactive mode. Use command-line arguments instead."
        show_usage
        return 1
    fi
    
    while true; do
        clear || echo ""
        heading "VM MANAGER - Main Menu"
        echo ""
        echo "🔨 Build & Setup:"
        echo "  [1]  Build QEMU (full pipeline)"
        echo "  [2]  Build QEMU (step by step)"
        echo "  [3]  Check build dependencies"
        echo "  [4]  Initialize directories"
        echo ""
        echo "🖥️  VM Management:"
        echo "  [5]  Create VM from template"
        echo "  [6]  Create new VM"
        echo "  [7]  List all VMs"
        echo "  [8]  Launch VM"
        echo "  [9]  Delete VM"
        echo ""
        echo "💾 Disk & ISO Management:"
        echo "  [10] Create disk image"
        echo "  [11] Convert disk image"
        echo "  [12] Resize disk image"
        echo "  [13] List available ISOs"
        echo "  [14] Download ISO from URL"
        echo "  [15] Detect ISOs in all directories"
        echo "  [16] Insert ISO into VM"
        echo "  [17] Eject ISO from VM"
        echo ""
        echo "🍎 UTM.app Integration:"
        echo "  [18] Create UTM VM configuration"
        echo "  [19] Export VM to UTM format"
        echo ""
        echo "🔧 Advanced VM Management:"
        echo "  [20] Stop a running VM"
        echo "  [21] Edit VM configuration"
        echo "  [22] List ROM files"
        echo "  [23] List disk images"
        echo ""
        echo "💾 Backup & Restore:"
        echo "  [24] Create configuration backup"
        echo "  [25] List available backups"
        echo "  [26] Restore from backup"
        echo ""
        echo "🚀 Quick Launch (Platform Presets):"
        echo "  [25] MacOS 68k (System 7-8.1)"
        echo "  [26] MacOS PPC (7.5.2-9.2.2, G3/G4)"
        echo "  [27] MacOS PPC64 (Mac OS X, G5)"
        echo "  [28] HaikuOS"
        echo "  [29] Linux (generic)"
        echo "  [30] Atari ST/TT/Falcon (68k)"
        echo "  [31] Commodore Amiga (68k/AROS)"
        echo "  [32] Solaris x86"
        echo "  [33] Solaris SPARC"
        echo "  [34] Windows XP"
        echo "  [35] OpenStep x86"
        echo "  [36] Custom QEMU (any architecture)"
        echo ""
        echo "📖 Information:"
        echo "  [37] Show QEMU version"
        echo "  [38] Show available architectures"
        echo "  [39] Show VM configurations"
        echo ""
        echo "🔍 Diagnostics:"
        echo "  [40] Test sharing services (Samba/Netatalk)"
        echo "  [41] Configure Netatalk (AFP) file sharing"
        echo "  [42] Configure Samba file sharing"
        echo "  [43] Verify all dependencies"
        echo "  [44] Configure XQuartz for X11 display"
        echo "  [45] Configure RAMDISK for sharing"
        echo "  [46] Test Samba connection"
        echo "  [47] Test Netatalk connection"
        echo "  [48] Test SSH connection"
        echo "  [49] Show QEMU command (debugging)"
        echo ""
        echo "❌ Exit:"
        echo "  [Q]  Quit"
        echo ""
        
        choice=$(ask "Select option" "")
        
        case "${choice,,}" in
            1) build_menu ;;
            2) build_step_by_step ;;
            3) check_build_deps ;;
            4) init_directories ;;
            5) create_vm_template ;;
            6) create_vm ;;
            7) list_vms ;;
            8) launch_vm_menu ;;
            9) delete_vm_menu ;;
            10) create_disk_image ;;
            11) convert_disk_image ;;
            12) resize_disk_image ;;
            13) list_isos ;;
            14) download_iso ;;
            15) detect_available_isos ;;
            16) insert_iso_menu ;;
            17) eject_iso_menu ;;
            18) create_utm_vm ;;
            19) export_utm_menu ;;
            20) stop_vm_menu ;;
            21) edit_vm_menu ;;
            22) list_roms ;;
            23) list_disks ;;
            24) backup_configurations ;;
            25) list_backups ;;
            26) backup_restore_menu ;;
            27) launch_macos_68k ;;
            28) launch_macos_ppc ;;
            29) launch_macos_ppc64 ;;
            30) launch_haiku ;;
            31) launch_linux ;;
            32) launch_atari ;;
            33) launch_amiga ;;
            34) launch_solaris_x86 ;;
            35) launch_solaris_sparc ;;
            36) launch_windows_xp ;;
            37) launch_openstep ;;
            38) launch_custom ;;
            37) show_qemu_version ;;
            38) show_architectures ;;
            39) show_vm_configs ;;
            40) test_sharing_services ;;
            41) configure_netatalk ;;
            42) configure_samba ;;
            43) verify_dependencies ;;
            44) configure_xquartz ;;
            45) configure_ramdisk ;;
            46) test_samba_connection localhost VM_Shares ;;
            47) test_netatalk_connection localhost VM_Shares ;;
            48) test_ssh_connection localhost 22 ;;
            49) show_qemu_command_menu ;;
            q|quit|exit) exit 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
        
        if is_interactive; then
            read -rp "Press Enter to continue..." _
        fi
    done
}

build_menu() {
    heading "Build QEMU - Full Pipeline"
    check_build_deps
    download_qemu
    apply_patches
    configure_qemu
    build_qemu
    install_qemu
    log "QEMU build complete!"
}

build_step_by_step() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "build_step_by_step function requires interactive mode"
        return 1
    fi
    
    heading "Build QEMU - Step by Step"
    echo ""
    echo "  1) Download source"
    echo "  2) Apply patches"
    echo "  3) Configure"
    echo "  4) Build"
    echo "  5) Install"
    echo "  6) All steps"
    echo "  7) Back to main menu"
    echo ""
    step=$(ask "Select step" "")
    case "${step}" in
        1) download_qemu ;;
        2) apply_patches ;;
        3) configure_qemu ;;
        4) build_qemu ;;
        5) install_qemu ;;
        6) build_menu ;;
        7) return ;;
        *) echo "Invalid option." ;;
    esac
    if is_interactive; then
        read -rp "Press Enter to continue..." _
    fi
}

launch_vm_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "launch_vm_menu function requires interactive mode"
        return 1
    fi
    
    list_vms
    [[ $? -ne 0 ]] && return 1
    vm_num=$(ask "Select VM number to launch" "")
    
    # Get all VM config files from vms/VM_NAME_PLATFORM/conf/
    local vm_confs=()
    while IFS= read -r -d '' vm_conf; do
        vm_confs+=("$vm_conf")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    local i=0
    for vm_conf in "${vm_confs[@]}"; do
        [[ -f "${vm_conf}" ]] && {
            if [[ $i -eq $vm_num ]]; then
                local vm_name=$(basename "${vm_conf}" .conf)
                launch_vm "${vm_name}"
                return 0
            fi
            ((i++)) || true
        }
    done
    die "Invalid VM selection"
}

delete_vm_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "delete_vm_menu function requires interactive mode"
        return 1
    fi
    
    list_vms
    [[ $? -ne 0 ]] && return 1
    vm_num=$(ask "Select VM number to delete" "")
    
    # Get all VM config files from vms/VM_NAME_PLATFORM/conf/
    local vm_confs=()
    while IFS= read -r -d '' vm_conf; do
        vm_confs+=("$vm_conf")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    local i=0
    for vm_conf in "${vm_confs[@]}"; do
        [[ -f "${vm_conf}" ]] && {
            if [[ $i -eq $vm_num ]]; then
                local vm_name=$(basename "${vm_conf}" .conf)
                confirm=$(ask "Delete VM '${vm_name}'?" "N")
                [[ "${confirm:-N}" =~ ^[yY] ]] && delete_vm "${vm_name}"
                return 0
            fi
            ((i++)) || true
        }
    done
    die "Invalid VM selection"
}

# Menu for ISO insertion
insert_iso_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "insert_iso_menu function requires interactive mode"
        return 1
    fi
    
    list_vms || return 1
    vm_num=$(ask "Select VM number to insert ISO into" "")
    
    # Get all VM config files from vms/VM_NAME_PLATFORM/conf/
    local vm_confs=()
    while IFS= read -r -d '' vm_conf; do
        vm_confs+=("$vm_conf")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    local i=0
    for vm_conf in "${vm_confs[@]}"; do
        [[ -f "${vm_conf}" ]] && {
            if [[ $i -eq $vm_num ]]; then
                local vm_name=$(basename "${vm_conf}" .conf)
                insert_iso "${vm_name}"
                return 0
            fi
            ((i++)) || true
        }
    done
    die "Invalid VM selection"
}

# Menu for ISO ejection
eject_iso_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "eject_iso_menu function requires interactive mode"
        return 1
    fi
    
    list_vms || return 1
    vm_num=$(ask "Select VM number to eject ISO from" "")
    
    # Get all VM config files from vms/VM_NAME_PLATFORM/conf/
    local vm_confs=()
    while IFS= read -r -d '' vm_conf; do
        vm_confs+=("$vm_conf")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    local i=0
    for vm_conf in "${vm_confs[@]}"; do
        [[ -f "${vm_conf}" ]] && {
            if [[ $i -eq $vm_num ]]; then
                local vm_name=$(basename "${vm_conf}" .conf)
                eject_iso "${vm_name}"
                return 0
            fi
            ((i++)) || true
        }
    done
    die "Invalid VM selection"
}

# Menu for UTM export
export_utm_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "export_utm_menu function requires interactive mode"
        return 1
    fi
    
    list_vms || return 1
    vm_num=$(ask "Select VM number to export to UTM format" "")
    
    # Get all VM config files from vms/VM_NAME_PLATFORM/conf/
    local vm_confs=()
    while IFS= read -r -d '' vm_conf; do
        vm_confs+=("$vm_conf")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    local i=0
    for vm_conf in "${vm_confs[@]}"; do
        [[ -f "${vm_conf}" ]] && {
            if [[ $i -eq $vm_num ]]; then
                local vm_name=$(basename "${vm_conf}" .conf)
                export_utm "${vm_name}"
                return 0
            fi
            ((i++)) || true
        }
    done
    die "Invalid VM selection"
}

# Menu for stopping VMs
stop_vm_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "stop_vm_menu function requires interactive mode"
        return 1
    fi
    
    list_vms || return 1
    vm_num=$(ask "Select VM number to stop" "")
    
    # Get all VM config files from vms/VM_NAME_PLATFORM/conf/
    local vm_confs=()
    while IFS= read -r -d '' vm_conf; do
        vm_confs+=("$vm_conf")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    local i=0
    for vm_conf in "${vm_confs[@]}"; do
        [[ -f "${vm_conf}" ]] && {
            if [[ $i -eq $vm_num ]]; then
                local vm_name=$(basename "${vm_conf}" .conf)
                stop_vm "${vm_name}"
                return 0
            fi
            ((i++)) || true
        }
    done
    die "Invalid VM selection"
}

# Menu for editing VM configuration
edit_vm_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "edit_vm_menu function requires interactive mode"
        return 1
    fi
    
    list_vms || return 1
    vm_num=$(ask "Select VM number to edit" "")
    
    # Get all VM config files from vms/VM_NAME_PLATFORM/conf/
    local vm_confs=()
    while IFS= read -r -d '' vm_conf; do
        vm_confs+=("$vm_conf")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    local i=0
    for vm_conf in "${vm_confs[@]}"; do
        [[ -f "${vm_conf}" ]] && {
            if [[ $i -eq $vm_num ]]; then
                local vm_name=$(basename "${vm_conf}" .conf)
                edit_vm "${vm_name}"
                return 0
            fi
            ((i++)) || true
        }
    done
    die "Invalid VM selection"
}

show_qemu_version() {
    heading "QEMU Version"
    local qemu_test="qemu-system-x86_64"
    local qemu_path
    qemu_path=$(qemu_bin "${qemu_test}") || {
        qemu_test="qemu-system-ppc"
        qemu_path=$(qemu_bin "${qemu_test}") || {
            die "No QEMU binary found. Build QEMU first."
        }
    }
    "${qemu_path}" -version
    [[ -z "${DEFAULT_DISPLAY}" ]] && detect_display_backend "${qemu_test}"
    return 0
}

show_architectures() {
    heading "Available QEMU Architectures"
    local archs=()
    for arch in ppc x86_64 m68k arm aarch64 i386 sparc sparc64; do
        command -v "qemu-system-${arch}" &>/dev/null && archs+=("${arch}")
    done
    
    if [[ ${#archs[@]} -gt 0 ]]; then
        for arch in "${archs[@]}"; do
            log "  ✓ qemu-system-${arch}"
        done
    else
        warn "No QEMU architectures found. Build QEMU first."
    fi
}

show_vm_configs() {
    heading "VM Configuration Templates"
    [[ -d "${VM_CONFIG_DIR}" ]] || { warn "No config directory: ${VM_CONFIG_DIR}"; return 1; }
    
    for config in "${VM_CONFIG_DIR}"/*.env; do
        [[ -f "${config}" ]] && log "  - $(basename "${config}")"
    done
}

# ---------------------------------------------------------------------------
# CLI Argument Handling
# ---------------------------------------------------------------------------

show_usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [COMMAND] [OPTIONS]

COMMANDS:

Build QEMU:
  build              Full QEMU build pipeline
  build-download     Download QEMU source
  build-patch       Apply upstream patches
  build-configure   Configure QEMU
  build-compile     Build QEMU
  build-install     Install QEMU
  init              Initialize all required directories

VM Management:
  create            Create new VM
  create-template   Create VM from template
  list              List all VMs
  launch <name>    Launch a VM
  delete <name>    Delete a VM

Platform Presets:
  macos-68k        Launch MacOS 68k VM
  macos-ppc        Launch MacOS PPC VM (G3/G4)
  macos-ppc64      Launch MacOS PPC VM (G5)
  haiku            Launch HaikuOS VM
  linux            Launch Linux VM
  atari            Launch Atari ST/TT/Falcon VM
  amiga            Launch Commodore Amiga/AROS VM
  solaris-x86      Launch Solaris x86 VM
  solaris-sparc    Launch Solaris SPARC VM
  windows-xp       Launch Windows XP VM
  openstep         Launch OpenStep x86 VM
  custom           Launch custom QEMU with any architecture

ISO Management:
  iso-list         List available ISOs
  iso-download     Download ISO from URL
  iso-detect      Detect ISOs in all directories
  iso-insert <vm>  Insert ISO into VM
  iso-eject <vm>  Eject ISO from VM

Architecture Detection:
  arch-detect      Detect available QEMU architectures

UTM Integration:
  utm-create       Create UTM VM configuration
  utm-export <vm>  Export VM to UTM format

Advanced VM Management:
  stop             Stop a running VM
  edit             Edit VM configuration
  list-roms        List available ROM files
  list-disks       List available disk images

Disk Management:
  disk-create      Create disk image
  disk-convert     Convert disk image
  disk-resize      Resize disk image

Information:
  qemu-version     Show QEMU version
  architectures    Show available architectures
  vm-configs       Show VM configuration templates
  capabilities     Detect QEMU capabilities
  check-deps       Check system dependencies
  verify-deps      Verify all dependencies (detailed)
  test-connections  Test sharing services (Samba/Netatalk)
  configure-netatalk Configure Netatalk (AFP) file sharing
  configure-samba   Configure Samba file sharing
  configure-xquartz Configure XQuartz for X11 display
  configure-ramdisk Configure RAMDISK for sharing
  test-samba        Test Samba connection with mounting
  test-netatalk    Test Netatalk connection with mounting
  test-ssh         Test SSH connection
  backup-config     Create backup of configurations
  list-backups      List available backups
  restore-config    Restore from backup
  show-command      Show QEMU command for a VM (debugging)
  menu             Interactive menu (default)
  help             Show this help

Environment Variables:
  QEMU_VERSION              QEMU version to build       (default: 9.2.0)
  QEMU_INSTALL_PREFIX       Installation prefix          (default: ~/.local/qemu-retro)
  VM_IMAGE_DIR              VM images directory          (default: ~/vm_assistant/images)
  VM_SHARED_DIR             Shared directory             (default: ~/vm_assistant/shares)
  VM_LOG_DIR                Logs directory               (default: ~/vm_assistant/logs)
  CONFIG_DIR                Config directory             (default: ~/vm_assistant)

Examples:
  # Build QEMU with all retro targets
  ${SCRIPT_NAME} build

  # Create and launch a MacOS PPC VM
  ${SCRIPT_NAME} create
  ${SCRIPT_NAME} launch my-macos-vm

  # Create VM from template
  ${SCRIPT_NAME} create-template

  # Launch with preset configuration
  ${SCRIPT_NAME} macos-ppc

  # Interactive menu
  ${SCRIPT_NAME} menu
EOF
}

# ---------------------------------------------------------------------------
# Show QEMU command for debugging
show_qemu_command() {
    local vm_name="$1"
    local config_file="${VM_DIR}/${vm_name}.conf"
    
    if [[ ! -f "${config_file}" ]]; then
        die "VM configuration not found: ${config_file}"
    fi
    
    heading "QEMU Command for VM: ${vm_name}"
    
    # Load configuration
    source "${config_file}" || die "Failed to load configuration"
    
    # Determine QEMU binary
    local qemu
    qemu=$(qemu_bin_or_die "${QEMU_BIN:-qemu-system-${QEMU_ARCH:-x86_64}}")
    
    # Build QEMU command array (similar to launch_vm but only shows command)
    local cmd=(
        "${qemu}"
        -machine "${MACHINE:-pc}"
        -cpu "${CPU:-host}"
        -m "${RAM_MB:-2048}"
        -display "${DISPLAY_BACKEND:-${DEFAULT_DISPLAY}}"
    )
    
    # Add disk
    [[ -n "${HDD_IMAGE:-}" && -f "${HDD_IMAGE}" ]] && cmd+=(-hda "${HDD_IMAGE}")
    
    # Add CDROM if specified
    [[ -n "${CDROM_IMAGE:-}" && -f "${CDROM_IMAGE}" ]] && cmd+=(-cdrom "${CDROM_IMAGE}")
    
    # Add network
    cmd+=(-nic user,model="${NETWORK_MODEL:-e1000}")
    
    # Option C: GDB debugging support
    if [[ "${ENABLE_GDB:-n}" == "y" ]]; then
        local gdb_port="${GDB_PORT:-${DEFAULT_GDB_PORT}}"
        cmd+=(-gdb "tcp::${gdb_port}" -S)
    fi
    
    # Option C: SSH port forwarding
    if [[ "${ENABLE_SSH:-n}" == "y" ]]; then
        local ssh_port="${SSH_PORT:-${DEFAULT_SSH_PORT}}"
        cmd+=(-netdev "user,id=sshnet0,hostfwd=tcp::${ssh_port}-:22")
        cmd+=(-device "virtio-net-pci,netdev=sshnet0")
    fi
    
    # Add other devices
    cmd+=(-device usb-kbd -device usb-mouse -rtc base=localtime)
    
    log "QEMU Command:"
    echo ""
    echo "  ${cmd[*]}"
    echo ""
    log "You can copy and modify this command for custom usage"
}

# Show QEMU command menu
show_qemu_command_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "show_qemu_command_menu function requires interactive mode"
        return 1
    fi
    
    heading "Show QEMU Command"
    list_vms
    vm_name=$(ask "Enter VM name to show command" "")
    [[ -n "$vm_name" ]] && show_qemu_command "$vm_name"
}

# Entry Point
# ---------------------------------------------------------------------------

main() {
    # Initialize
    ensure_dir "${CONFIG_DIR}"
    ensure_dir "${VM_DIR}"
    ensure_dir "${DISK_DIR}"
    ensure_dir "${ISO_DIR}"
    ensure_dir "${VM_LOG_DIR}"
    ensure_dir "${SHARE_DIR}"
    
    # Detect display backend
    local test_qemu="qemu-system-x86_64"
    if ! qemu_bin "${test_qemu}" &>/dev/null; then
        test_qemu="qemu-system-ppc"
        if ! qemu_bin "${test_qemu}" &>/dev/null; then
            test_qemu="qemu-system-ppc64"
        fi
    fi
    detect_display_backend "${test_qemu}"
    
    # Detect QEMU capabilities (silent for now, can be run manually)
    if [[ "${1:-}" != "menu" && "${1:-}" != "help" && "${1:-}" != "--help" && "${1:-}" != "-h" ]]; then
        detect_qemu_capabilities >/dev/null 2>&1 || true
    fi
    
    local cmd="${1:-menu}"
    
    case "${cmd}" in
        # Build commands
        build|build-all) build_menu ;;
        build-download|download) download_qemu ;;
        build-patch|patch) apply_patches ;;
        build-configure|configure) configure_qemu ;;
        build-compile|compile|build-build) build_qemu ;;
        build-install|install) install_qemu ;;
        init|init-dir|init-directories) init_directories ;;
        
        # VM management
        create) create_vm ;;
        create-template|create-vm-template|template) create_vm_template ;;
        list|list-vms) list_vms ;;
        launch) 
            [[ -n "${2:-}" ]] && launch_vm "$2" || launch_vm_menu
            ;;
        delete|del) 
            [[ -n "${2:-}" ]] && delete_vm "$2" || delete_vm_menu
            ;;
        
        # Platform presets
        macos-68k) launch_macos_68k ;;
        macos-ppc) launch_macos_ppc ;;
        macos-ppc64) launch_macos_ppc64 ;;
        haiku) launch_haiku ;;
        linux) launch_linux ;;
        atari) launch_atari ;;
        amiga) launch_amiga ;;
        solaris-x86) launch_solaris_x86 ;;
        solaris-sparc) launch_solaris_sparc ;;
        windows-xp) launch_windows_xp ;;
        openstep) launch_openstep ;;
        custom) launch_custom ;;
        
        # Advanced VM management
        stop|stop-vm) 
            [[ -n "${2:-}" ]] && stop_vm "$2" || stop_vm_menu ;;
        edit|edit-vm) 
            [[ -n "${2:-}" ]] && edit_vm "$2" || edit_vm_menu ;;
        list-roms|roms) list_roms ;;
        list-disks|disks) list_disks ;;
        
        # Capability detection
        capabilities|detect-capabilities) detect_qemu_capabilities ;;
        check-deps|detect-deps) detect_dependencies ;;
        verify-deps|verify-dependencies) verify_dependencies ;;
        test-connections|check-sharing|test-sharing) test_sharing_services ;;
        configure-netatalk|setup-netatalk) configure_netatalk ;;
        configure-samba|setup-samba) configure_samba ;;
        configure-xquartz|setup-xquartz) configure_xquartz ;;
        configure-ramdisk|setup-ramdisk) configure_ramdisk ;;
        test-samba|test-samba-connection) test_samba_connection ;;
        test-netatalk|test-netatalk-connection) test_netatalk_connection ;;
        test-ssh|test-ssh-connection) test_ssh_connection ;;
        backup-config|backup) backup_configurations ;;
        list-backups) list_backups ;;
        restore-config|restore) 
            [[ -n "${2:-}" ]] && restore_configuration "$2" || backup_restore_menu ;;
        show-command|show-qemu-command) 
            [[ -n "${2:-}" ]] && show_qemu_command "$2" || die "Please specify VM name"
            ;;
        
        # Disk/ISO management
        disk-create|create-disk) create_disk_image ;;
        disk-convert|convert-disk) convert_disk_image ;;
        disk-resize|resize-disk) resize_disk_image ;;
        iso-list|list-isos) list_isos ;;
        iso-download|download-iso) download_iso ;;
        iso-detect|detect-isos) detect_available_isos ;;
        arch-detect|detect-architectures) detect_available_architectures ;;
        iso-insert|insert-iso) 
            [[ -n "${2:-}" ]] && insert_iso "$2" || insert_iso_menu ;;
        iso-eject|eject-iso) 
            [[ -n "${2:-}" ]] && eject_iso "$2" || eject_iso_menu ;;
        
        # UTM integration
        utm-export|export-utm) 
            [[ -n "${2:-}" ]] && export_utm "$2" || export_utm_menu ;;
        utm-create|create-utm) create_utm_vm ;;
        
        # Information
        qemu-version|version) show_qemu_version ;;
        architectures|archs) show_architectures ;;
        vm-configs|configs) show_vm_configs ;;
        
        # Help
        help|--help|-h) show_usage ;;
        
        # Interactive / Default
        menu|*) show_main_menu ;;
    esac
}

main "$@"
