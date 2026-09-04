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
IMAGES_DIR="${CONFIG_DIR}/images"
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

# GUI Configuration
USE_XDIALOG=false
HAVE_XDIALOG=false
XDIALOG_PATH=""

# Cross-Compilation Toolchain Configuration
TOOLCHAIN_DIR="${CONFIG_DIR}/toolchains"
DETECTED_TOOLCHAINS=()

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

# Check if a QEMU device is available for a specific architecture
qemu_device_exists() {
    local device="$1"
    local arch="$2"
    local qemu_bin_path
    
    # Default to ppc if not specified
    [[ -z "${arch}" ]] && arch="ppc"
    
    qemu_bin_path=$(qemu_bin "qemu-system-${arch}" 2>/dev/null) || return 1
    
    if "${qemu_bin_path}" -device help 2>/dev/null | grep -q "${device}"; then
        return 0
    else
        return 1
    fi
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

# =============================================================================
# Debugging Workflow Functions
# =============================================================================

# Start a debug session for a specific VM
debug_start() {
    local vm_name="$1"
    local binary_path="$2"
    local debug_port="$3"
    
    # This function requires interactive mode
    if ! is_interactive; then
        warn "debug_start function requires interactive mode"
        return 1
    fi
    
    [[ -n "${vm_name}" ]] || die "VM name is required. Usage: debug_start <vm_name> [binary_path] [port]"
    
    heading "Starting Debug Session: ${vm_name}"
    
    # Check if VM is running
    if ! is_vm_running "${vm_name}"; then
        warn "VM '${vm_name}' is not running. Starting it first..."
        launch_vm "${vm_name}" || die "Failed to start VM: ${vm_name}"
        sleep 5  # Give VM time to start
    fi
    
    # Get VM configuration
    local config_file=""
    find_vm_config "${vm_name}" config_file || die "Config not found for VM: ${vm_name}"
    
    # Extract GDB port from config or use default
    local port="${debug_port:-${GDB_PORT:-${DEFAULT_GDB_PORT}}}"
    
    # If binary path provided, deploy it first
    if [[ -n "${binary_path}" && -f "${binary_path}" ]]; then
        log "Deploying binary to VM: ${binary_path}"
        deploy_binary "${vm_name}" "${binary_path}" || warn "Failed to deploy binary"
    fi
    
    # Display debug connection information
    log ""
    log "Debug Session Information:"
    log "  VM: ${vm_name}"
    log "  GDB Port: ${port}"
    log "  Status: Ready for debug connection"
    log ""
    log "Connect with GDB:"
    log "  gdb-multiarch -ex 'target remote localhost:${port}' ${binary_path:-BINARY}"
    log ""
    
    # Check if auto-connect is requested
    local auto_connect=$(ask "Auto-connect GDB? (y/n)" "n")
    if is_yes "${auto_connect}"; then
        debug_connect "${vm_name}" "${port}" "${binary_path}"
    fi
}

# Connect GDB to a running VM
debug_connect() {
    local vm_name="$1"
    local port="$2"
    local binary_path="$3"
    
    [[ -n "${vm_name}" ]] || die "VM name is required. Usage: debug_connect <vm_name> [port] [binary_path]"
    
    port="${port:-${GDB_PORT:-${DEFAULT_GDB_PORT}}}"
    
    heading "Connecting GDB to VM: ${vm_name}"
    log "Attempting GDB connection on port: ${port}"
    
    # Check if GDB is available
    local gdb_bin="${GDB_BIN:-gdb-multiarch}"
    if ! command -v "${gdb_bin}" &>/dev/null; then
        # Try common GDB variants
        for gdb_candidate in gdb-multiarch gdb gdb64; do
            if command -v "${gdb_candidate}" &>/dev/null; then
                gdb_bin="${gdb_candidate}"
                break
            fi
        done
    fi
    
    if ! command -v "${gdb_bin}" &>/dev/null; then
        die "No GDB found. Please install gdb-multiarch or standard gdb."
    fi
    
    log "Using GDB: ${gdb_bin}"
    
    # Build GDB command
    local gdb_cmd=("${gdb_bin}")
    
    if [[ -n "${binary_path}" && -f "${binary_path}" ]]; then
        gdb_cmd+=("${binary_path}")
    fi
    
    # Add connection command
    gdb_cmd+=(-ex "target remote localhost:${port}")
    
    log "Running: ${gdb_cmd[*]}"
    log "Press Ctrl+C to exit GDB and return to menu"
    
    # Run GDB interactively
    "${gdb_cmd[@]}"
}

# Deploy binary to a VM
deploy_binary() {
    local vm_name="$1"
    local binary_path="$2"
    local target_path="$3"
    
    [[ -n "${vm_name}" ]] || die "VM name is required"
    [[ -n "${binary_path}" ]] || die "Binary path is required"
    [[ -f "${binary_path}" ]] || die "Binary not found: ${binary_path}"
    
    heading "Deploying Binary to VM: ${vm_name}"
    log "Source: ${binary_path}"
    
    # Find VM directory
    local vm_dir=""
    find_vm_directory "${vm_name}" vm_dir || die "VM directory not found: ${vm_name}"
    
    # Determine target path if not specified
    if [[ -z "${target_path}" ]]; then
        target_path="${vm_dir}/$(basename "${binary_path}")"
    fi
    
    # Create target directory if needed
    ensure_dir "$(dirname "${target_path}")"
    
    # Copy binary to VM
    log "Copying to: ${target_path}"
    if cp "${binary_path}" "${target_path}" 2>/dev/null; then
        log "✅ Binary deployed successfully"
        
        # Set appropriate permissions
        chmod +x "${target_path}" 2>/dev/null
        log "✅ Binary made executable"
        
        return 0
    else
        # Try alternative methods if direct copy fails
        if [[ -d "${vm_dir}" ]]; then
            warn "Direct copy failed, trying alternative method..."
            # Method: Use shared directory
            if [[ -d "${VM_SHARED_DIR}" ]]; then
                local shared_binary="${VM_SHARED_DIR}/$(basename "${binary_path}")"
                cp "${binary_path}" "${shared_binary}"
                chmod +x "${shared_binary}"
                log "✅ Binary copied to shared directory: ${shared_binary}"
                log "Access it from VM at: /path/to/shared/directory"
                return 0
            fi
        fi
        
        die "Failed to deploy binary to VM: ${vm_name}"
    fi
}

# List active debug sessions
debug_list() {
    heading "Active Debug Sessions"
    
    # Check for running VMs with GDB enabled
    local active_vms=()
    local vm_info=""
    
    for vm_dir in "${VM_DIR}"/**; do
        [[ -d "${vm_dir}" ]] || continue
        local vm_name=$(basename "${vm_dir}")
        local config_file="${vm_dir}/conf/${vm_name}.conf"
        
        if [[ -f "${config_file}" ]]; then
            local gdb_enabled=$(grep -i "ENABLE_GDB" "${config_file}" | cut -d'=' -f2 | tr -d '"' | head -1)
            local gdb_port=$(grep -i "GDB_PORT" "${config_file}" | cut -d'=' -f2 | tr -d '"' | head -1)
            
            if [[ "${gdb_enabled}" == "yes" || "${gdb_enabled}" == "true" ]]; then
                local pid=""
                # Try to find QEMU process for this VM
                if pgrep -f "${vm_name}" &>/dev/null; then
                    pid=$(pgrep -f "${vm_name}" | head -1)
                    vm_info+="  VM: ${vm_name} | Port: ${gdb_port:-${DEFAULT_GDB_PORT}} | PID: ${pid}\n"
                    active_vms+=("${vm_name}")
                else
                    vm_info+="  VM: ${vm_name} | Port: ${gdb_port:-${DEFAULT_GDB_PORT}} | Status: Not running\n"
                fi
            fi
        fi
    done
    
    if [[ ${#active_vms[@]} -eq 0 ]]; then
        log "No active debug sessions found"
        log "Start a debug session with: debug-start <vm_name>"
    else
        echo -e "${vm_info}"
        log "Active debug sessions: ${#active_vms[@]}"
    fi
}

# Stop/Detach from debug session
debug_detach() {
    local vm_name="$1"
    
    [[ -n "${vm_name}" ]] || die "VM name is required. Usage: debug-detach <vm_name>"
    
    heading "Detaching from Debug Session: ${vm_name}"
    
    # Find and stop GDB process connected to this VM's port
    local gdb_pids=()
    local config_file=""
    
    find_vm_config "${vm_name}" config_file
    if [[ -f "${config_file}" ]]; then
        local gdb_port=$(grep -i "GDB_PORT" "${config_file}" | cut -d'=' -f2 | tr -d '"' | head -1)
        gdb_port="${gdb_port:-${DEFAULT_GDB_PORT}}"
        
        # Find GDB processes connected to this port
        gdb_pids=($(pgrep -f "tcp::${gdb_port}" 2>/dev/null || true))
        gdb_pids+=($(pgrep -f "remote localhost:${gdb_port}" 2>/dev/null || true))
        
        if [[ ${#gdb_pids[@]} -gt 0 ]]; then
            log "Found ${#gdb_pids[@]} GDB process(es) connected to port ${gdb_port}"
            for pid in "${gdb_pids[@]}"; do
                log "  Killing GDB process: ${pid}"
                kill "${pid}" 2>/dev/null
            done
            log "✅ GDB detached from VM: ${vm_name}"
        else
            log "No active GDB connection found for VM: ${vm_name}"
        fi
    else
        warn "Config file not found for VM: ${vm_name}"
    fi
}

# Advanced debugging: Set breakpoints and start
debug_with_breakpoints() {
    local vm_name="$1"
    local binary_path="$2"
    local breakpoints="$3"
    
    [[ -n "${vm_name}" ]] || die "VM name is required"
    [[ -n "${binary_path}" ]] || die "Binary path is required"
    
    heading "Debugging with Breakpoints: ${vm_name}"
    
    # Deploy binary first
    deploy_binary "${vm_name}" "${binary_path}" || return 1
    
    # Start debug session
    debug_start "${vm_name}" "${binary_path}" || return 1
    
    # If breakpoints provided, set them
    if [[ -n "${breakpoints}" ]]; then
        log "Setting breakpoints: ${breakpoints}"
        # This would be handled in the GDB session
        # For now, just display the breakpoints to set
        log "Manual GDB commands to set breakpoints:"
        IFS=',' read -ra bps <<< "${breakpoints}"
        for bp in "${bps[@]}"; do
            log "  (gdb) break ${bp}"
        done
        log "  (gdb) continue"
    fi
}

# Debug session management menu
debug_session_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "debug_session_menu function requires interactive mode"
        return 1
    fi
    
    while true; do
        clear || echo ""
        heading "Debug Session Management"
        echo ""
        echo "  [1] Start debug session"
        echo "  [2] Connect GDB to running VM"
        echo "  [3] List active debug sessions"
        echo "  [4] Detach from debug session"
        echo "  [5] Deploy binary to VM"
        echo "  [6] Debug with breakpoints"
        echo ""
        echo "  [B] Back to main menu"
        echo ""
        
        choice=$(ask "Select debug option" "")
        
        case "${choice}" in
            1) 
                vm_num=$(ask "VM number to debug (or name)" "")
                [[ -n "${vm_num}" ]] && debug_start "${vm_num}"
                ;;
            2)
                vm_num=$(ask "VM number to connect to" "")
                [[ -n "${vm_num}" ]] && debug_connect "${vm_num}"
                ;;
            3) debug_list ;;
            4)
                vm_num=$(ask "VM number to detach from" "")
                [[ -n "${vm_num}" ]] && debug_detach "${vm_num}"
                ;;
            5)
                vm_num=$(ask "Target VM name" "")
                binary=$(ask "Binary path to deploy" "")
                [[ -n "${vm_num}" && -n "${binary}" ]] && deploy_binary "${vm_num}" "${binary}"
                ;;
            6)
                vm_num=$(ask "VM name" "")
                binary=$(ask "Binary path" "")
                bps=$(ask "Breakpoints (comma-separated)" "")
                [[ -n "${vm_num}" && -n "${binary}" ]] && debug_with_breakpoints "${vm_num}" "${binary}" "${bps}"
                ;;
            b|B) return 0 ;;
            q|quit|exit) return 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
        
        if is_interactive; then
            read -rp "Press Enter to continue..." _
        fi
    done
}

# =============================================================================
# End Debugging Workflow Functions

# =============================================================================
# Helper Functions for Debugging
# =============================================================================

# Find VM configuration file for a given VM name
# Sets the config_file variable passed by reference
find_vm_config() {
    local vm_name="$1"
    local -n config_file_ref="$2"
    
    [[ -n "${vm_name}" ]] || die "VM name is required"
    
    local config_file=""
    config_file=$(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print -quit 2>/dev/null)
    
    if [[ -n "${config_file}" && -f "${config_file}" ]]; then
        config_file_ref="${config_file}"
        return 0
    else
        return 1
    fi
}

# Find VM config file path for a given VM name
# Returns the config file path
find_vm_config_file() {
    local vm_name="$1"
    
    [[ -n "${vm_name}" ]] || die "VM name is required"
    
    local config_file=""
    find_vm_config "${vm_name}" config_file
    
    if [[ -n "${config_file}" && -f "${config_file}" ]]; then
        echo "${config_file}"
        return 0
    else
        return 1
    fi
}

# Find VM directory for a given VM name
# Sets the vm_dir variable passed by reference
find_vm_directory() {
    local vm_name="$1"
    local -n vm_dir_ref="$2"
    
    [[ -n "${vm_name}" ]] || die "VM name is required"
    
    # VMs are stored as: vms/VM_NAME_PLATFORM/
    # We need to find the directory that contains the config file
    local config_file=""
    find_vm_config "${vm_name}" config_file
    
    if [[ -n "${config_file}" ]]; then
        vm_dir_ref="$(dirname "$(dirname "${config_file}")")"
        return 0
    else
        # Try direct directory search
        local vm_dir=""
        vm_dir=$(find "${VM_DIR}" -maxdepth 2 -type d -name "*${vm_name}*" -print -quit 2>/dev/null)
        
        if [[ -n "${vm_dir}" && -d "${vm_dir}" ]]; then
            vm_dir_ref="${vm_dir}"
            return 0
        fi
        
        return 1
    fi
}

# Get VM IP address (placeholder implementation)
# Returns 0 and echo the IP if available, 1 otherwise
get_vm_ip() {
    local vm_name="$1"
    
    [[ -n "${vm_name}" ]] || return 1
    
    # For now, return localhost as a fallback for SPICE
    # TODO: Implement actual VM IP detection based on the platform
    echo "127.0.0.1"
    return 0
}

# Ensure VM exists by checking if its configuration exists
ensure_vm_exists() {
    local vm_name="$1"
    
    [[ -n "${vm_name}" ]] || die "VM name is required"
    
    local config_file=""
    if ! find_vm_config "${vm_name}" config_file; then
        die "VM not found: ${vm_name}"
    fi
    
    return 0
}

# Check if a VM is currently running
is_vm_running() {
    local vm_name="$1"
    
    [[ -n "${vm_name}" ]] || return 1
    
    # Try to find QEMU process for this VM
    if pgrep -f "${vm_name}" &>/dev/null; then
        return 0
    fi
    
    # Try to find by config file pattern
    local config_file=""
    find_vm_config "${vm_name}" config_file
    
    if [[ -n "${config_file}" ]]; then
        # Extract VM name from config path
        local vm_pattern=$(basename "${config_file}" .conf)
        if pgrep -f "${vm_pattern}" &>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# =============================================================================
# End Helper Functions for Debugging

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
        "${IMAGES_DIR}"
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
# Package Manager Functions (MacPorts & Homebrew for macOS)
# ---------------------------------------------------------------------------

# Check if MacPorts is installed
check_macports() {
    if command -v port &>/dev/null; then
        log "MacPorts is installed"
        return 0
    else
        log "MacPorts is not installed"
        return 1
    fi
}

# Check if Homebrew is installed
check_homebrew() {
    if command -v brew &>/dev/null; then
        log "Homebrew is installed"
        return 0
    else
        log "Homebrew is not installed"
        return 1
    fi
}

# Install packages using MacPorts
install_macports_packages() {
    if ! check_macports; then
        warn "MacPorts is not installed. Cannot install packages."
        return 1
    fi
    
    local packages=("$@")
    local failed_packages=()
    
    log "Installing packages with MacPorts: ${packages[*]}"
    
    for pkg in "${packages[@]}"; do
        if ! sudo port install "$pkg" 2>/dev/null; then
            failed_packages+=("$pkg")
            warn "Failed to install: $pkg"
        else
            log "✓ Installed: $pkg"
        fi
    done
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        warn "Failed to install: ${failed_packages[*]}"
        return 1
    fi
    
    return 0
}

# Install packages using Homebrew
install_homebrew_packages() {
    if ! check_homebrew; then
        warn "Homebrew is not installed. Cannot install packages."
        return 1
    fi
    
    local packages=("$@")
    local failed_packages=()
    
    log "Installing packages with Homebrew: ${packages[*]}"
    
    for pkg in "${packages[@]}"; do
        if ! brew install "$pkg" 2>/dev/null; then
            failed_packages+=("$pkg")
            warn "Failed to install: $pkg"
        else
            log "✓ Installed: $pkg"
        fi
    done
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        warn "Failed to install: ${failed_packages[*]}"
        return 1
    fi
    
    return 0
}

# Install VM dependencies using available package manager
install_vm_dependencies() {
    heading "Installing VM Dependencies"
    
    local dependencies=()
    local package_manager=""
    
    # Platform-specific dependencies
    case "$(uname -s)" in
        Darwin)
            dependencies=("qemu" "wget" "curl" "sdl2" "pixman" "libpng" "jpeg" "glib2")
            if check_macports; then
                package_manager="macports"
            elif check_homebrew; then
                package_manager="homebrew"
            else
                warn "No supported package manager found (MacPorts or Homebrew)"
                return 1
            fi
            ;;
        Linux)
            dependencies=("qemu" "wget" "curl" "libsdl2-dev" "libpixman-1-dev" "libpng-dev" "libjpeg-dev" "libglib2.0-dev")
            package_manager="apt"  # Could be extended for other Linux distros
            ;;
        *)
            warn "Unsupported platform for dependency installation"
            return 1
            ;;
    esac
    
    case "${package_manager}" in
        macports)
            install_macports_packages "${dependencies[@]}"
            ;;
        homebrew)
            install_homebrew_packages "${dependencies[@]}"
            ;;
        *)
            warn "Package manager not supported: ${package_manager}"
            return 1
            ;;
    esac
    
    return 0
}

# Update package manager databases
update_package_manager() {
    heading "Updating Package Manager"
    
    if check_macports; then
        log "Updating MacPorts..."
        sudo port selfupdate
    elif check_homebrew; then
        log "Updating Homebrew..."
        brew update
    else
        warn "No supported package manager found"
        return 1
    fi
    
    return 0
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
        2>&1 | tee configure.log || {
            warn "Some optional features were not found; retrying with minimal flags..."
            "${QEMU_SRC_DIR}/configure" \
                --prefix="${QEMU_INSTALL_PREFIX}" \
                --target-list="${target_list}" \
                2>&1 | tee configure.log
        }
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
        share_dir=$(ask "Share directory path" "${VM_SHARED_DIR:-${DEFAULT_MACOS_SHARE_DIR}}")
    fi
    
    # Update configuration file
    local updates=(
        "ENABLE_GDB=${enable_gdb}"
        "GDB_PORT=${gdb_port}"
        "ENABLE_SSH=${enable_ssh}"
        "SSH_PORT=${ssh_port}"
        "ENABLE_NETATALK=${enable_netatalk}"
        "NETATALK_SHARE_NAME=${netatalk_share_name}"
        "VM_SHARED_DIR=${share_dir}"
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
VM_SHARED_DIR=${DEFAULT_MACOS_SHARE_DIR}"
        
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

# List available Images
list_images() {
    local start_dir=""
    
    # Non-interactive mode: use default directory and auto-scan
    if ! is_interactive; then
        start_dir="${IMAGES_DIR}"
        heading "Available Images in ${start_dir}"
        
        local found=0
        local image_dirs=("${start_dir}")
        
        for dir in "${image_dirs[@]}"; do
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
        read -rp "Enter directory to scan for Images [${IMAGES_DIR}]: " start_dir
        start_dir="${start_dir:-${IMAGES_DIR}}"
        
        # Validate directory exists and user wants to proceed
        if [[ ! -d "${start_dir}" ]]; then
            warn "Directory does not exist: ${start_dir}"
            read -rp "Do you want to navigate to another directory? (y/n) [y]: " navigate_choice
            navigate_choice="${navigate_choice:-y}"
            if [[ "${navigate_choice}" =~ ^[yY] ]]; then
                list_images
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
                    list_images
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
        start_dir="${IMAGES_DIR}"
    else
        # Enhanced UX: Ask user which directory to start with
        log "Select ISO file for VM"
        log "------------------------"
        read -rp "Enter directory to scan for Images [${IMAGES_DIR}]: " start_dir
        start_dir="${start_dir:-${IMAGES_DIR}}"
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
        local share_dir="${VM_SHARED_DIR:-${DEFAULT_MACOS_SHARE_DIR}}"
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

# Clone an existing VM
clone_vm() {
    local source_vm="$1"
    local new_vm_name="$2"
    
    # This function requires interactive mode
    if ! is_interactive; then
        warn "clone_vm function requires interactive mode"
        return 1
    fi
    
    # If no arguments, prompt for them
    if [[ -z "${source_vm}" ]]; then
        heading "Clone Virtual Machine"
        list_vms || return 1
        
        local vm_num
        vm_num=$(ask "Select VM number to clone" "")
        
        # Get all VM config files from vms/VM_NAME_PLATFORM/conf/
        local vm_confs=()
        while IFS= read -r -d '' vm_conf; do
            vm_confs+=("${vm_conf}")
        done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
        
        local i=0
        for vm_conf in "${vm_confs[@]}"; do
            [[ -f "${vm_conf}" ]] && {
                if [[ $i -eq $vm_num ]]; then
                    source_vm=$(basename "${vm_conf}" .conf)
                    break
                fi
                ((i++)) || true
            }
        done
        
        [[ -z "${source_vm}" ]] && { warn "Invalid VM selection"; return 1; }
    fi
    
    if [[ -z "${new_vm_name}" ]]; then
        new_vm_name=$(ask "New VM name for the clone" "${source_vm}-clone")
        [[ -z "${new_vm_name}" ]] && { warn "New VM name cannot be empty"; return 1; }
    fi
    
    heading "Cloning VM: ${source_vm} → ${new_vm_name}"
    
    # Find source VM directory and config
    local source_vm_dir=""
    local source_config_file=""
    local source_platform=""
    
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${source_vm}" ]]; then
            source_config_file="$file"
            source_vm_dir=$(dirname "$(dirname "${source_config_file}")")
            source_platform=$(basename "${source_vm_dir}")
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${source_vm}.conf" -print0 2>/dev/null)
    
    [[ -f "${source_config_file}" ]] || die "Source VM config not found: ${source_vm}"
    
    # Check if new VM already exists
    local new_vm_dir="${VM_DIR}/${new_vm_name}_${source_platform}"
    if [[ -d "${new_vm_dir}" ]]; then
        local overwrite
        overwrite=$(ask "Destination VM already exists. Overwrite? (y/n)" "n")
        if [[ "${overwrite}" != "y" ]]; then
            warn "Clone cancelled"
            return 1
        fi
        log "Removing existing VM..."
        rm -rf "${new_vm_dir}"
    fi
    
    # Create new VM directory structure
    ensure_dir "${new_vm_dir}/conf"
    ensure_dir "${new_vm_dir}/qcow2"
    ensure_dir "${new_vm_dir}/sh"
    ensure_dir "${new_vm_dir}/rom"
    ensure_dir "${new_vm_dir}/snapshots"
    
    log "Created directory structure: ${new_vm_dir}"
    
    # Copy configuration file
    local new_config_file="${new_vm_dir}/conf/${new_vm_name}.conf"
    cp "${source_config_file}" "${new_config_file}"
    log "✓ Copied configuration file"
    
    # Update VM name in the configuration
    sed -i.bak "s/${source_vm}/${new_vm_name}/g" "${new_config_file}"
    log "✓ Updated VM name in configuration"
    
    # Copy disk images (use qemu-img convert to ensure compatibility)
    local source_disk_dir="${source_vm_dir}/qcow2"
    local new_disk_dir="${new_vm_dir}/qcow2"
    
    if [[ -d "${source_disk_dir}" ]]; then
        for disk_file in "${source_disk_dir}"/*.qcow2; do
            [[ -f "${disk_file}" ]] || continue
            local disk_name=$(basename "${disk_file}")
            local new_disk_name=$(echo "${disk_name}" | sed "s/${source_vm}/${new_vm_name}/g")
            local new_disk_path="${new_disk_dir}/${new_disk_name}"
            
            log "Cloning disk: ${disk_name} → ${new_disk_name}"
            if qemu-img convert -p -O qcow2 "${disk_file}" "${new_disk_path}" 2>/dev/null; then
                log "✓ Disk cloned successfully"
                # Update disk path in configuration
                sed -i.bak "s|${disk_file}|${new_disk_path}|g" "${new_config_file}"
            else
                warn "✗ Failed to clone disk: ${disk_name}"
            fi
        done
    fi
    
    # Copy ROM files if they exist
    local source_rom_dir="${source_vm_dir}/rom"
    local new_rom_dir="${new_vm_dir}/rom"
    
    if [[ -d "${source_rom_dir}" ]]; then
        for rom_file in "${source_rom_dir}"/*; do
            [[ -f "${rom_file}" ]] || continue
            cp "${rom_file}" "${new_rom_dir}/"
            log "✓ Copied ROM file: $(basename "${rom_file}")"
        done
    fi
    
    # Copy scripts if they exist
    local source_sh_dir="${source_vm_dir}/sh"
    local new_sh_dir="${new_vm_dir}/sh"
    
    if [[ -d "${source_sh_dir}" ]]; then
        for sh_file in "${source_sh_dir}"/*; do
            [[ -f "${sh_file}" ]] || continue
            cp "${sh_file}" "${new_sh_dir}/"
            log "✓ Copied script: $(basename "${sh_file}")"
        done
    fi
    
    log "✅ VM cloned successfully: ${new_vm_name}"
    log "To launch: ${SCRIPT_NAME} launch ${new_vm_name}"
    log "To configure: ${SCRIPT_NAME} edit ${new_vm_name}"
    
    return 0
}

# Clone VM menu
clone_vm_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "clone_vm_menu function requires interactive mode"
        return 1
    fi
    
    clone_vm
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

# Launch MacOS 10.6 Snow Leopard PPC with comprehensive options
launch_macos_10_6_ppc() {
    heading "MacOS X 10.6 Snow Leopard (PPC)"
    log "Optimized configuration for Mac OS X 10.6 with dual display and debugging"
    log "Machine: QEMU mac99 (PowerPC 970fx)"
    log "Note: You need Mac OS X 10.6 Snow Leopard retail DVD ISO"
    log "Reference config: $(config_path "macos-ppc64")"
    
    local qemu
    qemu=$(qemu_bin_or_die "qemu-system-ppc64")

    # Pre-configured settings for MacOS 10.6
    local ram
    ram=$(ask_ram_size "RAM size (MiB) - recommended 2048M for 10.6" "2048")
    
    local cpu="970fx"  # Best CPU for MacOS 10.6
    log "Using CPU: ${cpu} (recommended for MacOS 10.6)"
    
    # SMP configuration - MacOS 10.6 supports multi-core
    local smp_sockets=2
    local smp_cores=1
    local smp_threads=1
    local smp_flags="${smp_sockets},sockets=${smp_sockets},cores=${smp_cores},threads=${smp_threads}"
    log "Using SMP: ${smp_flags}"
    
    local disk
    disk=$(pick_image "macos-106-ppc")
    
    local cdrom
    cdrom=$(pick_cdrom "macos-106-ppc")
    
    # Display configuration - dual screen by default
    local display="${DEFAULT_DISPLAY}"
    if [[ "${display}" == "none" ]]; then
        display=$(ask "Display backend (cocoa/gtk/vnc/spice)" "cocoa")
    fi
    log "Using display backend: ${display}"
    
    # Dual display configuration
    local extra_displays="secondary-vga,vgamem_mb=32"
    log "Configuring dual display: primary + secondary VGA"
    
    # Network configuration
    local network_model="sungem"
    local port_forwards=""
    
    # Add SSH port forwarding for debugging
    port_forwards=$(ask "Additional port forwards (comma-separated host:guest, e.g., 2222:22)" "")
    
    # Add GDB bridge port forwarding
    local gdb_port="${DEFAULT_GDB_BRIDGE_PORT}"
    local gdb_forward="tcp:${gdb_port}::${gdb_port}"
    local combined_forwards
    combined_forwards=$(merge_csv_values "${port_forwards}" "${gdb_forward}")
    
    # ROM/firmware configuration
    local firmware_path=""
    firmware_path=$(ask "Path to Mac ROM file (optional, leave blank for OpenBIOS)" "")
    local firmware_mode="auto"
    
    # Display flags
    local -a dflags; display_flags dflags "${display}" "${qemu}"
    
    # Network flags
    local -a netflags; append_user_network netflags "${network_model}" "${combined_forwards}"
    
    # Debug flags
    local -a dbgflags; qemu_gdb_flags dbgflags
    
    # Build QEMU command
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

    # Add dual display devices
    append_extra_display_devices cmd "${extra_displays}"
    
    # Add firmware if specified
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "Mac ROM"
    
    # Add disk and CDROM
    if [[ -n "${disk}" ]]; then
        cmd+=(-hda "${disk}")
    fi
    if [[ -n "${cdrom}" ]]; then
        cmd+=(-cdrom "${cdrom}" -boot d)
    fi
    
    # Additional optimizations for MacOS 10.6
    cmd+=(
        -device ide-hd,bus=ide.0,unit=0
        -device ide-cd,bus=ide.1,unit=0
    )

    log "MacOS 10.6 PPC Configuration:"
    log "  CPU: ${cpu}"
    log "  RAM: ${ram} MB"
    log "  SMP: ${smp_flags}"
    log "  Display: ${display} + dual VGA"
    log "  Network: ${network_model} with port forwarding"
    log "  Debug: GDB enabled on port ${gdb_port}"
    log "  Disk: ${disk:-none}"
    log "  CDROM: ${cdrom:-none}"
    log ""
    
    log "Running: ${cmd[*]}"
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/macos-106-ppc-$(date +%Y%m%d-%H%M%S).log"
}

# Create and launch MacOS 10.6 PPC VM with comprehensive options
create_and_launch_macos_10_6_ppc() {
    heading "Create and Launch MacOS X 10.6 Snow Leopard (PPC)"
    log "This will create a fully configured VM for MacOS 10.6 with dual display and debugging"
    
    local vm_name
    vm_name=$(ask "VM name for MacOS 10.6 PPC" "macos-106-ppc")
    [[ -z "${vm_name}" ]] && { warn "VM name cannot be empty"; return 1; }
    
    local platform="ppc64"
    local vm_dir="${VM_DIR}/${vm_name}_${platform}"
    
    # Check if VM already exists
    if [[ -d "${vm_dir}" ]]; then
        local overwrite
        overwrite=$(ask "VM directory already exists. Overwrite? (y/n)" "n")
        if [[ "${overwrite}" != "y" ]]; then
            warn "VM creation cancelled"
            return 1
        fi
        log "Removing existing VM..."
        rm -rf "${vm_dir}"
    fi
    
    # Create directory structure
    ensure_dir "${vm_dir}/conf"
    ensure_dir "${vm_dir}/qcow2"
    ensure_dir "${vm_dir}/sh"
    ensure_dir "${vm_dir}/rom"
    ensure_dir "${vm_dir}/snapshots"
    
    log "Created directory structure: ${vm_dir}"
    
    # Configuration parameters
    local ram="2048"
    local cpu="970fx"
    local smp_sockets=2
    local smp_cores=1
    local display_backend="${DEFAULT_DISPLAY}"
    [[ "${display_backend}" == "none" ]] && display_backend="cocoa"
    
    # Disk configuration
    local disk_size="40G"
    local disk_path="${vm_dir}/qcow2/${vm_name}.qcow2"
    local iso_path=""
    
    # Ask for ISO path
    local iso_list=()
    while IFS= read -r -d '' iso_file; do
        iso_list+=("${iso_file}")
    done < <(find "${IMAGES_DIR}" -name "*Mac*10.6*" -o -name "*Snow*Leopard*" | grep -i ".iso" | head -5 | xargs -0 find 2>/dev/null)
    
    if [[ ${#iso_list[@]} -gt 0 ]]; then
        echo "Available MacOS 10.6 ISOs:"
        local i=1
        for iso in "${iso_list[@]}"; do
            echo "  [$i] $(basename "${iso}")"
            ((i++)) || true
        done
        
        local iso_choice
        iso_choice=$(ask "Select ISO (1-${#iso_list[@]}) or enter path" "1")
        
        if [[ "${iso_choice}" =~ ^[0-9]+$ && ${iso_choice} -ge 1 && ${iso_choice} -le ${#iso_list[@]} ]]; then
            iso_path="${iso_list[$((iso_choice-1))]}"
        else
            iso_path=$(ask "Enter path to MacOS 10.6 ISO" "")
        fi
    else
        iso_path=$(ask "Enter path to MacOS 10.6 Snow Leopard ISO" "")
    fi
    
    # Create disk image if it doesn't exist
    if [[ ! -f "${disk_path}" ]]; then
        log "Creating disk image: ${disk_path} (${disk_size})"
        if ! qemu-img create -f qcow2 "${disk_path}" "${disk_size}" 2>/dev/null; then
            warn "Failed to create disk image"
            return 1
        fi
        log "✓ Disk image created"
    else
        log "Using existing disk image: ${disk_path}"
    fi
    
    # Create configuration file
    local config_file="${vm_dir}/conf/${vm_name}.conf"
    cat > "${config_file}" << EOF
# MacOS X 10.6 Snow Leopard (PPC64) Configuration
# VM: ${vm_name}
# Platform: ${platform}
# Created: $(date)

# QEMU binary
QEMU_BIN=qemu-system-ppc64

# Machine/CPU
MACHINE=mac99,via=pmu
CPU=${cpu}
RAM_MB=${ram}
SMP_SOCKETS=${smp_sockets}
SMP_CORES=${smp_cores}
SMP_THREADS=1

# Display
DISPLAY_BACKEND=${display_backend}
DUAL_DISPLAY=yes
EXTRA_DISPLAYS=secondary-vga,vgamem_mb=32

# Storage
HDD_IMAGE=${disk_path}
CDROM_IMAGE=${iso_path}
BOOT_ORDER=d

# Network
NETWORK_MODEL=sungem
NETWORK_TYPE=user

# Debug
ENABLE_GDB=yes
GDB_PORT=${DEFAULT_GDB_PORT}
GDB_BRIDGE_PORT=${DEFAULT_GDB_BRIDGE_PORT}

# Host Integration
VM_SHARED_DIR=${VM_SHARED_DIR}
AUDIO_BACKEND=sdl

# ROM/Firmware
FIRMWARE_PATH=
FIRMWARE_MODE=auto
EOF
    
    log "✓ Configuration file created: ${config_file}"
    
    # Create launch script
    local launch_script="${vm_dir}/sh/launch-${vm_name}.sh"
    cat > "${launch_script}" << 'EOF'
#!/bin/bash
# Launch script for MacOS 10.6 PPC VM
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_DIR="${SCRIPT_DIR}"

# Source configuration
CONFIG_FILE="${CONFIG_DIR}/conf/$(basename "${CONFIG_DIR}").conf"
if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
fi

# Build QEMU command
QEMU="${QEMU_BIN:-qemu-system-ppc64}"
CMD=(
    "${QEMU}"
    -machine "${MACHINE:-mac99,via=pmu}"
    -m "${RAM_MB:-2048}"
    -cpu "${CPU:-970fx}"
    -smp "${SMP_SOCKETS:-2},sockets=${SMP_SOCKETS:-2},cores=${SMP_CORES:-1},threads=${SMP_THREADS:-1}"
    -display "${DISPLAY_BACKEND:-cocoa}"
    -device VGA,vgamem_mb=64
    -device secondary-vga,vgamem_mb=32
    -device usb-kbd
    -device usb-mouse
    -nic user,model="${NETWORK_MODEL:-sungem}"
    -rtc base=localtime
    -gdb tcp::"${GDB_BRIDGE_PORT:-2346}"
)

if [[ -n "${FIRMWARE_PATH}" ]]; then
    CMD+=(-bios "${FIRMWARE_PATH}")
fi

if [[ -n "${HDD_IMAGE}" ]]; then
    CMD+=(-hda "${HDD_IMAGE}")
fi

if [[ -n "${CDROM_IMAGE}" ]]; then
    CMD+=(-cdrom "${CDROM_IMAGE}")
fi

# Port forwarding
CMD+=(-device e1000,netdev=net0 -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::2345-:2345,hostfwd=tcp::2346-:2346)

echo "Launching: ${CMD[*]}"
exec "${CMD[@]}"
EOF
    
    chmod +x "${launch_script}"
    log "✓ Launch script created: ${launch_script}"
    
    log "✅ MacOS 10.6 PPC VM created successfully!"
    log "VM Directory: ${vm_dir}"
    log "Configuration: ${config_file}"
    log "Launch Script: ${launch_script}"
    log ""
    log "To launch manually:"
    log "  cd ${vm_dir}/sh"
    log "  ./launch-${vm_name}.sh"
    log ""
    log "To launch with this script:"
    log "  ${SCRIPT_NAME} launch ${vm_name}"
    
    # Ask if user wants to launch now
    local launch_now
    launch_now=$(ask "Launch VM now? (y/n)" "y")
    if [[ "${launch_now}" == "y" ]]; then
        launch_vm "${vm_name}"
    fi
    
    return 0
}

# Debug MacOS 10.6 PPC VM
# This function launches the VM with enhanced debugging options
debug_macos_10_6_ppc() {
    local vm_name="${1:-macos-106-ppc}"
    
    heading "Debug MacOS X 10.6 Snow Leopard (PPC)"
    log "Launching VM with enhanced debugging for MacOS 10.6"
    
    # Check if VM exists
    local config_file=""
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            config_file="$file"
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
    
    if [[ -z "${config_file}" ]]; then
        warn "VM configuration not found: ${vm_name}"
        local create_option
        create_option=$(ask "Create VM now? (y/n)" "y")
        if [[ "${create_option}" == "y" ]]; then
            create_and_launch_macos_10_6_ppc
            return $?
        else
            return 1
        fi
    fi
    
    # Load configuration
    source "${config_file}" 2>/dev/null || {
        warn "Failed to load configuration: ${config_file}"
        return 1
    }
    
    local qemu="${QEMU_BIN:-qemu-system-ppc64}"
    
    # Display debug information
    log "Debug Configuration for MacOS 10.6 PPC:"
    log "  VM Name: ${vm_name}"
    log "  QEMU Binary: ${qemu}"
    log "  Machine: ${MACHINE:-mac99,via=pmu}"
    log "  CPU: ${CPU:-970fx}"
    log "  RAM: ${RAM_MB:-2048} MB"
    log "  Display: ${DISPLAY_BACKEND:-cocoa}"
    log "  HDD: ${HDD_IMAGE:-none}"
    log "  CDROM: ${CDROM_IMAGE:-none}"
    log ""
    
    # Enhanced debugging configuration
    log "Debug Options:"
    log "  GDB Port: ${GDB_PORT:-1234}"
    log "  GDB Bridge Port: ${GDB_BRIDGE_PORT:-2346}"
    
    # Additional debug ports
    local ssh_port="2222"
    local afp_port="548"
    local tls_port="8443"
    
    log "  SSH Port: ${ssh_port}"
    log "  AFP Port: ${afp_port}"
    log "  TLS Proxy Port: ${tls_port}"
    log ""
    
    # Network configuration with enhanced port forwarding
    local network_model="${NETWORK_MODEL:-sungem}"
    local port_forwards="tcp:${ssh_port}:22,tcp:${afp_port}:548,tcp:${tls_port}:8443,tcp:${GDB_BRIDGE_PORT:-2346}:2346"
    
    # Display configuration
    local -a dflags; display_flags dflags "${DISPLAY_BACKEND:-cocoa}" "${qemu}"
    
    # Network flags with enhanced port forwarding
    local -a netflags; append_user_network netflags "${network_model}" "${port_forwards}"
    
    # Debug flags
    local -a dbgflags; qemu_gdb_flags dbgflags
    
    # Build enhanced debug command
    local cmd=(
        "${qemu}"
        -machine "${MACHINE:-mac99,via=pmu}"
        -m "${RAM_MB:-2048}"
        -cpu "${CPU:-970fx}"
        -smp "${SMP_SOCKETS:-2},sockets=${SMP_SOCKETS:-2},cores=${SMP_CORES:-1},threads=${SMP_THREADS:-1}"
        "${dflags[@]}"
        -device VGA,vgamem_mb=64
        -device secondary-vga,vgamem_mb=32  # Dual display
        -device usb-kbd
        -device usb-mouse
        "${netflags[@]}"
        -rtc base=localtime
        "${dbgflags[@]}"
        -serial stdio  # Serial console for debugging
        -monitor telnet:127.0.0.1:5555,server,nowait  # QEMU monitor
    )
    
    # Add firmware if specified
    if [[ -n "${FIRMWARE_PATH:-}" ]]; then
        append_firmware_attachment cmd "${FIRMWARE_PATH}" "${FIRMWARE_MODE:-auto}" "Mac ROM"
    fi
    
    # Add disk and CDROM
    if [[ -n "${HDD_IMAGE:-}" ]]; then
        cmd+=(-hda "${HDD_IMAGE}")
    fi
    if [[ -n "${CDROM_IMAGE:-}" ]]; then
        cmd+=(-cdrom "${CDROM_IMAGE}" -boot d)
    fi
    
    log "Debug Command:"
    log "  ${cmd[*]}"
    log ""
    log "Debug Access Points:"
    log "  GDB: tcp::${GDB_BRIDGE_PORT:-2346}"
    log "  QEMU Monitor: telnet://127.0.0.1:5555"
    log "  Serial Console: stdio (current terminal)"
    log "  SSH: localhost:${ssh_port} -> guest:22"
    log "  AFP: localhost:${afp_port} -> guest:548"
    log "  TLS Proxy: localhost:${tls_port} -> guest:8443"
    log ""
    log "Connect GDB with:"
    log "  gdb-multiarch -ex 'target remote localhost:${GDB_BRIDGE_PORT:-2346}'"
    log ""
    
    mkdir -p "${VM_LOG_DIR}"
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/debug-${vm_name}-$(date +%Y%m%d-%H%M%S).log"
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
   path = ${VM_SHARED_DIR}
   cnidscheme = dbd
   vol size limit = 0
   valid users = ${current_user}
   rwlist = ${current_user}

[VM_Disks]
   path = ${VM_DIR}
   cnidscheme = dbd
   vol size limit = 0
   valid users = ${current_user}
   rwlist = ${current_user}

[VM_Images]
   path = ${IMAGES_DIR}
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
${VM_SHARED_DIR} "VM RAMDISK" options:usedots,noadouble
${VM_DIR} "VM Disques" options:usedots,noadouble
${IMAGES_DIR} "VM Images" options:usedots,noadouble,ro
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
   path = ${VM_SHARED_DIR}
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

[VM_Images]
   comment = VM Images
   path = ${IMAGES_DIR}
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
    local other_deps=("samba" "netatalk" "XQuartz" "xdialog")
    
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
            "xdialog")
                if detect_xdialog &>/dev/null; then
                    log "✓ XDialog is installed"
                else
                    warn "✗ XDialog is not installed"
                    missing_deps+=("XDialog")
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
        warn "XQuartz not installed. Download from: https://www.xquartz.org"
        return 1
    fi
    
    # Ensure .Xauthority file exists with correct permissions
    if [[ ! -f "$HOME/.Xauthority" ]]; then
        touch "$HOME/.Xauthority" && chmod 600 "$HOME/.Xauthority"
        log "Created .Xauthority file with secure permissions"
    else
        log ".Xauthority file exists"
        chmod 600 "$HOME/.Xauthority"
        log "Ensured .Xauthority has secure permissions"
    fi
    
    export DISPLAY=":0"
    log "Set DISPLAY=:0"
    
    # Configure xhost for local connections
    if xhost +local: &>/dev/null; then
        log "✓ xhost configured for local connections"
    else
        warn "✗ Failed to configure xhost for local connections"
    fi
    
    # Check if XQuartz is running
    if pgrep -x "Xquartz" &>/dev/null; then
        log "✓ XQuartz is running"
    else
        warn "✗ XQuartz is not running"
        log "Start XQuartz with: open -a XQuartz"
    fi
    
    log "XQuartz configuration complete"
    return 0
}

# Configure RAM disk for sharing
configure_ramdisk() {
    heading "Configuring RAMDISK"
    
    # Ensure directory exists
    if [[ ! -d "$SHARE_DIR" ]]; then
        ensure_dir "$SHARE_DIR"
        log "Created directory: $SHARE_DIR"
    else
        log "Directory exists: $SHARE_DIR"
    fi
    
    # Set permissions
    if sudo chmod 1777 "$SHARE_DIR" 2>/dev/null; then
        log "Permissions set to 1777 on: $SHARE_DIR"
    else
        warn "Failed to set permissions on: $SHARE_DIR (may require sudo)"
    fi
    
    # Set ownership
    if sudo chown root:wheel "$SHARE_DIR" 2>/dev/null; then
        log "Ownership set to root:wheel on: $SHARE_DIR"
    else
        warn "Failed to set ownership on: $SHARE_DIR (may require sudo)"
    fi
    
    local disk_usage=$(df -h "$SHARE_DIR" 2>/dev/null | tail -1 | awk '{print $4}')
    [[ -n "$disk_usage" ]] && log "Available space: $disk_usage"
    log "RAMDISK configuration complete: $SHARE_DIR"
    return 0
}

# ---------------------------------------------------------------------------
# XDialog GUI Support
# ---------------------------------------------------------------------------

# Detect if XDialog is available
detect_xdialog() {
    local xdialog_cmd
    
    # Check for xdialog in common paths
    if command -v xdialog &>/dev/null; then
        XDIALOG_PATH=$(command -v xdialog)
        HAVE_XDIALOG=true
        log "✓ XDialog found at: ${XDIALOG_PATH}"
        return 0
    fi
    
    # Check common installation paths
    local xdialog_paths=(
        "/opt/X11/bin/xdialog"
        "/usr/X11/bin/xdialog"
        "/usr/local/bin/xdialog"
        "/usr/bin/xdialog"
    )
    
    for path in "${xdialog_paths[@]}"; do
        if [[ -x "$path" ]]; then
            XDIALOG_PATH="$path"
            HAVE_XDIALOG=true
            log "✓ XDialog found at: ${XDIALOG_PATH}"
            return 0
        fi
    done
    
    # Check if XQuartz is installed and look in its bin directory
    if [[ -d "/Applications/Utilities/XQuartz.app" ]]; then
        local xquartz_bin="/Applications/Utilities/XQuartz.app/Contents/bin/xdialog"
        if [[ -x "$xquartz_bin" ]]; then
            XDIALOG_PATH="$xquartz_bin"
            HAVE_XDIALOG=true
            log "✓ XDialog found via XQuartz at: ${XDIALOG_PATH}"
            return 0
        fi
    fi
    
    HAVE_XDIALOG=false
    XDIALOG_PATH=""
    warn "✗ XDialog not found"
    return 1
}

# Enable XDialog GUI mode
enable_xdialog() {
    if $HAVE_XDIALOG; then
        USE_XDIALOG=true
        log "GUI mode enabled using XDialog"
        return 0
    else
        warn "Cannot enable GUI mode: XDialog not available"
        return 1
    fi
}

# Disable XDialog GUI mode
disable_xdialog() {
    USE_XDIALOG=false
    log "GUI mode disabled, using CLI"
}

# Check if we should use GUI mode
is_gui_mode() {
    [[ "$USE_XDIALOG" == "true" && "$HAVE_XDIALOG" == "true" ]]
}

# GUI file selector using XDialog
gui_file_selector() {
    local title="$1"
    local directory="$2"
    local pattern="$3"
    
    if ! is_gui_mode; then
        # Fallback to CLI
        echo "$(find "${directory:-/}" -name "${pattern:-*}" -type f 2>/dev/null | head -1)"
        return 1
    fi
    
    local result
    result=$(${XDIALOG_PATH} --stdout --title "${title}" --fselect "${directory:-$HOME}/" 2>/dev/null)
    
    if [[ -n "$result" ]]; then
        echo "$result"
        return 0
    else
        return 1
    fi
}

# GUI directory selector using XDialog
gui_dir_selector() {
    local title="$1"
    local directory="$2"
    
    if ! is_gui_mode; then
        # Fallback to CLI
        echo "${directory:-$HOME}"
        return 1
    fi
    
    local result
    result=$(${XDIALOG_PATH} --stdout --title "${title}" --dselect "${directory:-$HOME}/" 2>/dev/null)
    
    if [[ -n "$result" ]]; then
        echo "$result"
        return 0
    else
        return 1
    fi
}

# GUI message box
gui_msgbox() {
    local title="$1"
    local message="$2"
    
    if ! is_gui_mode; then
        # Fallback to CLI
        echo "${message}"
        return 0
    fi
    
    ${XDIALOG_PATH} --title "${title}" --msgbox "${message}" 10 50 2>/dev/null
    return $?
}

# GUI input box
gui_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    local result
    
    if ! is_gui_mode; then
        # Fallback to CLI
        read -rp "${prompt} [${default}]: " result
        echo "${result:-${default}}"
        return 0
    fi
    
    result=$(${XDIALOG_PATH} --stdout --title "${title}" --inputbox "${prompt}" 10 50 "${default}" 2>/dev/null)
    
    if [[ -n "$result" ]]; then
        echo "$result"
        return 0
    else
        echo "$default"
        return 1
    fi
}

# GUI yes/no dialog
gui_yesno() {
    local title="$1"
    local message="$2"
    local default="$3"
    
    if ! is_gui_mode; then
        # Fallback to CLI
        local answer
        read -rp "${message} [${default}]: " answer
        case "${answer:-${default}}" in
            [Yy]*) return 0 ;;
            *) return 1 ;;
        esac
    fi
    
    ${XDIALOG_PATH} --title "${title}" --defaultno --yesno "${message}" 10 50 2>/dev/null
    return $?
}

# Configure XDialog settings
configure_xdialog() {
    heading "Configuring XDialog"
    
    # Try to detect XDialog
    if ! detect_xdialog; then
        log "XDialog configuration:"
        log "  XDialog is not installed."
        log "  Install XDialog via:"
        log "    - MacPorts: sudo port install xdialog"
        log "    - Homebrew: brew install xdialog"
        log "    - Source: https://sourceforge.net/projects/xdialog/"
        return 1
    fi
    
    # Test XDialog functionality
    if ${XDIALOG_PATH} --version &>/dev/null; then
        local version=$(${XDIALOG_PATH} --version 2>/dev/null)
        log "✓ XDialog version: ${version}"
    fi
    
    # Enable GUI mode by default if XDialog is available
    enable_xdialog
    
    log "XDialog configuration complete"
    return 0
}

# ---------------------------------------------------------------------------
# Cross-Compilation Toolchain Detection
# ---------------------------------------------------------------------------

# Known cross-compilation toolchains and their typical binaries
declare -A TOOLCHAIN_BINARIES=(
    ["retro68"]="m68k-elf-gcc m68k-apple-elf-gcc"
    ["powerpc"]="powerpc-elf-gcc powerpc-linux-gnu-gcc powerpc-apple-darwin-gcc"
    ["arm"]="arm-linux-gnueabi-gcc arm-none-eabi-gcc arm-apple-darwin-gcc"
    ["sparc"]="sparc-elf-gcc sparc-linux-gnu-gcc"
    ["x86_64"]="x86_64-elf-gcc x86_64-linux-gnu-gcc"
    ["i386"]="i386-elf-gcc i686-elf-gcc"
    ["riscv"]="riscv64-elf-gcc riscv32-elf-gcc"
    ["mingw"]="x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc"
)

# Known toolchain directories
declare -A TOOLCHAIN_DIRS=(
    ["retro68"]="${HOME}/vm_assistant/vm_clients_3rdparty/macos/Retro68"
    ["powerpc"]="${HOME}/.local/cross-compilers/powerpc"
    ["arm"]="${HOME}/.local/cross-compilers/arm"
    ["sparc"]="${HOME}/.local/cross-compilers/sparc"
    ["x86_64"]="${HOME}/.local/cross-compilers/x86_64"
    ["i386"]="${HOME}/.local/cross-compilers/i386"
)

# Detect available cross-compilation toolchains
detect_cross_compilation_toolchains() {
    heading "Detecting Cross-Compilation Toolchains"
    
    DETECTED_TOOLCHAINS=()
    local found_any=false
    
    log "Searching for cross-compilation toolchains..."
    
    # Check for Retro68 specifically
    if [[ -f "$RETRO68_BIN" ]] || command -v Retro68 &>/dev/null; then
        DETECTED_TOOLCHAINS+=("retro68")
        log "✓ Found Retro68 toolchain"
        found_any=true
    fi
    
    # Check each toolchain type
    for toolchain in "${!TOOLCHAIN_BINARIES[@]}"; do
        local binaries="${TOOLCHAIN_BINARIES[$toolchain]}"
        local found=false
        
        # Check if any of the toolchain binaries are available
        for binary in $binaries; do
            if command -v "$binary" &>/dev/null; then
                found=true
                break
            fi
        done
        
        # Check in known toolchain directories
        if ! $found && [[ -n "${TOOLCHAIN_DIRS[$toolchain]:-}" ]]; then
            local toolchain_dir="${TOOLCHAIN_DIRS[$toolchain]}"
            if [[ -d "$toolchain_dir" ]]; then
                for binary in $binaries; do
                    if [[ -x "${toolchain_dir}/bin/${binary}" ]]; then
                        found=true
                        break
                    fi
                done
            fi
        fi
        
        if $found; then
            DETECTED_TOOLCHAINS+=("$toolchain")
            log "✓ Found ${toolchain} toolchain"
            found_any=true
        fi
    done
    
    # Check for additional toolchains in PATH
    local path_compilers=($(compgen -c | grep -E -- "-(elf|linux|apple|darwin|w64|mingw|gnueabi)-gcc$" || true))
    for compiler in "${path_compilers[@]}"; do
        local toolchain_name
        case "$compiler" in
            m68k-*) toolchain_name="retro68" ;;
            powerpc-*) toolchain_name="powerpc" ;;
            arm-*) toolchain_name="arm" ;;
            sparc-*) toolchain_name="sparc" ;;
            x86_64-*) toolchain_name="x86_64" ;;
            i386-*) toolchain_name="i386" ;;
            riscv-*) toolchain_name="riscv" ;;
            *-mingw32-*) toolchain_name="mingw" ;;
            *) continue ;;
        esac
        
        # Only add if not already detected
        if [[ " ${DETECTED_TOOLCHAINS[@]} " != *" ${toolchain_name} "* ]]; then
            DETECTED_TOOLCHAINS+=("$toolchain_name")
            log "✓ Found ${toolchain_name} toolchain (${compiler})"
            found_any=true
        fi
    done
    
    # Check for toolchain management systems
    if command -v ccache &>/dev/null; then
        log "✓ Found ccache (compiler cache)"
    fi
    
    if command -v cmake &>/dev/null; then
        log "✓ Found CMake build system"
    fi
    
    if command -v ninja &>/dev/null; then
        log "✓ Found Ninja build system"
    fi
    
    if $found_any; then
        log "Detected toolchains: ${DETECTED_TOOLCHAINS[*]}"
    else
        log "No cross-compilation toolchains detected in standard locations"
        log "Install toolchains via:"
        log "  - MacPorts: sudo port install <toolchain>"
        log "  - Homebrew: brew install <toolchain>"
        log "  - Manual: Download and install from vendor websites"
    fi
    
    return 0
}

# Get list of detected toolchains
list_detected_toolchains() {
    if [[ ${#DETECTED_TOOLCHAINS[@]} -eq 0 ]]; then
        log "No toolchains in cache, detecting..."
        detect_cross_compilation_toolchains
    fi
    
    if [[ ${#DETECTED_TOOLCHAINS[@]} -eq 0 ]]; then
        echo "No cross-compilation toolchains detected."
        return 1
    fi
    
    heading "Detected Cross-Compilation Toolchains"
    echo "Found ${#DETECTED_TOOLCHAINS[@]} toolchain(s):"
    
    for toolchain in "${DETECTED_TOOLCHAINS[@]}"; do
        case "$toolchain" in
            "retro68") echo "  ✓ Retro68 (68k MacOS development)" ;;
            "powerpc") echo "  ✓ PowerPC cross-compiler" ;;
            "arm") echo "  ✓ ARM cross-compiler" ;;
            "sparc") echo "  ✓ SPARC cross-compiler" ;;
            "x86_64") echo "  ✓ x86_64 cross-compiler" ;;
            "i386") echo "  ✓ i386 cross-compiler" ;;
            "riscv") echo "  ✓ RISC-V cross-compiler" ;;
            "mingw") echo "  ✓ MinGW (Windows cross-compiler)" ;;
            *) echo "  ✓ ${toolchain} toolchain" ;;
        esac
    done
    
    echo ""
    echo "Toolchain Details:"
    for toolchain in "${DETECTED_TOOLCHAINS[@]}"; do
        local binaries="${TOOLCHAIN_BINARIES[$toolchain]}"
        echo "  ${toolchain}:"
        for binary in $binaries; do
            if command -v "$binary" &>/dev/null; then
                echo "    ✓ ${binary} [$(command -v "$binary")]"
            elif [[ -n "${TOOLCHAIN_DIRS[$toolchain]:-}" ]] && [[ -x "${TOOLCHAIN_DIRS[$toolchain]}/bin/${binary}" ]]; then
                echo "    ✓ ${binary} [${TOOLCHAIN_DIRS[$toolchain]}/bin/${binary}]"
            else
                echo "    ✗ ${binary} [not found]"
            fi
        done
    done
}

# Check for specific toolchain
has_toolchain() {
    local toolchain="$1"
    [[ " ${DETECTED_TOOLCHAINS[@]} " == *" ${toolchain} "* ]]
}

# Get compiler path for a specific toolchain
get_toolchain_compiler() {
    local toolchain="$1"
    local compiler_type="$2"  # gcc, g++, cc, etc.
    
    local binaries="${TOOLCHAIN_BINARIES[$toolchain]}"
    
    for binary in $binaries; do
        # Replace gcc with the requested compiler type
        local target_compiler="${binary/gcc/${compiler_type:-gcc}}"
        
        if command -v "$target_compiler" &>/dev/null; then
            echo "$(command -v "$target_compiler")"
            return 0
        elif [[ -n "${TOOLCHAIN_DIRS[$toolchain]:-}" ]] && [[ -x "${TOOLCHAIN_DIRS[$toolchain]}/bin/${target_compiler}" ]]; then
            echo "${TOOLCHAIN_DIRS[$toolchain]}/bin/${target_compiler}"
            return 0
        fi
    done
    
    return 1
}

# Setup toolchain environment variables
setup_toolchain_environment() {
    local toolchain="$1"
    local toolchain_dir=""
    
    case "$toolchain" in
        "retro68") toolchain_dir="$RETRO68_DIR" ;;
        *) toolchain_dir="${TOOLCHAIN_DIRS[$toolchain]:-}" ;;
    esac
    
    if [[ -d "$toolchain_dir" ]]; then
        log "Setting up environment for ${toolchain} toolchain"
        
        # Add toolchain bin directory to PATH
        local bin_dir="${toolchain_dir}/bin"
        if [[ -d "$bin_dir" && "$PATH" != *"$bin_dir"* ]]; then
            export PATH="${bin_dir}:${PATH}"
            log "Added to PATH: ${bin_dir}"
        fi
        
        # Set environment variables based on toolchain
        case "$toolchain" in
            "retro68")
                export RETRO68_HOME="$toolchain_dir"
                log "Set RETRO68_HOME: ${toolchain_dir}"
                ;;
            "powerpc")
                export POWERPC_TOOLCHAIN="$toolchain_dir"
                log "Set POWERPC_TOOLCHAIN: ${toolchain_dir}"
                ;;
            "arm")
                export ARM_TOOLCHAIN="$toolchain_dir"
                log "Set ARM_TOOLCHAIN: ${toolchain_dir}"
                ;;
        esac
        
        log "Environment setup complete for ${toolchain}"
        return 0
    else
        warn "Toolchain directory not found: ${toolchain_dir}"
        return 1
    fi
}

# Configure cross-compilation toolchain (interactive)
configure_toolchain() {
    heading "Configure Cross-Compilation Toolchain"
    
    # First detect what's available
    detect_cross_compilation_toolchains
    
    if [[ ${#DETECTED_TOOLCHAINS[@]} -eq 0 ]]; then
        log "No cross-compilation toolchains detected."
        ask "Would you like to install Retro68 toolchain for 68k development?" "no" | grep -iq "y" && {
            install_retro68
        }
        return 0
    fi
    
    # Show detected toolchains
    list_detected_toolchains
    
    # Ask user to select a toolchain to configure
    local options=()
    for toolchain in "${DETECTED_TOOLCHAINS[@]}"; do
        options+=("$toolchain" "$toolchain")
    done
    options+=("all" "Configure all detected toolchains")
    options+=("none" "Skip configuration")
    
    if is_gui_mode; then
        # GUI selection
        local choice
        choice=$(gui_inputbox "Select Toolchain" "Choose a toolchain to configure:" "${DETECTED_TOOLCHAINS[0]}")
    else
        # CLI selection
        local choice
        echo "Available toolchains:"
        for i in "${!DETECTED_TOOLCHAINS[@]}"; do
            echo "  [$((i+1))] ${DETECTED_TOOLCHAINS[$i]}"
        done
        echo "  [A] Configure all"
        echo "  [S] Skip"
        choice=$(ask "Select toolchain" "")
        
        case "${choice}" in
            [Aa]) choice="all" ;;
            [Ss]) choice="none" ;;
            [1-9]*) 
                local index=$((choice - 1))
                if [[ $index -lt ${#DETECTED_TOOLCHAINS[@]} ]]; then
                    choice="${DETECTED_TOOLCHAINS[$index]}"
                fi
                ;;
        esac
    fi
    
    case "$choice" in
        "none")
            log "Skipped toolchain configuration"
            ;;
        "all")
            for toolchain in "${DETECTED_TOOLCHAINS[@]}"; do
                setup_toolchain_environment "$toolchain"
            done
            ;;
        "")
            # Default to first toolchain
            setup_toolchain_environment "${DETECTED_TOOLCHAINS[0]}"
            ;;
        *)
            if has_toolchain "$choice"; then
                setup_toolchain_environment "$choice"
            else
                warn "Toolchain not detected: $choice"
            fi
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Build Automation Workflow
# ---------------------------------------------------------------------------

# Build project directory
PROJECTS_DIR="${CONFIG_DIR}/projects"
BUILD_LOG_DIR="${VM_LOG_DIR}/builds"

# Create projects directory
ensure_projects_dir() {
    ensure_dir "$PROJECTS_DIR"
    ensure_dir "$BUILD_LOG_DIR"
}

# Build project using detected toolchain
build_project() {
    local project_name="$1"
    local project_path="$2"
    local target_arch="$3"
    local toolchain="$4"
    local output_dir="$5"
    
    ensure_projects_dir
    
    if [[ -z "$project_path" ]]; then
        # Try to find project in projects directory
        project_path="${PROJECTS_DIR}/${project_name}"
        if [[ ! -d "$project_path" ]]; then
            die "Project not found: ${project_name}. Specify path or create project first."
        fi
    fi
    
    if [[ ! -d "$project_path" ]]; then
        die "Project directory not found: ${project_path}"
    fi
    
    # Ensure output directory exists
    [[ -n "$output_dir" ]] || output_dir="${project_path}/build"
    ensure_dir "$output_dir"
    
    heading "Building Project: ${project_name}"
    log "Project path: ${project_path}"
    log "Target architecture: ${target_arch:-unknown}"
    log "Output directory: ${output_dir}"
    
    # Determine toolchain to use
    if [[ -n "$toolchain" ]]; then
        if ! has_toolchain "$toolchain"; then
            log "Toolchain ${toolchain} not detected, trying to detect available toolchains..."
            detect_cross_compilation_toolchains
            
            if ! has_toolchain "$toolchain"; then
                die "Specified toolchain not available: ${toolchain}"
            fi
        fi
    else
        # Auto-select toolchain based on target architecture
        log "Auto-selecting toolchain for ${target_arch}..."
        toolchain=$(select_toolchain_for_arch "${target_arch}")
        if [[ -z "$toolchain" ]]; then
            log "No specific toolchain found for ${target_arch}, using system compiler"
            toolchain="system"
        fi
    fi
    
    # Setup toolchain environment
    if [[ "$toolchain" != "system" ]]; then
        setup_toolchain_environment "$toolchain"
    fi
    
    # Check for Makefile
    if [[ -f "${project_path}/Makefile" ]]; then
        log "Building with Makefile..."
        local build_cmd="make"
        local target=""
        
        # Check for architecture-specific targets
        case "${target_arch}" in
            "68k"|"m68k") target="68k" ;;
            "ppc") target="ppc" ;;
            "arm") target="arm" ;;
            "x86"|"x86_64") target="x86" ;;
        esac
        
        if [[ -n "$target" ]]; then
            build_cmd="make ${target}"
        fi
        
        # Execute build with logging
        local log_file="${BUILD_LOG_DIR}/${project_name}-$(date +%Y%m%d-%H%M%S).log"
        log "Build log: ${log_file}"
        
        if (cd "$project_path" && ${build_cmd} 2>&1 | tee "$log_file"); then
            log "✅ Build successful"
            return 0
        else
            warn "❌ Build failed. Check log: ${log_file}"
            return 1
        fi
    fi
    
    warn "No Makefile found in project directory: ${project_path}"
    return 1
}

# Select appropriate toolchain for target architecture
select_toolchain_for_arch() {
    local target_arch="$1"
    
    case "${target_arch}" in
        "68k"|"m68k"|"mac68k")
            if has_toolchain "retro68"; then
                echo "retro68"
            fi
            ;;
        "ppc"|"powerpc")
            if has_toolchain "powerpc"; then
                echo "powerpc"
            fi
            ;;
        "arm"|"arm64")
            if has_toolchain "arm"; then
                echo "arm"
            fi
            ;;
        "sparc")
            if has_toolchain "sparc"; then
                echo "sparc"
            fi
            ;;
        "x86"|"x86_64"|"i386")
            if has_toolchain "x86_64" || has_toolchain "i386"; then
                echo "x86_64"
            fi
            ;;
        *)
            # Try to find any available toolchain
            if [[ ${#DETECTED_TOOLCHAINS[@]} -gt 0 ]]; then
                echo "${DETECTED_TOOLCHAINS[0]}"
            fi
            ;;
    esac
}

# Deploy to VM after build
deploy_to_vm() {
    local project_name="$1"
    local vm_name="$2"
    local binary_path="$3"
    local deploy_dir="$4"
    
    heading "Deploying to VM: ${vm_name}"
    
    if [[ -z "$binary_path" ]]; then
        # Try to find built binary in common locations
        local project_path="${PROJECTS_DIR}/${project_name}"
        local build_dirs=(
            "${project_path}/build"
            "${project_path}/bin"
            "${project_path}/dist"
            "${project_path}"
        )
        
        for dir in "${build_dirs[@]}"; do
            if [[ -f "${dir}/${project_name}" ]]; then
                binary_path="${dir}/${project_name}"
                break
            elif [[ -f "${dir}/${project_name}.elf" ]]; then
                binary_path="${dir}/${project_name}.elf"
                break
            elif [[ -f "${dir}/output.elf" ]]; then
                binary_path="${dir}/output.elf"
                break
            fi
        done
        
        if [[ -z "$binary_path" ]]; then
            die "Could not find built binary for project: ${project_name}"
        fi
    fi
    
    if [[ ! -f "$binary_path" ]]; then
        die "Binary not found: ${binary_path}"
    fi
    
    # Check if VM exists
    if ! find_vm_config "$vm_name"; then
        die "VM not found: ${vm_name}"
    fi
    
    # Deploy the binary
    log "Deploying binary: ${binary_path}"
    if ! deploy_binary "$vm_name" "$binary_path"; then
        warn "Failed to deploy binary to VM: ${vm_name}"
        return 1
    fi
    
    log "✅ Binary deployed successfully to: ${vm_name}"
    return 0
}

# Full build-deploy-debug workflow
build_deploy_debug_workflow() {
    local project_name="$1"
    local vm_name="$2"
    local toolchain="$3"
    local target_arch="$4"
    local skip_build="$5"
    local skip_deploy="$6"
    
    heading "Build-Deploy-Debug Workflow: ${project_name} → ${vm_name}"
    
    ensure_projects_dir
    
    # Step 1: Build (unless skipped)
    if [[ "$skip_build" != "true" ]]; then
        log "Step 1: Building project..."
        if ! build_project "$project_name" "" "$target_arch" "$toolchain"; then
            warn "Build failed, skipping workflow"
            return 1
        fi
    else
        log "Skipping build step"
    fi
    
    # Step 2: Deploy (unless skipped)
    if [[ "$skip_deploy" != "true" ]]; then
        log "Step 2: Deploying to VM..."
        if ! deploy_to_vm "$project_name" "$vm_name"; then
            warn "Deploy failed, skipping debug"
            return 1
        fi
    else
        log "Skipping deploy step"
    fi
    
    # Step 3: Debug
    log "Step 3: Starting debug session..."
    if ! debug_start "$vm_name"; then
        warn "Failed to start debug session"
        return 1
    fi
    
    log "✅ Build-Deploy-Debug workflow completed successfully"
    return 0
}

# Create development project template
create_dev_project() {
    local project_name="$1"
    local template_type="$2"
    local target_arch="$3"
    local project_path="${PROJECTS_DIR}/${project_name}"
    
    ensure_projects_dir
    
    heading "Creating Development Project: ${project_name}"
    log "Project type: ${template_type:-generic}"
    log "Target architecture: ${target_arch:-unknown}"
    
    # Create project directory
    if [[ -d "$project_path" ]]; then
        die "Project directory already exists: ${project_path}"
    fi
    
    mkdir -p "$project_path/src" "$project_path/include" "$project_path/build"
    
    # Create template files based on type
    case "$template_type" in
        "retro68"|"68k")
            create_retro68_project "$project_name" "$project_path" "$target_arch"
            ;;
        "ppc")
            create_ppc_project "$project_name" "$project_path" "$target_arch"
            ;;
        "arm")
            create_arm_project "$project_name" "$project_path" "$target_arch"
            ;;
        "generic"|*)
            create_generic_project "$project_name" "$project_path" "$target_arch"
            ;;
    esac
    
    log "✅ Project created at: ${project_path}"
    return 0
}

# Create Retro68 project template
create_retro68_project() {
    local project_name="$1"
    local project_path="$2"
    local target_arch="$3"
    
    # Create main source file
    cat > "${project_path}/src/main.c" << 'EOF'
#include <stdio.h>

int main() {
    printf("Hello from Retro68!\n");
    return 0;
}
EOF
    
    # Create Makefile for Retro68
    cat > "${project_path}/Makefile" << MAKEFILE_END
# Retro68 Project Makefile
TARGET = ${project_name}
SRC = src/main.c
CC = m68k-elf-gcc
CFLAGS = -Wall -O2 -mcpu=68000
LDFLAGS = -T macos71.ld

all: build/\$(TARGET).elf

build/\$(TARGET).elf: \$(SRC)
	mkdir -p build
	\$(CC) \$(CFLAGS) \$(LDFLAGS) -o \$@ \$^

clean:
	rm -rf build/*

.PHONY: all clean
MAKEFILE_END
    
    # Create project config
    cat > "${project_path}/project.cfg" << EOF
project_name=${project_name}
target_arch=${target_arch:-68k}
toolchain=retro68
compiler=m68k-elf-gcc
EOF
    
    log "Created Retro68 project template"
}

# Create generic project template
create_generic_project() {
    local project_name="$1"
    local project_path="$2"
    local target_arch="$3"
    
    # Create main source file
    cat > "${project_path}/src/main.c" << 'EOF'
#include <stdio.h>

int main() {
    printf("Hello World!\n");
    return 0;
}
EOF
    
    # Create simple Makefile
    cat > "${project_path}/Makefile" << MAKEFILE_END
# Generic Project Makefile
TARGET = ${project_name}
SRC = src/main.c

all: build/\$(TARGET)

build/\$(TARGET): \$(SRC)
	mkdir -p build
	gcc -Wall -O2 -o \$@ \$^

clean:
	rm -rf build/*

.PHONY: all clean
MAKEFILE_END
    
    # Create project config
    cat > "${project_path}/project.cfg" << EOF
project_name=${project_name}
target_arch=${target_arch:-generic}
toolchain=system
compiler=gcc
EOF
    
    log "Created generic project template"
}

# Create PPC project template
create_ppc_project() {
    local project_name="$1"
    local project_path="$2"
    local target_arch="$3"
    
    # Create main source file
    cat > "${project_path}/src/main.c" << 'EOF'
#include <stdio.h>

int main() {
    printf("Hello from PowerPC!\n");
    return 0;
}
EOF
    
    # Create Makefile for PowerPC
    cat > "${project_path}/Makefile" << MAKEFILE_END
# PowerPC Project Makefile
TARGET = ${project_name}
SRC = src/main.c
CC = powerpc-elf-gcc
CFLAGS = -Wall -O2
LDFLAGS = 

all: build/\$(TARGET).elf

build/\$(TARGET).elf: \$(SRC)
	mkdir -p build
	\$(CC) \$(CFLAGS) \$(LDFLAGS) -o \$@ \$^

clean:
	rm -rf build/*

.PHONY: all clean
MAKEFILE_END
    
    # Create project config
    cat > "${project_path}/project.cfg" << EOF
project_name=${project_name}
target_arch=${target_arch:-ppc}
toolchain=powerpc
compiler=powerpc-elf-gcc
EOF
    
    log "Created PowerPC project template"
}

# Create ARM project template
create_arm_project() {
    local project_name="$1"
    local project_path="$2"
    local target_arch="$3"
    
    # Create main source file
    cat > "${project_path}/src/main.c" << 'EOF'
#include <stdio.h>

int main() {
    printf("Hello from ARM!\n");
    return 0;
}
EOF
    
    # Create Makefile for ARM
    cat > "${project_path}/Makefile" << MAKEFILE_END
# ARM Project Makefile
TARGET = ${project_name}
SRC = src/main.c
CC = arm-none-eabi-gcc
CFLAGS = -Wall -O2 -mcpu=arm7tdmi
LDFLAGS = -T arm.ld

all: build/\$(TARGET).elf

build/\$(TARGET).elf: \$(SRC)
	mkdir -p build
	\$(CC) \$(CFLAGS) \$(LDFLAGS) -o \$@ \$^

clean:
	rm -rf build/*

.PHONY: all clean
MAKEFILE_END
    
    # Create project config
    cat > "${project_path}/project.cfg" << EOF
project_name=${project_name}
target_arch=${target_arch:-arm}
toolchain=arm
compiler=arm-none-eabi-gcc
EOF
    
    log "Created ARM project template"
}

# ---------------------------------------------------------------------------
# Source Code Mounting
# ---------------------------------------------------------------------------

# Mount source code directory into VM for development
mount_source_code() {
    local vm_name="$1"
    local source_dir="$2"
    local mount_point="$3"
    local readonly="$4"
    
    heading "Mounting Source Code for VM: ${vm_name}"
    
    # Validate VM exists
    if ! find_vm_config "$vm_name"; then
        die "VM not found: ${vm_name}"
    fi
    
    # Validate source directory
    if [[ -z "$source_dir" ]]; then
        # Use projects directory by default
        source_dir="$PROJECTS_DIR"
    fi
    
    if [[ ! -d "$source_dir" ]]; then
        die "Source directory not found: ${source_dir}"
    fi
    
    # Validate mount point
    if [[ -z "$mount_point" ]]; then
        mount_point="/mnt/source"
    fi
    
    # Ensure absolute path
    source_dir="$(cd "$source_dir" && pwd)"
    
    log "Source directory: ${source_dir}"
    log "Mount point: ${mount_point}"
    log "Read-only: ${readonly:-yes}"
    
    # Check if VM is running
    if is_vm_running "$vm_name"; then
        warn "Cannot mount directory while VM is running"
        log "Stop the VM first, then add the mount configuration"
        return 1
    fi
    
    # Update VM configuration to include the mount
    local config_file="$(find_vm_config_file "$vm_name")"
    if [[ -z "$config_file" ]]; then
        die "Could not find VM config file for: ${vm_name}"
    fi
    
    # Add virtio-9p or virtfs configuration
    local fs_type="virtio-9p"
    local fs_id="source_$(echo "$vm_name" | tr - _)"
    local security_model="mapped-file"
    
    # Check if already mounted
    if grep -q "${source_dir}" "$config_file"; then
        log "Source directory already mounted in VM configuration"
        return 0
    fi
    
    # Add 9P filesystem configuration
    echo "" >> "$config_file"
    echo "# Source code mounting" >> "$config_file"
    echo "QEMU_FS_TYPE_${fs_id}=\"${fs_type}\"" >> "$config_file"
    echo "QEMU_FS_SOURCE_${fs_id}=\"${source_dir}\"" >> "$config_file"
    echo "QEMU_FS_MOUNT_${fs_id}=\"${mount_point}\"" >> "$config_file"
    echo "QEMU_FS_SECURITY_${fs_id}=\"${security_model}\"" >> "$config_file"
    echo "QEMU_FS_READONLY_${fs_id}=\"${readonly:-yes}\"" >> "$config_file"
    
    log "✅ Source directory configured for mounting"
    log "Add this to your QEMU command:"
    log "  -fsdev ${fs_type},id=${fs_id},path=${source_dir},security_model=${security_model}\"
    log "  -device virtio-9p-pci,fsdev=${fs_id},mount_tag=${mount_point}"
    
    return 0
}

# Unmount/Remove source code mount from VM
unmount_source_code() {
    local vm_name="$1"
    local mount_point="$2"
    
    heading "Removing Source Code Mount from VM: ${vm_name}"
    
    # Validate VM exists
    if ! find_vm_config "$vm_name"; then
        die "VM not found: ${vm_name}"
    fi
    
    local config_file="$(find_vm_config_file "$vm_name")"
    if [[ -z "$config_file" ]]; then
        die "Could not find VM config file for: ${vm_name}"
    fi
    
    if [[ -z "$mount_point" ]]; then
        mount_point="/mnt/source"
    fi
    
    # Remove source code mounting configuration
    local temp_file="${config_file}.tmp"
    
    if grep -q "source_${vm_name}" "$config_file"; then
        # Remove all lines related to this mount
        grep -v "QEMU_FS_.*_source_${vm_name}" "$config_file" > "$temp_file"
        mv "$temp_file" "$config_file"
        log "✅ Source code mount configuration removed"
    else
        log "No source code mount found for VM: ${vm_name}"
        return 1
    fi
    
    return 0
}

# List mounted source directories for VM
list_source_mounts() {
    local vm_name="$1"
    
    heading "Source Code Mounts for VM: ${vm_name}"
    
    # Validate VM exists
    if ! find_vm_config "$vm_name"; then
        die "VM not found: ${vm_name}"
    fi
    
    local config_file="$(find_vm_config_file "$vm_name")"
    if [[ -z "$config_file" ]]; then
        die "Could not find VM config file for: ${vm_name}"
    fi
    
    local mounts_found=false
    
    while IFS= read -r line; do
        if [[ "$line" =~ QEMU_FS_TYPE_[^=]+=.*source_ ]]; then
            local fs_id=$(echo "$line" | sed 's|QEMU_FS_TYPE_||;s|=.*||')
            local source_path=$(grep "QEMU_FS_SOURCE_${fs_id}=" "$config_file" | sed 's|.*=||')
            local mount_point=$(grep "QEMU_FS_MOUNT_${fs_id}=" "$config_file" | sed 's|.*=||')
            local readonly=$(grep "QEMU_FS_READONLY_${fs_id}=" "$config_file" | sed 's|.*=||')
            
            echo "  ✓ ${source_path} -> ${mount_point} [readonly: ${readonly}]"
            mounts_found=true
        fi
    done < "$config_file"
    
    if ! $mounts_found; then
        log "No source code mounts configured for VM: ${vm_name}"
    fi
}

# Mount source code interactive
mount_source_code_interactive() {
    if ! is_interactive; then
        warn "mount_source_code_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Mount Source Code Directory"
    
    # List VMs
    list_vms
    
    local vm_name=$(ask "Select VM name" "")
    if [[ -z "$vm_name" ]]; then
        warn "VM name is required"
        return 1
    fi
    
    # List projects
    list_projects
    
    local source_dir=$(ask "Source directory to mount" "$PROJECTS_DIR")
    local mount_point=$(ask "Mount point in VM" "/mnt/source")
    local readonly=$(ask "Read-only mount?" "yes")
    
    mount_source_code "$vm_name" "$source_dir" "$mount_point" "$readonly"
}

# List development projects
list_projects() {
    ensure_projects_dir
    
    heading "Development Projects"
    
    if [[ -d "$PROJECTS_DIR" ]]; then
        local projects=()
        local project
        
        for project_dir in "${PROJECTS_DIR}"/*/; do
            if [[ -f "${project_dir}project.cfg" ]]; then
                local project_name=$(grep -E "^project_name=" "${project_dir}project.cfg" | cut -d'=' -f2)
                local target_arch=$(grep -E "^target_arch=" "${project_dir}project.cfg" | cut -d'=' -f2)
                local toolchain=$(grep -E "^toolchain=" "${project_dir}project.cfg" | cut -d'=' -f2)
                
                projects+=("${project_name:-$(basename "$project_dir")}")
                echo "  ✓ $(basename "$project_dir") [${target_arch:-unknown}/${toolchain:-system}]"
            else
                echo "  ? $(basename "$project_dir") [no config]"
            fi
        done
        
        if [[ ${#projects[@]} -eq 0 ]]; then
            log "No projects found in ${PROJECTS_DIR}"
        else
            local count=${#projects[@]}
            log "Found ${count} projects"
        fi
    else
        log "No projects directory found"
    fi
}

# Build project menu
build_project_menu() {
    if ! is_interactive; then
        warn "build_project_menu function requires interactive mode"
        return 1
    fi
    
    heading "Build Project Menu"
    
    # List available projects
    list_projects
    
    echo ""
    local project_name=$(ask "Enter project name" "")
    
    if [[ -z "$project_name" ]]; then
        log "No project specified"
        return 1
    fi
    
    local project_path="${PROJECTS_DIR}/${project_name}"
    if [[ ! -d "$project_path" ]]; then
        ask "Project not found. Create new project?" "yes" | grep -iq "y" && {
            local template_type=$(ask "Select project template" "generic")
            local target_arch=$(ask "Target architecture" "")
            create_dev_project "$project_name" "$template_type" "$target_arch"
            project_path="${PROJECTS_DIR}/${project_name}"
        }
    fi
    
    # Select toolchain
    detect_cross_compilation_toolchains
    local toolchain=$(ask "Select toolchain (leave empty for auto-select)" "")
    
    # Build the project
    build_project "$project_name" "$project_path" "" "$toolchain"
    
    if is_yes "$(ask "Deploy to VM?" "yes")"; then
        local vm_name=$(ask "VM name" "")
        if [[ -n "$vm_name" ]]; then
            deploy_to_vm "$project_name" "$vm_name"
        fi
    fi
}

# Create development project interactive
create_dev_project_interactive() {
    if ! is_interactive; then
        warn "create_dev_project_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Create Development Project"
    
    local project_name=$(ask "Project name" "")
    if [[ -z "$project_name" ]]; then
        warn "Project name is required"
        return 1
    fi
    
    local template_type=$(ask "Project template type" "generic")
    local target_arch=$(ask "Target architecture (68k, ppc, arm, etc.)" "")
    
    create_dev_project "$project_name" "$template_type" "$target_arch"
}

# Build-Deploy-Debug interactive workflow
build_deploy_debug_interactive() {
    if ! is_interactive; then
        warn "build_deploy_debug_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Build-Deploy-Debug Workflow"
    
    # List available projects
    list_projects
    
    local project_name=$(ask "Project name" "")
    if [[ -z "$project_name" ]]; then
        warn "Project name is required"
        return 1
    fi
    
    # List available VMs
    list_vms
    
    local vm_name=$(ask "Target VM name" "")
    if [[ -z "$vm_name" ]]; then
        warn "VM name is required"
        return 1
    fi
    
    detect_cross_compilation_toolchains
    local toolchain=$(ask "Toolchain (leave empty for auto-select)" "")
    local target_arch=$(ask "Target architecture (leave empty for auto-detect)" "")
    
    local skip_build=$(ask "Skip build step?" "no")
    local skip_deploy=$(ask "Skip deploy step?" "no")
    
    build_deploy_debug_workflow "$project_name" "$vm_name" "$toolchain" "$target_arch" "$skip_build" "$skip_deploy"
}

# ---------------------------------------------------------------------------
# GUI Application Launcher
# ---------------------------------------------------------------------------

# Launch GUI application from VM via XQuartz
launch_gui_application() {
    local vm_name="$1"
    local app_path="$2"
    local display="$3"
    local use_xquartz="$4"
    
    heading "Launching GUI Application from VM: ${vm_name}"
    
    # Validate VM exists
    if ! find_vm_config "$vm_name"; then
        die "VM not found: ${vm_name}"
    fi
    
    # Check if VM is running
    if ! is_vm_running "$vm_name"; then
        warn "VM is not running: ${vm_name}"
        ask "Start VM now?" "yes" | grep -iq "y" && launch_vm "$vm_name" || return 1
        
        # Wait a bit for VM to start
        sleep 5
        
        if ! is_vm_running "$vm_name"; then
            die "Failed to start VM: ${vm_name}"
        fi
    fi
    
    # Validate application path
    if [[ -z "$app_path" ]]; then
        die "Application path is required"
    fi
    
    # Setup XQuartz if requested
    if is_yes "$use_xquartz" && ! configure_xquartz; then
        warn "XQuartz configuration failed"
        # Continue anyway, might work without explicit configuration
    fi
    
    # Set display if not provided
    if [[ -z "$display" ]]; then
        if $USE_XDIALOG && $HAVE_XDIALOG; then
            display=":0"
        else
            display=":0"
        fi
    fi
    
    log "Using display: ${display}"
    log "Launching application: ${app_path}"
    
    # Get VM IP address or use hostname
    local vm_ip=""
    if get_vm_ip "$vm_name"; then
        vm_ip=$(get_vm_ip "$vm_name")
    else
        # Try to get IP from VM config
        local config_file="$(find_vm_config_file "$vm_name")"
        if [[ -f "$config_file" ]]; then
            vm_ip=$(grep -E "^IP_ADDRESS|^GUEST_IP" "$config_file" | head -1 | cut -d'=' -f2)
        fi
    fi
    
    if [[ -z "$vm_ip" ]]; then
        # Fallback to using VM name as hostname
        vm_ip="$vm_name"
        log "Using VM name as hostname: ${vm_ip}"
    else
        log "VM IP address: ${vm_ip}"
    fi
    
    # Check if we can SSH to the VM
    if command -v ssh &>/dev/null; then
        # Try to launch the application via SSH with X11 forwarding
        local ssh_cmd="ssh -X ${vm_ip} 'DISPLAY=${display} ${app_path} &'"
        log "Launching via SSH with X11 forwarding..."
        log "Command: ${ssh_cmd}"
        
        if eval "$ssh_cmd"; then
            log "✅ GUI application launched successfully"
            return 0
        else
            warn "Failed to launch GUI application via SSH"
            return 1
        fi
    else
        warn "SSH not available, cannot launch GUI application remotely"
        return 1
    fi
}

# Launch GUI application with file selection
launch_gui_application_interactive() {
    if ! is_interactive; then
        warn "launch_gui_application_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Launch GUI Application from VM"
    
    # List running VMs
    log "Available VMs:"
    list_vms
    
    local vm_name=$(ask "Select VM name" "")
    if [[ -z "$vm_name" ]]; then
        warn "VM name is required"
        return 1
    fi
    
    # Ask for application path
    local app_path
    if is_gui_mode; then
        app_path=$(gui_file_selector "Select Application" "" "*.app")
    else
        app_path=$(ask "Enter application path in VM" "")
    fi
    
    if [[ -z "$app_path" ]]; then
        warn "Application path is required"
        return 1
    fi
    
    local use_xquartz=$(ask "Use XQuartz for display?" "yes")
    local display=$(ask "Display to use" "$DISPLAY")
    
    launch_gui_application "$vm_name" "$app_path" "$display" "$use_xquartz"
}

# Configure XQuartz optimization
configure_xquartz_optimization() {
    heading "Configuring XQuartz Optimization"
    
    # Check if XQuartz is installed
    if [[ ! -d "/Applications/Utilities/XQuartz.app" ]]; then
        warn "XQuartz not installed"
        log "Download XQuartz from: https://www.xquartz.org"
        return 1
    fi
    
    # Check if XQuartz is running
    if ! pgrep -x "Xquartz" &>/dev/null; then
        warn "XQuartz is not running"
        log "Starting XQuartz..."
        if open -a XQuartz; then
            sleep 3
        else
            warn "Failed to start XQuartz"
            return 1
        fi
    fi
    
    # Configure XQuartz security settings
    if [[ -f "/etc/X11/xinit/xserverrc" ]]; then
        log "Configuring XQuartz security..."
        echo "allowed_users=anybody" | sudo tee /etc/X11/xinit/xserverrc >/dev/null
        log "✅ XQuartz security configured for all users"
    else
        warn "XQuartz security config not found"
    fi
    
    # Configure xhost for local connections
    if xhost +local: &>/dev/null; then
        log "✅ xhost configured for local connections"
    else
        warn "✗ Failed to configure xhost"
    fi
    
    # Test X11 forwarding
    local test_result
    if xclock -display "$DISPLAY" &>/dev/null; then
        log "✅ X11 display is working"
        pkill xclock
    else
        warn "✗ X11 display test failed"
    fi
    
    log "XQuartz optimization complete"
    return 0
}

# ---------------------------------------------------------------------------
# Testing Framework Integration
# ---------------------------------------------------------------------------

# Test directory structure
TESTS_DIR="${CONFIG_DIR}/tests"
TEST_RESULTS_DIR="${VM_LOG_DIR}/test_results"

# Ensure test directories exist
ensure_test_directories() {
    ensure_dir "$TESTS_DIR"
    ensure_dir "$TEST_RESULTS_DIR"
}

# Run automated tests in target VM
run_vm_tests() {
    local vm_name="$1"
    local test_script="$2"
    local test_type="$3"
    local output_dir="$4"
    
    heading "Running Tests in VM: ${vm_name}"
    
    # Validate VM exists and is running
    if ! find_vm_config "$vm_name"; then
        die "VM not found: ${vm_name}"
    fi
    
    if ! is_vm_running "$vm_name"; then
        die "VM is not running: ${vm_name}"
    fi
    
    ensure_test_directories
    
    # Set default output directory
    [[ -n "$output_dir" ]] || output_dir="${TEST_RESULTS_DIR}/${vm_name}_$(date +%Y%m%d-%H%M%S)"
    ensure_dir "$output_dir"
    
    log "Test type: ${test_type:-unit}"
    log "Output directory: ${output_dir}"
    
    if [[ -z "$test_script" ]]; then
        # Use default test script
        test_script="${TESTS_DIR}/default_tests.sh"
        if [[ ! -f "$test_script" ]]; then
            warn "No test script specified and default not found"
            return 1
        fi
    fi
    
    # Check if test script exists locally
    if [[ -f "$test_script" ]]; then
        # Copy test script to VM
        log "Copying test script to VM..."
        if ! deploy_file_to_vm "$vm_name" "$test_script" "/tmp/test_script.sh"; then
            warn "Failed to copy test script to VM"
            return 1
        fi
        
        # Run the test script in the VM
        log "Running test script in VM..."
        local test_cmd="chmod +x /tmp/test_script.sh && /tmp/test_script.sh"
        
        if execute_in_vm "$vm_name" "$test_cmd"; then
            log "✅ Tests completed successfully"
        else
            warn "❌ Tests failed"
            return 1
        fi
    else
        # Try to run command directly in VM
        log "Running test command directly in VM..."
        if execute_in_vm "$vm_name" "$test_script"; then
            log "✅ Test command completed successfully"
        else
            warn "❌ Test command failed"
            return 1
        fi
    fi
    
    # Collect test results
    if [[ -d "$output_dir" ]]; then
        log "Collecting test results..."
        collect_test_results "$vm_name" "$output_dir"
    fi
    
    return 0
}

# Execute command in VM
execute_in_vm() {
    local vm_name="$1"
    local command="$2"
    local timeout="$3"
    
    # Get VM IP address
    local vm_ip
    if get_vm_ip "$vm_name"; then
        vm_ip=$(get_vm_ip "$vm_name")
    else
        # Try to get from config
        local config_file="$(find_vm_config_file "$vm_name")"
        if [[ -f "$config_file" ]]; then
            vm_ip=$(grep -E "^IP_ADDRESS|^GUEST_IP" "$config_file" | head -1 | cut -d'=' -f2)
        fi
    fi
    
    if [[ -z "$vm_ip" ]]; then
        die "Could not determine VM IP address for: ${vm_name}"
    fi
    
    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 "${vm_ip}" "echo SSH_OK" &>/dev/null; then
        warn "SSH connection to VM failed: ${vm_ip}"
        return 1
    fi
    
    # Execute command with timeout
    [[ -n "$timeout" ]] || timeout=300  # 5 minutes default
    
    log "Executing in VM ${vm_name} [${vm_ip}]: ${command}"
    
    if timeout "$timeout" ssh "${vm_ip}" "$command"; then
        return 0
    else
        warn "Command timed out after ${timeout} seconds"
        return 1
    fi
}

# Deploy file to VM
deploy_file_to_vm() {
    local vm_name="$1"
    local source_file="$2"
    local dest_path="$3"
    
    # Validate file exists
    if [[ ! -f "$source_file" ]]; then
        die "Source file not found: ${source_file}"
    fi
    
    # Get VM IP
    local vm_ip
    if get_vm_ip "$vm_name"; then
        vm_ip=$(get_vm_ip "$vm_name")
    else
        local config_file="$(find_vm_config_file "$vm_name")"
        if [[ -f "$config_file" ]]; then
            vm_ip=$(grep -E "^IP_ADDRESS|^GUEST_IP" "$config_file" | head -1 | cut -d'=' -f2)
        fi
    fi
    
    if [[ -z "$vm_ip" ]]; then
        die "Could not determine VM IP address for: ${vm_name}"
    fi
    
    # Use scp to copy file
    log "Copying ${source_file} to VM ${vm_name}:${dest_path}"
    
    if scp -q "$source_file" "${vm_ip}:${dest_path}"; then
        log "✅ File copied successfully"
        return 0
    else
        warn "Failed to copy file to VM"
        return 1
    fi
}

# Collect test results from VM
collect_test_results() {
    local vm_name="$1"
    local output_dir="$2"
    
    heading "Collecting Test Results from VM: ${vm_name}"
    
    ensure_dir "$output_dir"
    
    # Get VM IP
    local vm_ip
    if get_vm_ip "$vm_name"; then
        vm_ip=$(get_vm_ip "$vm_name")
    else
        local config_file="$(find_vm_config_file "$vm_name")"
        if [[ -f "$config_file" ]]; then
            vm_ip=$(grep -E "^IP_ADDRESS|^GUEST_IP" "$config_file" | head -1 | cut -d'=' -f2)
        fi
    fi
    
    if [[ -z "$vm_ip" ]]; then
        warn "Could not determine VM IP address for: ${vm_name}"
        return 1
    fi
    
    # Copy test results from common locations
    local result_files=(
        "/tmp/test_results_*.xml"
        "/tmp/test_results_*.json"
        "/tmp/test_output_*.txt"
        "/tmp/test_log_*.log"
    )
    
    local files_copied=0
    
    for pattern in "${result_files[@]}"; do
        local files
        if ssh "$vm_ip" "ls $pattern 2>/dev/null"; then
            files=$(ssh "$vm_ip" "ls $pattern 2>/dev/null")
            for file in $files; do
                local filename=$(basename "$file")
                if scp -q "${vm_ip}:${file}" "${output_dir}/" 2>/dev/null; then
                    log "✓ Collected: ${filename}"
                    files_copied=$((files_copied + 1))
                else
                    warn "✗ Failed to collect: ${filename}"
                fi
            done
        fi
    done
    
    if [[ $files_copied -eq 0 ]]; then
        log "No test result files found in common locations"
    else
        log "✅ Collected ${files_copied} test result files"
        log "Test results saved to: ${output_dir}"
    fi
    
    return 0
}

# Create test configuration
create_test_config() {
    local test_name="$1"
    local vm_name="$2"
    local test_type="$3"
    local config_file="${TESTS_DIR}/${test_name}.testcfg"
    
    heading "Creating Test Configuration: ${test_name}"
    
    ensure_test_directories
    
    if [[ -f "$config_file" ]]; then
        die "Test configuration already exists: ${config_file}"
    fi
    
    # Create test configuration file
    cat > "$config_file" << EOF
# Test Configuration: ${test_name}
TEST_NAME=${test_name}
VM_TARGET=${vm_name:-}
TEST_TYPE=${test_type:-unit}
COMMAND=
ARGS=
TIMEOUT=300
RETRY_ON_FAIL=3
OUTPUT_DIR=

# Environment variables for test
ENV_VARS=

# Dependencies
DEPENDENCIES=
EOF
    
    log "✅ Test configuration created: ${config_file}"
    log "Edit the configuration file to customize test settings"
    return 0
}

# List test configurations
list_test_configs() {
    ensure_test_directories
    
    heading "Test Configurations"
    
    if [[ -d "$TESTS_DIR" ]]; then
        local configs=()
        local config
        
        for config_file in "${TESTS_DIR}"/*.testcfg; do
            if [[ -f "$config_file" ]]; then
                local test_name=$(grep -E "^TEST_NAME=" "$config_file" | cut -d'=' -f2)
                local vm_target=$(grep -E "^VM_TARGET=" "$config_file" | cut -d'=' -f2)
                local test_type=$(grep -E "^TEST_TYPE=" "$config_file" | cut -d'=' -f2)
                
                echo "  ✓ $(basename "$config_file" .testcfg) [${test_type:-unknown}] -> VM: ${vm_target:-any}"
                configs+=("$(basename "$config_file")")
            fi
        done
        
        if [[ ${#configs[@]} -gt 0 ]]; then
            local count=${#configs[@]}
            log "Found ${count} test configurations"
        else
            log "No test configurations found in ${TESTS_DIR}"
        fi
    else
        log "Test directory not found: ${TESTS_DIR}"
    fi
}

# Run test configuration
run_test_config() {
    local config_file="$1"
    local vm_name="$2"
    
    heading "Running Test Configuration: $(basename "$config_file")"
    
    if [[ ! -f "$config_file" ]]; then
        die "Test configuration not found: ${config_file}"
    fi
    
    # Load configuration
    source "$config_file"
    
    local test_name=${TEST_NAME:-"unknown"}
    local target_vm=${VM_TARGET:-$vm_name}
    local test_type=${TEST_TYPE:-"unit"}
    local command=${COMMAND:-}
    local timeout=${TIMEOUT:-300}
    local retry_on_fail=${RETRY_ON_FAIL:-1}
    local output_dir=${OUTPUT_DIR:-${TEST_RESULTS_DIR}/${test_name}_$(date +%Y%m%d-%H%M%S)}
    
    if [[ -z "$target_vm" && -z "$vm_name" ]]; then
        die "No target VM specified in config or as parameter"
    fi
    
    [[ -n "$vm_name" ]] && target_vm="$vm_name"
    
    if [[ -z "$command" ]]; then
        die "No test command specified in configuration"
    fi
    
    log "Test: ${test_name}"
    log "Target VM: ${target_vm}"
    log "Test type: ${test_type}"
    log "Command: ${command}"
    log "Timeout: ${timeout}s"
    
    # Run the test with retries
    local attempt=1
    local success=0
    
    while [[ $attempt -le $retry_on_fail ]]; do
        log "Test attempt ${attempt}/${retry_on_fail}"
        
        if run_vm_tests "$target_vm" "$command" "$test_type" "$output_dir"; then
            success=1
            break
        fi
        
        attempt=$((attempt + 1))
        log "Retrying in 5 seconds..."
        sleep 5
    done
    
    if [[ $success -eq 1 ]]; then
        log "✅ Test configuration executed successfully"
    else
        warn "❌ Test configuration failed after ${retry_on_fail} attempts"
        return 1
    fi
    
    return 0
}

# Create test configuration interactive
create_test_config_interactive() {
    if ! is_interactive; then
        warn "create_test_config_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Create Test Configuration"
    
    local test_name=$(ask "Test configuration name" "")
    if [[ -z "$test_name" ]]; then
        warn "Test name is required"
        return 1
    fi
    
    # List VMs
    list_vms
    
    local vm_name=$(ask "Target VM name (leave empty for any)" "")
    local test_type=$(ask "Test type (unit, integration, performance, regression)" "unit")
    
    create_test_config "$test_name" "$vm_name" "$test_type"
    
    # Offer to edit the configuration
    local config_file="${TESTS_DIR}/${test_name}.testcfg"
    if [[ -f "$config_file" ]]; then
        ask "Edit test configuration now?" "no" | grep -iq "y" && {
            ${EDITOR:-nano} "$config_file"
        }
    fi
}

# Run test configuration interactive
run_test_config_interactive() {
    if ! is_interactive; then
        warn "run_test_config_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Run Test Configuration"
    
    # List test configurations
    list_test_configs
    
    local config_file=$(ask "Select test configuration file" "")
    if [[ -z "$config_file" ]]; then
        warn "Test configuration file is required"
        return 1
    fi
    
    # If it's just a name, add the directory
    if [[ "$config_file" != /* && "$config_file" != ${TESTS_DIR}/* ]]; then
        config_file="${TESTS_DIR}/${config_file}"
    fi
    
    # List VMs
    list_vms
    
    local vm_name=$(ask "Target VM name (leave empty to use config default)" "")
    
    run_test_config "$config_file" "$vm_name"
}

# ---------------------------------------------------------------------------
# XDialog Management UI
# ---------------------------------------------------------------------------

# GUI VM creation using XDialog
gui_create_vm() {
    if ! is_interactive; then
        warn "gui_create_vm function requires interactive mode"
        return 1
    fi
    
    if ! is_gui_mode; then
        create_vm
        return 0
    fi
    
    heading "Create VM [GUI Mode]"
    
    # Select VM name
    local vm_name
    vm_name=$(gui_inputbox "Create VM" "Enter VM name:" "my-vm")
    if [[ -z "$vm_name" ]]; then
        warn "VM name is required"
        return 1
    fi
    
    # Select platform
    local platform
    platform=$(gui_inputbox "Platform Selection" "Select platform (macos-68k, macos-ppc, macos-ppc64, linux, haiku, etc.):" "macos-ppc")
    
    # Select architecture
    local arch
    arch=$(gui_inputbox "Architecture" "Select architecture (ppc, ppc64, x86_64, m68k, etc.):" "ppc")
    
    # Select RAM size
    local ram
    ram=$(gui_inputbox "RAM Size" "RAM size in MB (default: 256):" "256")
    
    # Select disk size
    local disk_size
    disk_size=$(gui_inputbox "Disk Size" "Disk size in GB (default: 10):" "10")
    
    # Select display type
    local display_options=("cocoa" "sdl" "gtk" "spice" "vnc" "none")
    local display
    if command -v xdialog &>/dev/null; then
        display=$(gui_inputbox "Display Backend" "Select display backend:" "${display_options[0]}")
    else
        display=$(ask "Display backend" "${display_options[0]}")
    fi
    
    # Create VM with selected parameters
    log "Creating VM with the following parameters:"
    log "  Name: ${vm_name}"
    log "  Platform: ${platform}"
    log "  Architecture: ${arch}"
    log "  RAM: ${ram}MB"
    log "  Disk: ${disk_size}GB"
    log "  Display: ${display}"
    
    # Call create_vm with parameters
    create_vm "$vm_name" "$platform" "$arch" "$ram" "$disk_size" "$display"
}

# GUI VM management menu
gui_manage_vms() {
    if ! is_interactive; then
        warn "gui_manage_vms function requires interactive mode"
        return 1
    fi
    
    if ! is_gui_mode; then
        launch_vm_menu
        return 0
    fi
    
    heading "Manage VMs [GUI Mode]"
    
    while true; do
        local options=(
            "List VMs" "list_vms"
            "Create VM" "gui_create_vm"
            "Launch VM" "launch_vm_menu"
            "Stop VM" "stop_vm_menu"
            "Edit VM" "edit_vm_menu"
            "Delete VM" "delete_vm_menu"
            "Back" "return"
        )
        
        local choice
        if is_gui_mode; then
            # This would need a proper GUI menu implementation
            choice=$(gui_inputbox "VM Management" "Select action:" "List VMs")
        else
            list_vms
            choice=$(ask "Select action" "")
        fi
        
        case "$choice" in
            "List VMs") list_vms ;;
            "Create VM") gui_create_vm ;;
            "Launch VM") launch_vm_menu ;;
            "Stop VM") stop_vm_menu ;;
            "Edit VM") edit_vm_menu ;;
            "Delete VM") delete_vm_menu ;;
            "Back"|"return") return 0 ;;
            *) log "Invalid option: $choice" ;;
        esac
    done
}

# GUI debug session launcher
gui_debug_vm() {
    if ! is_interactive; then
        warn "gui_debug_vm function requires interactive mode"
        return 1
    fi
    
    if ! is_gui_mode; then
        debug_session_menu
        return 0
    fi
    
    heading "Debug VM [GUI Mode]"
    
    # List VMs
    list_vms
    
    local vm_name
    vm_name=$(gui_inputbox "Select VM" "Enter VM name to debug:" "")
    if [[ -z "$vm_name" ]]; then
        warn "VM name is required"
        return 1
    fi
    
    # Select debug options
    local enable_gdb
    enable_gdb=$(gui_yesno "Debug Options" "Enable GDB debugging?" "yes")
    
    local enable_ssh
    enable_ssh=$(gui_yesno "SSH Options" "Enable SSH forwarding?" "yes")
    
    local enable_netatalk
    enable_netatalk=$(gui_yesno "File Sharing" "Enable Netatalk (AFP) sharing?" "no")
    
    # Start debug session
    if $enable_gdb; then
        debug_start "$vm_name" "" "gdb"
    else
        debug_start "$vm_name"
    fi
}

# XDialog-based main menu
gui_main_menu() {
    if ! is_interactive; then
        warn "gui_main_menu function requires interactive mode"
        return 1
    fi
    
    if ! is_gui_mode; then
        show_main_menu
        return 0
    fi
    
    heading "Main Menu [GUI Mode]"
    
    while true; do
        # In GUI mode, we would show a graphical menu
        # For now, we'll use the CLI menu but with GUI enhancements
        
        # Show a simplified menu for GUI mode
        local options=(
            "VM Management" "gui_manage_vms"
            "Build Automation" "build_project_menu"
            "Debugging" "gui_debug_vm"
            "Testing" "run_test_config_interactive"
            "GUI Applications" "launch_gui_application_interactive"
            "Quit" "return"
        )
        
        local choice
        if is_gui_mode; then
            choice=$(gui_inputbox "Main Menu" "Select category:" "VM Management")
        else
            choice=$(ask "Select category" "VM Management")
        fi
        
        case "$choice" in
            "VM Management") gui_manage_vms ;;
            "Build Automation") build_project_menu ;;
            "Debugging") gui_debug_vm ;;
            "Testing") run_test_config_interactive ;;
            "GUI Applications") launch_gui_application_interactive ;;
            "Quit"|"return") return 0 ;;
            *) log "Invalid option: $choice" ;;
        esac
    done
}

# Start XDialog-based UI
gui_mode_start() {
    heading "Starting GUI Mode"
    
    if ! detect_xdialog; then
        warn "XDialog not available, falling back to CLI mode"
        show_main_menu
        return 0
    fi
    
    enable_xdialog
    
    if is_gui_mode; then
        log "GUI mode enabled"
        gui_main_menu
    else
        warn "Failed to enable GUI mode"
        show_main_menu
    fi
}

# ---------------------------------------------------------------------------
# Enhanced Deployment Features
# ---------------------------------------------------------------------------

# Deployment directory structure
DEPLOY_DIR="${CONFIG_DIR}/deployments"
DEPLOY_LOG_DIR="${VM_LOG_DIR}/deployments"
DEPLOY_BACKUP_DIR="${CONFIG_DIR}/deployments/backups"

# Ensure deployment directories exist
ensure_deploy_dirs() {
    ensure_dir "$DEPLOY_DIR"
    ensure_dir "$DEPLOY_LOG_DIR"
    ensure_dir "$DEPLOY_BACKUP_DIR"
}

# Incremental deployment - only deploy changed files
incremental_deploy() {
    local vm_name="$1"
    local source_dir="$2"
    local target_dir="$3"
    local backup_first="$4"
    local exclude_patterns="$5"
    
    heading "Incremental Deployment to VM: ${vm_name}"
    
    # Validate VM exists
    if ! find_vm_config "$vm_name"; then
        die "VM not found: ${vm_name}"
    fi
    
    # Validate source directory
    if [[ -z "$source_dir" ]]; then
        source_dir="$PROJECTS_DIR"
    fi
    
    if [[ ! -d "$source_dir" ]]; then
        die "Source directory not found: ${source_dir}"
    fi
    
    # Set default target directory
    [[ -n "$target_dir" ]] || target_dir="/opt/deploy"
    
    log "Source directory: ${source_dir}"
    log "Target directory: ${target_dir}"
    log "Backup first: ${backup_first:-no}"
    
    ensure_deploy_dirs
    
    # Get VM IP
    local vm_ip
    if get_vm_ip "$vm_name"; then
        vm_ip=$(get_vm_ip "$vm_name")
    else
        local config_file="$(find_vm_config_file "$vm_name")"
        if [[ -f "$config_file" ]]; then
            vm_ip=$(grep -E "^IP_ADDRESS|^GUEST_IP" "$config_file" | head -1 | cut -d'=' -f2)
        fi
    fi
    
    if [[ -z "$vm_ip" ]]; then
        die "Could not determine VM IP address for: ${vm_name}"
    fi
    
    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 "${vm_ip}" "echo SSH_OK" &>/dev/null; then
        die "SSH connection to VM failed: ${vm_ip}"
    fi
    
    # Backup existing files if requested
    if is_yes "$backup_first"; then
        local backup_dir="${DEPLOY_BACKUP_DIR}/${vm_name}/$(date +%Y%m%d-%H%M%S)"
        ensure_dir "$backup_dir"
        
        log "Backing up existing files..."
        if ssh "${vm_ip}" "mkdir -p ${backup_dir}" 2>/dev/null; then
            # Copy existing files to backup
            if ssh "${vm_ip}" "find ${target_dir} -type f -exec cp {} ${backup_dir} \;" 2>/dev/null; then
                log "✅ Backup created: ${backup_dir}"
            else
                warn "⚠️  Backup created with some files skipped"
            fi
        else
            warn "⚠️  Could not create backup directory on VM"
        fi
    fi
    
    # Find changed files using rsync dry-run or find with newer timestamp
    local changed_files=()
    local temp_file=$(mktemp)
    
    log "Finding changed files..."
    
    # Use rsync to find changed files if available
    if command -v rsync &>/dev/null; then
        # Get list of files that would be transferred
        rsync -avn --exclude="${exclude_patterns:-*.log *.tmp}" "${source_dir}/" "${vm_ip}:${target_dir}/" | \
            grep -E "^>f\+|^>\+|^<f\+|^<\+" | awk '{print $2}' > "$temp_file"
    else
        # Fallback to find command - deploy all files
        find "$source_dir" -type f | grep -v "${exclude_patterns:-\.git|\.svn|\.tmp|\.log}" > "$temp_file"
    fi
    
    local file_count=0
    local deployed_count=0
    
    # Create target directory on VM
    if ! ssh "${vm_ip}" "mkdir -p ${target_dir}" 2>/dev/null; then
        die "Failed to create target directory on VM: ${target_dir}"
    fi
    
    # Deploy changed files
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            local relative_path="${file#${source_dir}/}"
            local target_path="${target_dir}/${relative_path}"
            local target_parent_dir=$(dirname "$target_path")
            
            # Create parent directory on VM
            ssh "${vm_ip}" "mkdir -p ${target_parent_dir}" 2>/dev/null
            
            # Copy file
            if scp -q "$file" "${vm_ip}:${target_path}"; then
                log "✓ Deployed: ${relative_path}"
                deployed_count=$((deployed_count + 1))
            else
                warn "✗ Failed to deploy: ${relative_path}"
            fi
            
            file_count=$((file_count + 1))
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    if [[ $deployed_count -gt 0 ]]; then
        log "✅ Incremental deployment completed: ${deployed_count}/${file_count} files deployed"
    else
        log "📭 No files needed deployment"
    fi
    
    # Set permissions if needed
    if [[ $deployed_count -gt 0 ]]; then
        log "Setting permissions on deployed files..."
        ssh "${vm_ip}" "find ${target_dir} -type f -exec chmod +x {} \;" 2>/dev/null
        ssh "${vm_ip}" "find ${target_dir} -type d -exec chmod +x {} \;" 2>/dev/null
    fi
    
    return 0
}

# Environment validation before deployment
validate_environment() {
    local vm_name="$1"
    local requirements_file="$2"
    
    heading "Validating Environment: ${vm_name}"
    
    # Validate VM exists and is running
    if ! find_vm_config "$vm_name"; then
        die "VM not found: ${vm_name}"
    fi
    
    if ! is_vm_running "$vm_name"; then
        die "VM is not running: ${vm_name}"
    fi
    
    # Get VM IP
    local vm_ip
    if get_vm_ip "$vm_name"; then
        vm_ip=$(get_vm_ip "$vm_name")
    else
        local config_file="$(find_vm_config_file "$vm_name")"
        if [[ -f "$config_file" ]]; then
            vm_ip=$(grep -E "^IP_ADDRESS|^GUEST_IP" "$config_file" | head -1 | cut -d'=' -f2)
        fi
    fi
    
    if [[ -z "$vm_ip" ]]; then
        die "Could not determine VM IP address for: ${vm_name}"
    fi
    
    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 "${vm_ip}" "echo SSH_OK" &>/dev/null; then
        die "❌ SSH connection failed: ${vm_ip}"
        return 1
    fi
    
    log "✅ SSH connectivity: OK"
    
    # Check for required commands
    local required_commands=("ls" "mkdir" "chmod" "cp" "find")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! ssh "${vm_ip}" "command -v $cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        warn "❌ Missing commands on VM: ${missing_commands[*]}"
        return 1
    fi
    
    log "✅ Required commands: OK"
    
    # Check for custom requirements file
    if [[ -n "$requirements_file" && -f "$requirements_file" ]]; then
        log "Checking custom requirements..."
        
        while IFS= read -r requirement; do
            # Skip empty lines and comments
            [[ -z "$requirement" || "$requirement" == \#* ]] && continue
            
            if ! ssh "${vm_ip}" "$requirement" &>/dev/null; then
                warn "❌ Requirement failed: $requirement"
                return 1
            fi
            
            log "✅ Requirement passed: $requirement"
        done < "$requirements_file"
        
        log "✅ Custom requirements: OK"
    fi
    
    # Check disk space
    local disk_info
    disk_info=$(ssh "${vm_ip}" "df -h / | tail -1" 2>/dev/null)
    if [[ -n "$disk_info" ]]; then
        log "✅ Disk space: $disk_info"
    else
        warn "⚠️  Could not check disk space"
    fi
    
    # Check memory
    local memory_info
    memory_info=$(ssh "${vm_ip}" "free -h" 2>/dev/null)
    if [[ -n "$memory_info" ]]; then
        log "✅ Memory: $(echo "$memory_info" | head -1)"
    else
        warn "⚠️  Could not check memory"
    fi
    
    log "✅ Environment validation passed for VM: ${vm_name}"
    return 0
}

# Deployment rollback capability
rollback_deployment() {
    local vm_name="$1"
    local backup_id="$2"
    local target_dir="$3"
    
    heading "Rolling Back Deployment: ${vm_name}"
    
    # Validate VM exists
    if ! find_vm_config "$vm_name"; then
        die "VM not found: ${vm_name}"
    fi
    
    # Find available backups
    if [[ -z "$backup_id" ]]; then
        log "Available backups:"
        local backups=()
        
        if [[ -d "$DEPLOY_BACKUP_DIR/$vm_name" ]]; then
            local backup_dirs=()
            while IFS= read -r backup_dir; do
                [[ -d "$backup_dir" ]] && backup_dirs+=("$backup_dir")
            done < <(find "$DEPLOY_BACKUP_DIR/$vm_name" -type d -maxdepth 1 | sort -r)
            
            for i in "${!backup_dirs[@]}"; do
                local dir_name=$(basename "${backup_dirs[$i]}")
                local dir_size=$(du -sh "${backup_dirs[$i]}" 2>/dev/null | cut -f1)
                echo "  [$i] ${dir_name} [${dir_size}]"
                backups+=("$dir_name")
            done
            
            if [[ ${#backups[@]} -eq 0 ]]; then
                die "No backups found for VM: ${vm_name}"
            fi
        else
            die "No backup directory found for VM: ${vm_name}"
        fi
        
        # Let user select backup
        local choice
        choice=$(ask "Select backup to restore" "0")
        backup_id="${backups[$choice]:-${backups[0]}}"
    fi
    
    # Set default target directory
    [[ -n "$target_dir" ]] || target_dir="/opt/deploy"
    
    log "Restoring backup: ${backup_id}"
    log "Target directory: ${target_dir}"
    
    # Get VM IP
    local vm_ip
    if get_vm_ip "$vm_name"; then
        vm_ip=$(get_vm_ip "$vm_name")
    else
        local config_file="$(find_vm_config_file "$vm_name")"
        if [[ -f "$config_file" ]]; then
            vm_ip=$(grep -E "^IP_ADDRESS|^GUEST_IP" "$config_file" | head -1 | cut -d'=' -f2)
        fi
    fi
    
    if [[ -z "$vm_ip" ]]; then
        die "Could not determine VM IP address for: ${vm_name}"
    fi
    
    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 "${vm_ip}" "echo SSH_OK" &>/dev/null; then
        die "SSH connection to VM failed: ${vm_ip}"
    fi
    
    local backup_source="${DEPLOY_BACKUP_DIR}/${vm_name}/${backup_id}"
    
    if [[ ! -d "$backup_source" ]]; then
        die "Backup not found: ${backup_source}"
    fi
    
    log "Rolling back from: ${backup_source}"
    
    # Remove current files
    log "Removing current deployment..."
    if ! ssh "${vm_ip}" "rm -rf ${target_dir}/*" 2>/dev/null; then
        warn "⚠️  Could not remove all files from target directory"
    fi
    
    # Create target directory
    if ! ssh "${vm_ip}" "mkdir -p ${target_dir}" 2>/dev/null; then
        die "Failed to create target directory: ${target_dir}"
    fi
    
    # Restore from backup
    log "Restoring files from backup..."
    local deployed_count=0
    local file_count=0
    
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            local relative_path="${file#${backup_source}/}"
            local target_path="${target_dir}/${relative_path}"
            local target_parent_dir=$(dirname "$target_path")
            
            # Create parent directory on VM
            ssh "${vm_ip}" "mkdir -p ${target_parent_dir}" 2>/dev/null
            
            # Copy file
            if scp -q "$file" "${vm_ip}:${target_path}"; then
                log "✓ Restored: ${relative_path}"
                deployed_count=$((deployed_count + 1))
            else
                warn "✗ Failed to restore: ${relative_path}"
            fi
            
            file_count=$((file_count + 1))
        fi
    done < <(find "$backup_source" -type f)
    
    # Set permissions
    log "Setting permissions on restored files..."
    ssh "${vm_ip}" "find ${target_dir} -type f -exec chmod +x {} \;" 2>/dev/null
    ssh "${vm_ip}" "find ${target_dir} -type d -exec chmod +x {} \;" 2>/dev/null
    
    log "✅ Rollback completed: ${deployed_count} files restored"
    
    return 0
}

# List deployment history
list_deployment_history() {
    local vm_name="$1"
    
    heading "Deployment History for VM: ${vm_name}"
    
    ensure_deploy_dirs
    
    local history_file="${DEPLOY_DIR}/${vm_name}.deployments"
    
    if [[ ! -f "$history_file" ]]; then
        log "No deployment history found for VM: ${vm_name}"
        return 0
    fi
    
    # Show deployment history
    local line_num=1
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            echo "  [${line_num}] ${line}"
            line_num=$((line_num + 1))
        fi
    done < "$history_file"
    
    return 0
}

# Log deployment to history
log_deployment() {
    local vm_name="$1"
    local message="$2"
    local timestamp="$3"
    
    [[ -n "$timestamp" ]] || timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    ensure_deploy_dirs
    
    local history_file="${DEPLOY_DIR}/${vm_name}.deployments"
    
    echo "[${timestamp}] ${message}" >> "$history_file"
    
    return 0
}

# Deployment validation and cleanup
cleanup_deployment() {
    local vm_name="$1"
    local keep_backups="$2"
    local target_dir="$3"
    
    heading "Cleaning Up Deployments for VM: ${vm_name}"
    
    ensure_deploy_dirs
    
    # Set default values
    [[ -n "$keep_backups" ]] || keep_backups=5
    [[ -n "$target_dir" ]] || target_dir="/opt/deploy"
    
    # Get VM IP if needed
    local vm_ip=""
    if [[ -n "$target_dir" && "$target_dir" != /* ]]; then
        # If target_dir is relative, we need VM IP to construct full path
        if get_vm_ip "$vm_name"; then
            vm_ip=$(get_vm_ip "$vm_name")
        else
            local config_file="$(find_vm_config_file "$vm_name")"
            if [[ -f "$config_file" ]]; then
                vm_ip=$(grep -E "^IP_ADDRESS|^GUEST_IP" "$config_file" | head -1 | cut -d'=' -f2)
            fi
        fi
    fi
    
    # Clean up old backups
    if [[ -d "$DEPLOY_BACKUP_DIR/$vm_name" ]]; then
        log "Cleaning up old backups..."
        
        # Find all backup directories sorted by modification time (oldest first)
        local backup_dirs=()
        while IFS= read -r backup_dir; do
            [[ -d "$backup_dir" ]] && backup_dirs+=("$backup_dir")
        done < <(find "$DEPLOY_BACKUP_DIR/$vm_name" -type d -maxdepth 1 -printf '%T+ %p\n' | sort | cut -d' ' -f2-)
        
        # Remove old backups if we have more than keep_backups
        local backup_count=${#backup_dirs[@]}
        if [[ $backup_count -gt $keep_backups ]]; then
            local remove_count=$((backup_count - keep_backups))
            for ((i=0; i<remove_count; i++)); do
                local old_backup="${backup_dirs[$i]}"
                log "Removing old backup: $(basename "$old_backup")"
                rm -rf "$old_backup"
            done
            log "✅ Removed ${remove_count} old backups"
        fi
    fi
    
    # Clean up target directory on VM if specified
    if [[ -n "$vm_ip" && -n "$target_dir" ]]; then
        log "Cleaning up target directory on VM..."
        
        # Find temporary files
        local temp_files=()
        temp_files=$(ssh "${vm_ip}" "find ${target_dir} -name '*.tmp' -o -name '*.temp' -o -name '*.bak' -o -name '*.swp' 2>/dev/null" || true)
        
        if [[ -n "$temp_files" ]]; then
            log "Removing temporary files..."
            ssh "${vm_ip}" "find ${target_dir} \( -name '*.tmp' -o -name '*.temp' -o -name '*.bak' -o -name '*.swp' \) -delete" 2>/dev/null
            log "✅ Temporary files cleaned"
        fi
        
        # Find old log files (> 7 days)
        ssh "${vm_ip}" "find ${target_dir} -name '*.log' -mtime +7 -delete" 2>/dev/null
    fi
    
    log "✅ Deployment cleanup completed"
    return 0
}

# ---------------------------------------------------------------------------
# Development Project Management - Project Snapshots
# ---------------------------------------------------------------------------

# Directory for project snapshots
PROJECT_SNAPSHOT_DIR="${PROJECTS_DIR}/snapshots"

# Ensure project snapshot directory exists
ensure_project_snapshot_dirs() {
    ensure_dir "${PROJECTS_DIR}"
    ensure_dir "${PROJECT_SNAPSHOT_DIR}"
}

# Create a project snapshot
# Usage: create_project_snapshot <project_name> [snapshot_name] [description]
create_project_snapshot() {
    local project_name="$1"
    local snapshot_name="$2"
    local description="$3"
    
    heading "Creating Project Snapshot: ${project_name}"
    
    ensure_project_snapshot_dirs
    
    # Validate project exists
    local project_dir="${PROJECTS_DIR}/${project_name}"
    if [[ ! -d "$project_dir" ]]; then
        die "Project not found: ${project_name}. Use list-projects to see available projects."
    fi
    
    # Set default snapshot name if not provided
    [[ -n "$snapshot_name" ]] || snapshot_name="${project_name}-$(date +%Y%m%d-%H%M%S)"
    
    # Set default description if not provided
    [[ -n "$description" ]] || description="Automatic snapshot created on $(date)"
    
    local snapshot_dir="${PROJECT_SNAPSHOT_DIR}/${project_name}/${snapshot_name}"
    
    # Create snapshot directory
    log "Creating snapshot directory: ${snapshot_dir}"
    mkdir -p "${snapshot_dir}"
    
    # Create metadata file
    local metadata_file="${snapshot_dir}/snapshot.meta"
    cat > "${metadata_file}" << EOF
# Project Snapshot Metadata
PROJECT_NAME="${project_name}"
SNAPSHOT_NAME="${snapshot_name}"
CREATED_AT="$(date +%Y-%m-%d\ %H:%M:%S)"
DESCRIPTION="${description}"
SOURCE_DIR="${project_dir}"
EOF
    
    # Create archive of project
    local archive_file="${snapshot_dir}/project.tar.gz"
    log "Archiving project to: ${archive_file}"
    
    if ! tar -czf "${archive_file}" -C "${PROJECTS_DIR}" "${project_name}" 2>/dev/null; then
        die "Failed to create project archive"
    fi
    
    # Save project configuration if it exists
    local config_file="${project_dir}/project.conf"
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "${snapshot_dir}/project.conf.bak"
    fi
    
    # Save VM associations if any
    local vm_configs=("${VM_DIR}"/*.conf)
    for vm_config in "${vm_configs[@]}"; do
        if [[ -f "$vm_config" ]]; then
            local vm_name=$(basename "$vm_config" .conf)
            if grep -q "${project_name}" "$vm_config" 2>/dev/null; then
                cp "$vm_config" "${snapshot_dir}/vm_${vm_name}.conf"
            fi
        fi
    done
    
    log "✅ Project snapshot created: ${snapshot_name}"
    log "   Location: ${snapshot_dir}"
    log "   Archive: ${archive_file}"
    
    return 0
}

# Restore a project snapshot
# Usage: restore_project_snapshot <project_name> <snapshot_name> [restore_to]
restore_project_snapshot() {
    local project_name="$1"
    local snapshot_name="$2"
    local restore_to="$3"
    
    heading "Restoring Project Snapshot: ${project_name} from ${snapshot_name}"
    
    ensure_project_snapshot_dirs
    
    local snapshot_dir="${PROJECT_SNAPSHOT_DIR}/${project_name}/${snapshot_name}"
    
    if [[ ! -d "$snapshot_dir" ]]; then
        die "Snapshot not found: ${snapshot_dir}"
    fi
    
    # Read metadata
    local metadata_file="${snapshot_dir}/snapshot.meta"
    if [[ ! -f "$metadata_file" ]]; then
        die "Invalid snapshot: missing metadata file"
    fi
    
    # Set restore target
    [[ -n "$restore_to" ]] || restore_to="${project_name}"
    local restore_dir="${PROJECTS_DIR}/${restore_to}"
    
    # Check if target already exists
    if [[ -d "$restore_dir" ]]; then
        local backup_name="${restore_to}-backup-$(date +%Y%m%d-%H%M%S)"
        log "Target project already exists. Backing up to: ${backup_name}"
        mv "${restore_dir}" "${PROJECTS_DIR}/${backup_name}"
    fi
    
    # Extract archive
    local archive_file="${snapshot_dir}/project.tar.gz"
    if [[ ! -f "$archive_file" ]]; then
        die "Archive file not found: ${archive_file}"
    fi
    
    log "Extracting project archive..."
    if ! tar -xzf "$archive_file" -C "${PROJECTS_DIR}" 2>/dev/null; then
        die "Failed to extract project archive"
    fi
    
    # Restore configuration if backup exists
    local config_backup="${snapshot_dir}/project.conf.bak"
    if [[ -f "$config_backup" ]]; then
        cp "$config_backup" "${restore_dir}/project.conf"
    fi
    
    # Restore VM configurations if they exist
    for vm_config in "${snapshot_dir}"/vm_*.conf; do
        if [[ -f "$vm_config" ]]; then
            local vm_name=$(basename "$vm_config" | sed 's/^vm_//;s/.conf$//')
            cp "$vm_config" "${VM_DIR}/${vm_name}.conf"
        fi
    done
    
    log "✅ Project snapshot restored: ${snapshot_name}"
    log "   Restored to: ${restore_dir}"
    
    return 0
}

# List project snapshots
# Usage: list_project_snapshots [project_name]
list_project_snapshots() {
    local project_name="$1"
    
    heading "Project Snapshots"
    
    ensure_project_snapshot_dirs
    
    if [[ -n "$project_name" ]]; then
        # List snapshots for specific project
        local project_snapshot_dir="${PROJECT_SNAPSHOT_DIR}/${project_name}"
        
        if [[ ! -d "$project_snapshot_dir" ]]; then
            log "No snapshots found for project: ${project_name}"
            return 0
        fi
        
        log "Snapshots for project: ${project_name}"
        log "="
        
        local snapshots=()
        while IFS= read -r snapshot_dir; do
            [[ -d "$snapshot_dir" ]] && snapshots+=("$snapshot_dir")
        done < <(find "$project_snapshot_dir" -type d -maxdepth 1 | sort -r)
        
        for i in "${!snapshots[@]}"; do
            local snapshot_name=$(basename "${snapshots[$i]}")
            local metadata_file="${snapshots[$i]}/snapshot.meta"
            
            if [[ -f "$metadata_file" ]]; then
                local created_at=$(grep "^CREATED_AT=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
                local description=$(grep "^DESCRIPTION=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
                local size=$(du -sh "${snapshots[$i]}" 2>/dev/null | cut -f1)
                
                echo "  [${i}] ${snapshot_name} [${size}]"
                echo "      Created: ${created_at}"
                echo "      Description: ${description}"
                echo ""
            fi
        done
    else
        # List snapshots for all projects
        log "All Project Snapshots:"
        log "="
        
        local project_dirs=()
        while IFS= read -r project_dir; do
            [[ -d "$project_dir" ]] && project_dirs+=("$project_dir")
        done < <(find "$PROJECT_SNAPSHOT_DIR" -type d -maxdepth 1 | sort)
        
        for project_dir in "${project_dirs[@]}"; do
            local project_name=$(basename "$project_dir")
            local snapshot_count=$(find "$project_dir" -type d -maxdepth 1 | wc -l | tr -d ' ')
            snapshot_count=$((snapshot_count - 1))  # Subtract the project directory itself
            
            log "📁 ${project_name}: ${snapshot_count} snapshots"
            
            # List latest 3 snapshots for each project
            local snapshots=()
            local snapshot_list
            snapshot_list=$(find "$project_dir" -type d -maxdepth 1 | sort -r | head -4)
            while IFS= read -r snapshot_dir; do
                [[ -n "$snapshot_dir" && -d "$snapshot_dir" ]] && snapshots+=("$snapshot_dir")
            done <<< "$snapshot_list"
            
            # Skip the project directory itself
            for snapshot_dir in "${snapshots[@]:1}"; do
                local snapshot_name
                snapshot_name=$(basename "$snapshot_dir")
                local created_at
                created_at=$(grep "^CREATED_AT=" "${snapshot_dir}/snapshot.meta" 2>/dev/null | cut -d'=' -f2- | tr -d '"')
                echo "    --- ${snapshot_name} [${created_at}]"
            done
            echo ""
        done
    fi
    
    return 0
}

# Delete a project snapshot
# Usage: delete_project_snapshot <project_name> <snapshot_name>
delete_project_snapshot() {
    local project_name="$1"
    local snapshot_name="$2"
    
    heading "Delete Project Snapshot"
    
    ensure_project_snapshot_dirs
    
    local snapshot_dir="${PROJECT_SNAPSHOT_DIR}/${project_name}/${snapshot_name}"
    
    if [[ ! -d "$snapshot_dir" ]]; then
        die "Snapshot not found: ${snapshot_dir}"
    fi
    
    # Confirm deletion
    if ! confirm "Are you sure you want to delete snapshot '${snapshot_name}' for project '${project_name}'?"; then
        log "Deletion cancelled"
        return 0
    fi
    
    log "Deleting snapshot: ${snapshot_dir}"
    rm -rf "${snapshot_dir}"
    
    # Clean up empty project directory
    local project_snapshot_dir="${PROJECT_SNAPSHOT_DIR}/${project_name}"
    if [[ -d "$project_snapshot_dir" && -z "$(ls -A "$project_snapshot_dir")" ]]; then
        rmdir "$project_snapshot_dir"
    fi
    
    log "✅ Snapshot deleted: ${snapshot_name}"
    
    return 0
}

# Interactive project snapshot creation
create_project_snapshot_interactive() {
    if ! is_interactive; then
        warn "create_project_snapshot_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Create Project Snapshot [Interactive]"
    
    list_projects
    echo ""
    
    local project_name
    project_name=$(ask "Enter project name to snapshot" "")
    
    if [[ -z "$project_name" ]]; then
        die "Project name is required"
    fi
    
    local project_dir="${PROJECTS_DIR}/${project_name}"
    if [[ ! -d "$project_dir" ]]; then
        die "Project not found: ${project_name}"
    fi
    
    local snapshot_name
    snapshot_name=$(ask "Enter snapshot name (leave blank for auto-generated)" "")
    
    local description
    description=$(ask "Enter description for this snapshot" "Automatic snapshot")
    
    create_project_snapshot "$project_name" "$snapshot_name" "$description"
}

# Interactive project snapshot restore
restore_project_snapshot_interactive() {
    if ! is_interactive; then
        warn "restore_project_snapshot_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Restore Project Snapshot [Interactive]"
    
    list_projects
    echo ""
    
    local project_name
    project_name=$(ask "Enter project name" "")
    
    if [[ -z "$project_name" ]]; then
        die "Project name is required"
    fi
    
    list_project_snapshots "$project_name"
    echo ""
    
    local snapshot_name
    snapshot_name=$(ask "Enter snapshot name to restore" "")
    
    if [[ -z "$snapshot_name" ]]; then
        die "Snapshot name is required"
    fi
    
    local restore_to
    restore_to=$(ask "Restore to project name (leave blank for original)" "")
    
    restore_project_snapshot "$project_name" "$snapshot_name" "$restore_to"
}

# Interactive project snapshot deletion
delete_project_snapshot_interactive() {
    if ! is_interactive; then
        warn "delete_project_snapshot_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Delete Project Snapshot [Interactive]"
    
    list_projects
    echo ""
    
    local project_name
    project_name=$(ask "Enter project name" "")
    
    if [[ -z "$project_name" ]]; then
        die "Project name is required"
    fi
    
    list_project_snapshots "$project_name"
    echo ""
    
    local snapshot_name
    snapshot_name=$(ask "Enter snapshot name to delete" "")
    
    if [[ -z "$snapshot_name" ]]; then
        die "Snapshot name is required"
    fi
    
    delete_project_snapshot "$project_name" "$snapshot_name"
}

# ---------------------------------------------------------------------------
# Enhanced Debugging Workflows - Debug Session Recording
# ---------------------------------------------------------------------------

# Directory for debug session recordings
DEBUG_SESSION_DIR="${CONFIG_DIR}/debug_sessions"

# Ensure debug session directory exists
ensure_debug_session_dirs() {
    ensure_dir "${DEBUG_SESSION_DIR}"
}

# Start a debug session recording
# Usage: start_debug_recording <session_name> [vm_name] [gdb_port] [description]
start_debug_recording() {
    local session_name="$1"
    local vm_name="$2"
    local gdb_port="$3"
    local description="$4"
    
    heading "Starting Debug Session Recording: ${session_name}"
    
    ensure_debug_session_dirs
    
    # Set default values
    [[ -n "$session_name" ]] || session_name="debug_session_$(date +%Y%m%d-%H%M%S)"
    [[ -n "$gdb_port" ]] || gdb_port="1234"
    [[ -n "$description" ]] || description="Debug session started on $(date)"
    
    local session_dir="${DEBUG_SESSION_DIR}/${session_name}"
    local recording_file="${session_dir}/recording.log"
    local metadata_file="${session_dir}/session.meta"
    local commands_file="${session_dir}/commands.gdb"
    
    # Create session directory
    log "Creating debug session directory: ${session_dir}"
    mkdir -p "${session_dir}"
    
    # Save metadata
    cat > "${metadata_file}" << EOF
# Debug Session Metadata
SESSION_NAME="${session_name}"
VM_NAME="${vm_name:-unknown}"
GDB_PORT="${gdb_port}"
STARTED_AT="$(date +%Y-%m-%d\ %H:%M:%S)"
STATUS="recording"
DESCRIPTION="${description}"
EOF
    
    # Start GDB with logging
    log "Starting GDB recording..."
    log "Session directory: ${session_dir}"
    log "GDB port: ${gdb_port}"
    
    # Create GDB command script
    cat > "${commands_file}" << EOF
set logging file ${recording_file}
set logging enabled on
set logging overwrite off

# Connect to VM
target remote localhost:${gdb_port}

# Enable full debugging output
set debug remote 1
set debug protocol 1

# Continue execution
continue
EOF
    
    log "✅ Debug session recording started: ${session_name}"
    log "   Recording file: ${recording_file}"
    log "   GDB commands: ${commands_file}"
    log ""
    log "To connect GDB manually:"
    log "  gdb-multiarch -x ${commands_file}"
    
    return 0
}

# Stop a debug session recording
# Usage: stop_debug_recording <session_name>
stop_debug_recording() {
    local session_name="$1"
    
    heading "Stopping Debug Session Recording: ${session_name}"
    
    local session_dir="${DEBUG_SESSION_DIR}/${session_name}"
    local metadata_file="${session_dir}/session.meta"
    
    if [[ ! -d "$session_dir" ]]; then
        die "Debug session not found: ${session_name}"
    fi
    
    if [[ ! -f "$metadata_file" ]]; then
        die "Invalid debug session: missing metadata file"
    fi
    
    # Update metadata
    local end_time=$(date +"%Y-%m-%d %H:%M:%S")
    local start_time=$(grep "^STARTED_AT=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
    
    # Calculate duration
    local start_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" +%s 2>/dev/null || echo 0)
    local end_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$end_time" +%s 2>/dev/null || echo 0)
    local duration=$((end_ts - start_ts))
    
    # Update metadata with end time and duration
    sed -i.bak "s/^STATUS=.*/STATUS="stopped"/" "$metadata_file" 2>/dev/null
    echo "ENDED_AT=\"${end_time}\"" >> "$metadata_file"
    echo "DURATION_SECONDS=\"${duration}\"" >> "$metadata_file"
    
    log "✅ Debug session recording stopped: ${session_name}"
    log "   Duration: ${duration} seconds"
    log "   Started: ${start_time}"
    log "   Ended: ${end_time}"
    
    return 0
}

# Replay a debug session recording
# Usage: replay_debug_session <session_name>
replay_debug_session() {
    local session_name="$1"
    
    heading "Replaying Debug Session: ${session_name}"
    
    local session_dir="${DEBUG_SESSION_DIR}/${session_name}"
    local metadata_file="${session_dir}/session.meta"
    local recording_file="${session_dir}/recording.log"
    
    if [[ ! -d "$session_dir" ]]; then
        die "Debug session not found: ${session_name}"
    fi
    
    if [[ ! -f "$recording_file" ]]; then
        die "Recording file not found: ${recording_file}"
    fi
    
    # Display session information
    log "Session: ${session_name}"
    
    if [[ -f "$metadata_file" ]]; then
        local vm_name=$(grep "^VM_NAME=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local gdb_port=$(grep "^GDB_PORT=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local start_time=$(grep "^STARTED_AT=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local end_time=$(grep "^ENDED_AT=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local duration=$(grep "^DURATION_SECONDS=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local description=$(grep "^DESCRIPTION=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        
        log "VM: ${vm_name}"
        log "GDB Port: ${gdb_port}"
        log "Started: ${start_time}"
        log "Ended: ${end_time}"
        log "Duration: ${duration} seconds"
        log "Description: ${description}"
    fi
    
    log ""
    log "Recording Contents:"
    log "="
    
    # Display recording file
    if [[ -f "$recording_file" ]]; then
        head -50 "$recording_file"
        echo ""
        echo "... [truncated]"
    fi
    
    return 0
}

# List all debug sessions
# Usage: list_debug_sessions [status_filter]
list_debug_sessions() {
    local status_filter="$1"
    
    heading "Debug Sessions"
    
    ensure_debug_session_dirs
    
    local sessions=()
    while IFS= read -r session_dir; do
        [[ -d "$session_dir" ]] && sessions+=("$session_dir")
    done < <(find "$DEBUG_SESSION_DIR" -type d -maxdepth 1 | sort -r)
    
    if [[ ${#sessions[@]} -eq 0 ]]; then
        log "No debug sessions found"
        return 0
    fi
    
    local index=0
    for session_dir in "${sessions[@]}"; do
        local session_name=$(basename "$session_dir")
        local metadata_file="${session_dir}/session.meta"
        
        if [[ ! -f "$metadata_file" ]]; then
            continue
        fi
        
        local status=$(grep "^STATUS=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local vm_name=$(grep "^VM_NAME=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local start_time=$(grep "^STARTED_AT=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local duration=$(grep "^DURATION_SECONDS=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local size=$(du -sh "$session_dir" 2>/dev/null | cut -f1)
        
        # Apply status filter if specified
        if [[ -n "$status_filter" && "$status" != "$status_filter" ]]; then
            continue
        fi
        
        echo "  [${index}] ${session_name} [${status}] [${size}]"
        echo "      VM: ${vm_name:-unknown}"
        echo "      Started: ${start_time}"
        if [[ -n "$duration" ]]; then
            echo "      Duration: ${duration}s"
        fi
        echo ""
        
        index=$((index + 1))
    done
    
    return 0
}

# Delete a debug session
# Usage: delete_debug_session <session_name>
delete_debug_session() {
    local session_name="$1"
    
    heading "Delete Debug Session"
    
    local session_dir="${DEBUG_SESSION_DIR}/${session_name}"
    
    if [[ ! -d "$session_dir" ]]; then
        die "Debug session not found: ${session_name}"
    fi
    
    # Confirm deletion
    if ! confirm "Are you sure you want to delete debug session '${session_name}'?"; then
        log "Deletion cancelled"
        return 0
    fi
    
    log "Deleting debug session: ${session_dir}"
    rm -rf "${session_dir}"
    
    log "✅ Debug session deleted: ${session_name}"
    
    return 0
}

# Interactive debug session recording start
start_debug_recording_interactive() {
    if ! is_interactive; then
        warn "start_debug_recording_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Start Debug Session Recording [Interactive]"
    
    local session_name
    session_name=$(ask "Enter session name (leave blank for auto-generated)" "")
    
    list_vms
    local vm_name
    vm_name=$(ask "Enter VM name" "")
    
    local gdb_port
    gdb_port=$(ask "Enter GDB port" "1234")
    
    local description
    description=$(ask "Enter description for this debug session" "Debug session")
    
    start_debug_recording "$session_name" "$vm_name" "$gdb_port" "$description"
}

# Interactive debug session replay
replay_debug_session_interactive() {
    if ! is_interactive; then
        warn "replay_debug_session_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Replay Debug Session [Interactive]"
    
    list_debug_sessions
    echo ""
    
    local session_name
    session_name=$(ask "Enter session name to replay" "")
    
    if [[ -z "$session_name" ]]; then
        die "Session name is required"
    fi
    
    replay_debug_session "$session_name"
}

# ---------------------------------------------------------------------------
# Enhanced Debugging Workflows - Breakpoint Presets
# ---------------------------------------------------------------------------

# Directory for breakpoint presets
BREAKPOINT_PRESET_DIR="${CONFIG_DIR}/breakpoint_presets"

# Ensure breakpoint preset directory exists
ensure_breakpoint_preset_dirs() {
    ensure_dir "${BREAKPOINT_PRESET_DIR}"
}

# Define a breakpoint preset
# Usage: create_breakpoint_preset <preset_name> <description> <breakpoints_file>
create_breakpoint_preset() {
    local preset_name="$1"
    local description="$2"
    local breakpoints_file="$3"
    
    heading "Creating Breakpoint Preset: ${preset_name}"
    
    ensure_breakpoint_preset_dirs
    
    if [[ -z "$preset_name" ]]; then
        die "Preset name is required"
    fi
    
    local preset_dir="${BREAKPOINT_PRESET_DIR}/${preset_name}"
    local preset_meta="${preset_dir}/preset.meta"
    local preset_gdb="${preset_dir}/breakpoints.gdb"
    
    # Create preset directory
    log "Creating breakpoint preset directory: ${preset_dir}"
    mkdir -p "${preset_dir}"
    
    # Save metadata
    [[ -n "$description" ]] || description="Breakpoint preset for ${preset_name}"
    
    cat > "${preset_meta}" << EOF
# Breakpoint Preset Metadata
PRESET_NAME="${preset_name}"
DESCRIPTION="${description}"
CREATED_AT="$(date +%Y-%m-%d\ %H:%M:%S)"
ARCHITECTURE="universal"
EOF
    
    # Process breakpoints file
    if [[ -f "$breakpoints_file" ]]; then
        cp "$breakpoints_file" "${preset_gdb}"
    else
        # Create empty GDB commands file
        cat > "${preset_gdb}" << EOF
# GDB Breakpoint Commands for ${preset_name}
# Add breakpoints below
# Example: break main
# Example: break *0x00000400
EOF
    fi
    
    log "✅ Breakpoint preset created: ${preset_name}"
    log "   Directory: ${preset_dir}"
    log "   GDB commands: ${preset_gdb}"
    
    return 0
}

# Apply a breakpoint preset to a VM
# Usage: apply_breakpoint_preset <preset_name> <vm_name> [gdb_port]
apply_breakpoint_preset() {
    local preset_name="$1"
    local vm_name="$2"
    local gdb_port="$3"
    
    heading "Applying Breakpoint Preset: ${preset_name} to VM: ${vm_name}"
    
    ensure_breakpoint_preset_dirs
    
    local preset_dir="${BREAKPOINT_PRESET_DIR}/${preset_name}"
    local preset_gdb="${preset_dir}/breakpoints.gdb"
    
    if [[ ! -d "$preset_dir" ]]; then
        die "Breakpoint preset not found: ${preset_name}"
    fi
    
    if [[ ! -f "$preset_gdb" ]]; then
        die "Breakpoint preset GDB file not found: ${preset_gdb}"
    fi
    
    [[ -n "$gdb_port" ]] || gdb_port="1234"
    
    # Read VM IP if available
    local vm_ip=""
    if get_vm_ip "$vm_name"; then
        vm_ip=$(get_vm_ip "$vm_name")
    else
        # Try to get from config
        local config_file=$(find_vm_config_file "$vm_name")
        if [[ -f "$config_file" ]]; then
            vm_ip=$(grep -E "^IP_ADDRESS|^GUEST_IP" "$config_file" | head -1 | cut -d'=' -f2)
        fi
    fi
    
    log "Applying breakpoint preset to VM: ${vm_name} [IP: ${vm_ip:-not available}]"
    log "GDB port: ${gdb_port}"
    
    # Create temporary GDB script with preset + connection
    local temp_gdb_script=$(mktemp /tmp/apply_preset_XXXXXX.gdb)
    
    cat > "$temp_gdb_script" << EOF
# Auto-generated GDB script for breakpoint preset: ${preset_name}
# VM: ${vm_name}
# Port: ${gdb_port}

# Connect to VM
target remote ${vm_ip:+$vm_ip:}$gdb_port

# Load breakpoint preset commands
source ${preset_gdb}

# Continue execution
continue
EOF
    
    log "✅ Breakpoint preset applied"
    log "   GDB script created: ${temp_gdb_script}"
    log ""
    log "To use this preset, run:"
    log "  gdb-multiarch -x ${temp_gdb_script}"
    log ""
    log "Or manually with:"
    log "  gdb-multiarch"
    log "  [gdb] source ${preset_gdb}"
    log "  [gdb] target remote ${vm_ip:+$vm_ip:}$gdb_port"
    log "  [gdb] continue"
    
    return 0
}

# List available breakpoint presets
# Usage: list_breakpoint_presets
list_breakpoint_presets() {
    heading "Breakpoint Presets"
    
    ensure_breakpoint_preset_dirs
    
    local presets=()
    while IFS= read -r preset_dir; do
        [[ -d "$preset_dir" ]] && presets+=("$preset_dir")
    done < <(find "$BREAKPOINT_PRESET_DIR" -type d -maxdepth 1 | sort)
    
    if [[ ${#presets[@]} -eq 0 ]]; then
        log "No breakpoint presets found"
        return 0
    fi
    
    log "Available Breakpoint Presets:"
    log "="
    
    for i in "${!presets[@]}"; do
        local preset_name=$(basename "${presets[$i]}")
        local preset_meta="${presets[$i]}/preset.meta"
        
        if [[ -f "$preset_meta" ]]; then
            local description=$(grep "^DESCRIPTION=" "$preset_meta" | cut -d'=' -f2- | tr -d '"')
            local created_at=$(grep "^CREATED_AT=" "$preset_meta" | cut -d'=' -f2- | tr -d '"')
            local architecture=$(grep "^ARCHITECTURE=" "$preset_meta" | cut -d'=' -f2- | tr -d '"')
            local size=$(du -sh "${presets[$i]}" 2>/dev/null | cut -f1)
            
            echo "  [${i}] ${preset_name} [${architecture}] [${size}]"
            echo "      Created: ${created_at}"
            echo "      Description: ${description}"
            
            # Show first few lines of the preset
            local preset_gdb="${presets[$i]}/breakpoints.gdb"
            if [[ -f "$preset_gdb" ]]; then
                echo "      Preview:"
                head -3 "$preset_gdb" | sed 's/^/         /'
            fi
            echo ""
        fi
    done
    
    return 0
}

# Delete a breakpoint preset
# Usage: delete_breakpoint_preset <preset_name>
delete_breakpoint_preset() {
    local preset_name="$1"
    
    heading "Delete Breakpoint Preset"
    
    ensure_breakpoint_preset_dirs
    
    local preset_dir="${BREAKPOINT_PRESET_DIR}/${preset_name}"
    
    if [[ ! -d "$preset_dir" ]]; then
        die "Breakpoint preset not found: ${preset_name}"
    fi
    
    # Confirm deletion
    if ! confirm "Are you sure you want to delete breakpoint preset '${preset_name}'?"; then
        log "Deletion cancelled"
        return 0
    fi
    
    log "Deleting breakpoint preset: ${preset_dir}"
    rm -rf "${preset_dir}"
    
    log "✅ Breakpoint preset deleted: ${preset_name}"
    
    return 0
}

# Interactive breakpoint preset creation
create_breakpoint_preset_interactive() {
    if ! is_interactive; then
        warn "create_breakpoint_preset_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Create Breakpoint Preset [Interactive]"
    
    local preset_name
    preset_name=$(ask "Enter preset name" "")
    
    if [[ -z "$preset_name" ]]; then
        die "Preset name is required"
    fi
    
    local description
    description=$(ask "Enter description" "Breakpoint preset")
    
    local architecture
    architecture=$(ask "Enter target architecture (universal, 68k, ppc, x86, etc.)" "universal")
    
    # Create preset directory first
    local preset_dir="${BREAKPOINT_PRESET_DIR}/${preset_name}"
    mkdir -p "${preset_dir}"
    
    local preset_gdb="${preset_dir}/breakpoints.gdb"
    
    # Create GDB commands file
    echo "# GDB Breakpoint Commands for ${preset_name}" > "$preset_gdb"
    echo "# Architecture: ${architecture}" >> "$preset_gdb"
    echo "# Generated: $(date)" >> "$preset_gdb"
    echo "" >> "$preset_gdb"
    
    while true; do
        local breakpoint
        breakpoint=$(ask "Enter breakpoint command (or 'done' to finish)" "")
        
        if [[ "$breakpoint" == "done" || -z "$breakpoint" ]]; then
            break
        fi
        
        echo "${breakpoint}" >> "$preset_gdb"
    done
    
    # Save metadata
    local preset_meta="${preset_dir}/preset.meta"
    cat > "${preset_meta}" << EOF
# Breakpoint Preset Metadata
PRESET_NAME="${preset_name}"
DESCRIPTION="${description}"
CREATED_AT="$(date +%Y-%m-%d\ %H:%M:%S)"
ARCHITECTURE="${architecture}"
EOF
    
    log "✅ Breakpoint preset created: ${preset_name}"
    log "   File: ${preset_gdb}"
    
    return 0
}

# ---------------------------------------------------------------------------
# Enhanced Debugging Workflows - Multi-VM Debugging
# ---------------------------------------------------------------------------

# Directory for multi-VM debug sessions
MULTI_DEBUG_DIR="${CONFIG_DIR}/multi_debug"

# Ensure multi-debug directory exists
ensure_multi_debug_dirs() {
    ensure_dir "${MULTI_DEBUG_DIR}"
}

# Start multi-VM debug session
# Usage: start_multi_debug <session_name> <vm1> <port1> [vm2 port2 ...]
start_multi_debug() {
    local session_name="$1"
    shift
    local vms=("$@")
    
    heading "Starting Multi-VM Debug Session: ${session_name}"
    
    ensure_multi_debug_dirs
    
    if [[ ${#vms[@]} -lt 2 || $(( ${#vms[@]} % 2 )) -ne 0 ]]; then
        die "Usage: start_multi_debug SESSION_NAME VM1 PORT1 [VM2 PORT2 ...]"
    fi
    
    [[ -n "$session_name" ]] || session_name="multi_debug_$(date +%Y%m%d-%H%M%S)"
    
    local session_dir="${MULTI_DEBUG_DIR}/${session_name}"
    local metadata_file="${session_dir}/session.meta"
    local script_file="${session_dir}/multi_debug.sh"
    
    # Create session directory
    log "Creating multi-debug session directory: ${session_dir}"
    mkdir -p "${session_dir}"
    
    # Save metadata
    cat > "${metadata_file}" << EOF
# Multi-VM Debug Session Metadata
SESSION_NAME="${session_name}"
STARTED_AT="$(date +%Y-%m-%d\ %H:%M:%S)"
STATUS="active"
VM_COUNT="$(( ${#vms[@]} / 2 ))"
EOF
    
    # Create debug script that starts GDB for each VM
    echo "#!/bin/bash" > "${script_file}"
    echo "# Multi-VM Debug Script for session: ${session_name}" >> "${script_file}"
    echo "# Generated: $(date)" >> "${script_file}"
    echo "" >> "${script_file}"
    echo 'SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"' >> "${script_file}"
    echo 'SESSION_DIR="${SCRIPT_DIR}"' >> "${script_file}"
    echo "" >> "${script_file}"
    
    # Add GDB commands for each VM
    local vm_count=$(( ${#vms[@]} / 2 ))
    for ((i=0; i<vm_count; i++)); do
        local vm_name="${vms[$((i*2))]}"
        local gdb_port="${vms[$((i*2+1))]}"
        local gdb_script="${session_dir}/gdb_${vm_name}.gdb"
        
        # Create individual GDB script for this VM
        echo "# GDB script for VM: ${vm_name}" > "${gdb_script}"
        echo "# Port: ${gdb_port}" >> "${gdb_script}"
        echo "target remote localhost:${gdb_port}" >> "${gdb_script}"
        echo "set pagination off" >> "${gdb_script}"
        echo "set logging file ${session_dir}/debug_${vm_name}.log" >> "${gdb_script}"
        echo "set logging enabled on" >> "${gdb_script}"
        echo "continue" >> "${gdb_script}"
        
        # Add to main script
        echo "" >> "${script_file}"
        echo "# Starting GDB for ${vm_name} on port ${gdb_port}" >> "${script_file}"
        echo "echo \"Starting debug session for ${vm_name}...\"" >> "${script_file}"
        echo "gdb-multiarch -x \"${gdb_script}\" &" >> "${script_file}"
        
        log "Added VM: ${vm_name} on port: ${gdb_port}"
    done
    
    # Add cleanup and instructions to main script
    echo "" >> "${script_file}"
    echo "echo \"Multi-VM debug session started for ${vm_count} VMs\"" >> "${script_file}"
    echo "echo \"Session directory: ${session_dir}\"" >> "${script_file}"
    echo "echo \"Logs are being written to individual debug_*.log files\"" >> "${script_file}"
    echo "echo \"Press Ctrl+C to stop all debug sessions\"" >> "${script_file}"
    echo "" >> "${script_file}"
    echo "# Wait for all background processes" >> "${script_file}"
    echo "wait" >> "${script_file}"
    
    chmod +x "${script_file}"
    
    log "✅ Multi-VM debug session configured: ${session_name}"
    log "   Session directory: ${session_dir}"
    log "   Script: ${script_file}"
    log "   VMs configured: ${vm_count}"
    log ""
    log "To start the multi-debug session:"
    log "  ${script_file}"
    log ""
    log "To start it in background:"
    log "  nohup ${script_file} &"
    
    return 0
}

# Stop multi-VM debug session
# Usage: stop_multi_debug <session_name>
stop_multi_debug() {
    local session_name="$1"
    
    heading "Stopping Multi-VM Debug Session: ${session_name}"
    
    local session_dir="${MULTI_DEBUG_DIR}/${session_name}"
    local metadata_file="${session_dir}/session.meta"
    
    if [[ ! -d "$session_dir" ]]; then
        die "Multi-debug session not found: ${session_name}"
    fi
    
    # Find and kill any GDB processes associated with this session
    local end_time=$(date +"%Y-%m-%d %H:%M:%S")
    local start_time=$(grep "^STARTED_AT=" "$metadata_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')
    
    # Update metadata
    sed -i.bak "s/^STATUS=.*/STATUS="stopped"/" "$metadata_file" 2>/dev/null
    echo "ENDED_AT=\"${end_time}\"" >> "$metadata_file"
    
    # Kill any GDB processes that might be running for this session
    local gdb_pids=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local gdb_script="${session_dir}/${line}"
            if [[ -f "$gdb_script" ]]; then
                # Find GDB processes using this script
                local pids=$(pgrep -f "${gdb_script}" 2>/dev/null || true)
                if [[ -n "$pids" ]]; then
                    gdb_pids+=($pids)
                fi
            fi
        fi
    done < <(find "$session_dir" -name "*.gdb" 2>/dev/null)
    
    if [[ ${#gdb_pids[@]} -gt 0 ]]; then
        log "Stopping ${#gdb_pids[@]} GDB processes..."
        for pid in "${gdb_pids[@]}"; do
            if kill "$pid" 2>/dev/null; then
                log "Stopped GDB process: ${pid}"
            fi
        done
    else
        log "No active GDB processes found for this session"
    fi
    
    # Calculate duration
    local start_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" +%s 2>/dev/null || echo 0)
    local end_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$end_time" +%s 2>/dev/null || echo 0)
    local duration=$((end_ts - start_ts))
    
    log "✅ Multi-VM debug session stopped: ${session_name}"
    log "   Duration: ${duration} seconds"
    
    return 0
}

# List multi-VM debug sessions
# Usage: list_multi_debug_sessions [status_filter]
list_multi_debug_sessions() {
    local status_filter="$1"
    
    heading "Multi-VM Debug Sessions"
    
    ensure_multi_debug_dirs
    
    local sessions=()
    while IFS= read -r session_dir; do
        [[ -d "$session_dir" ]] && sessions+=("$session_dir")
    done < <(find "$MULTI_DEBUG_DIR" -type d -maxdepth 1 | sort -r)
    
    if [[ ${#sessions[@]} -eq 0 ]]; then
        log "No multi-VM debug sessions found"
        return 0
    fi
    
    local index=0
    for session_dir in "${sessions[@]}"; do
        local session_name=$(basename "$session_dir")
        local metadata_file="${session_dir}/session.meta"
        
        if [[ ! -f "$metadata_file" ]]; then
            continue
        fi
        
        local status=$(grep "^STATUS=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local vm_count=$(grep "^VM_COUNT=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local start_time=$(grep "^STARTED_AT=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local end_time=$(grep "^ENDED_AT=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        local size=$(du -sh "$session_dir" 2>/dev/null | cut -f1)
        
        # Apply status filter if specified
        if [[ -n "$status_filter" && "$status" != "$status_filter" ]]; then
            continue
        fi
        
        echo "  [${index}] ${session_name} [${status}] [${size}]"
        echo "      VMs: ${vm_count}"
        echo "      Started: ${start_time}"
        if [[ -n "$end_time" ]]; then
            echo "      Ended: ${end_time}"
        fi
        echo ""
        
        index=$((index + 1))
    done
    
    return 0
}

# Delete multi-VM debug session
# Usage: delete_multi_debug_session <session_name>
delete_multi_debug_session() {
    local session_name="$1"
    
    heading "Delete Multi-VM Debug Session"
    
    local session_dir="${MULTI_DEBUG_DIR}/${session_name}"
    
    if [[ ! -d "$session_dir" ]]; then
        die "Multi-debug session not found: ${session_name}"
    fi
    
    # Stop the session first if it's active
    local metadata_file="${session_dir}/session.meta"
    if [[ -f "$metadata_file" ]]; then
        local status=$(grep "^STATUS=" "$metadata_file" | cut -d'=' -f2- | tr -d '"')
        if [[ "$status" == "active" ]]; then
            log "Stopping active session first..."
            stop_multi_debug "$session_name"
        fi
    fi
    
    # Confirm deletion
    if ! confirm "Are you sure you want to delete multi-debug session '${session_name}'?"; then
        log "Deletion cancelled"
        return 0
    fi
    
    log "Deleting multi-debug session: ${session_dir}"
    rm -rf "${session_dir}"
    
    log "✅ Multi-debug session deleted: ${session_name}"
    
    return 0
}

# Interactive multi-VM debug session start
start_multi_debug_interactive() {
    if ! is_interactive; then
        warn "start_multi_debug_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Start Multi-VM Debug Session [Interactive]"
    
    list_vms
    echo ""
    
    local session_name
    session_name=$(ask "Enter session name (leave blank for auto-generated)" "")
    
    local vms=()
    while true; do
        local vm_name
        vm_name=$(ask "Enter VM name to debug (or 'done' to finish)" "")
        
        if [[ "$vm_name" == "done" || -z "$vm_name" ]]; then
            break
        fi
        
        local gdb_port
        gdb_port=$(ask "Enter GDB port for ${vm_name}" "1234")
        
        vms+=("$vm_name" "$gdb_port")
    done
    
    if [[ ${#vms[@]} -lt 2 ]]; then
        die "At least one VM must be specified"
    fi
    
    start_multi_debug "$session_name" "${vms[@]}"
}

# ---------------------------------------------------------------------------
# Enhanced Debugging Workflows - Debug Symbol Management
# ---------------------------------------------------------------------------

# Directory for debug symbols
DEBUG_SYMBOLS_DIR="${CONFIG_DIR}/debug_symbols"

# Ensure debug symbols directory exists
ensure_debug_symbols_dirs() {
    ensure_dir "${DEBUG_SYMBOLS_DIR}"
}

# Download and extract debug symbols for a binary
# Usage: download_debug_symbols <binary_path> [output_dir] [url]
download_debug_symbols() {
    local binary_path="$1"
    local output_dir="$2"
    local url="$3"
    
    heading "Downloading Debug Symbols for: ${binary_path}"
    
    ensure_debug_symbols_dirs
    
    if [[ ! -f "$binary_path" ]]; then
        die "Binary file not found: ${binary_path}"
    fi
    
    local binary_name=$(basename "$binary_path")
    [[ -n "$output_dir" ]] || output_dir="${DEBUG_SYMBOLS_DIR}/${binary_name}"
    
    # Create output directory
    log "Output directory: ${output_dir}"
    mkdir -p "${output_dir}"
    
    # Check if debug symbols are already available
    local debug_file="${output_dir}/${binary_name}.debug"
    
    if [[ -f "$debug_file" ]]; then
        log "Debug symbols already exist: ${debug_file}"
        return 0
    fi
    
    # Method 1: Try to extract debug symbols from the binary
    if command -v objcopy &>/dev/null; then
        log "Attempting to extract debug symbols with objcopy..."
        if objcopy --only-keep-debug "$binary_path" "$debug_file" 2>/dev/null; then
            # Strip debug symbols from original binary
            objcopy --strip-debug "$binary_path" "${output_dir}/${binary_name}.stripped" 2>/dev/null
            # Add debug link to original binary
            objcopy --add-gnu-debuglink="$debug_file" "${output_dir}/${binary_name}.stripped" 2>/dev/null
            
            log "✅ Debug symbols extracted: ${debug_file}"
            log "   Stripped binary: ${output_dir}/${binary_name}.stripped"
            return 0
        fi
    fi
    
    # Method 2: Download from URL if provided
    if [[ -n "$url" ]]; then
        log "Downloading debug symbols from: ${url}"
        if command -v wget &>/dev/null; then
            if wget -O "$debug_file" "$url" 2>/dev/null; then
                log "✅ Debug symbols downloaded: ${debug_file}"
                return 0
            fi
        elif command -v curl &>/dev/null; then
            if curl -L -o "$debug_file" "$url" 2>/dev/null; then
                log "✅ Debug symbols downloaded: ${debug_file}"
                return 0
            fi
        fi
        
        warn "Failed to download debug symbols from URL"
    fi
    
    # Method 3: Look for debug symbols in common locations
    local common_locations=(
        "/usr/lib/debug/.build-id/"
        "/usr/lib/debug/"
        "/opt/debug/"
    )
    
    for location in "${common_locations[@]}"; do
        if [[ -d "$location" ]]; then
            local debug_files=()
            while IFS= read -r debug_file; do
                [[ -f "$debug_file" ]] && debug_files+=("$debug_file")
            done < <(find "$location" -name "*.debug" -path "*${binary_name}*" 2>/dev/null)
            
            if [[ ${#debug_files[@]} -gt 0 ]]; then
                log "Found debug symbols in ${location}"
                cp "${debug_files[0]}" "$debug_file"
                log "✅ Copied debug symbols: ${debug_file}"
                return 0
            fi
        fi
    done
    
    warn "Could not find or extract debug symbols for: ${binary_path}"
    warn "Try installing debug symbol packages for your distribution"
    
    return 1
}

# Generate debug information for a binary
# Usage: generate_debug_info <binary_path> [output_dir]
generate_debug_info() {
    local binary_path="$1"
    local output_dir="$2"
    
    heading "Generating Debug Information for: ${binary_path}"
    
    if [[ ! -f "$binary_path" ]]; then
        die "Binary file not found: ${binary_path}"
    fi
    
    local binary_name=$(basename "$binary_path")
    [[ -n "$output_dir" ]] || output_dir="${DEBUG_SYMBOLS_DIR}/${binary_name}"
    
    ensure_debug_symbols_dirs
    mkdir -p "${output_dir}"
    
    local info_file="${output_dir}/debug_info.txt"
    
    log "Collecting debug information..."
    
    echo "Debug Information for: ${binary_name}" > "$info_file"
    echo "Generated: $(date)" >> "$info_file"
    echo "=" >> "$info_file"
    
    # File type information
    if command -v file &>/dev/null; then
        echo "" >> "$info_file"
        echo "File Type:" >> "$info_file"
        file "$binary_path" >> "$info_file" 2>&1
    fi
    
    # Symbol table information
    if command -v nm &>/dev/null; then
        echo "" >> "$info_file"
        echo "Symbol Table:" >> "$info_file"
        nm "$binary_path" | head -20 >> "$info_file" 2>&1
    fi
    
    # Architecture information
    if command -v readelf &>/dev/null; then
        echo "" >> "$info_file"
        echo "ELF Information:" >> "$info_file"
        readelf -h "$binary_path" >> "$info_file" 2>&1
    fi
    
    # Section information
    if command -v objdump &>/dev/null; then
        echo "" >> "$info_file"
        echo "Sections:" >> "$info_file"
        objdump -h "$binary_path" >> "$info_file" 2>&1
        
        echo "" >> "$info_file"
        echo "Debug Sections:" >> "$info_file"
        objdump -g "$binary_path" >> "$info_file" 2>&1 | head -20
    fi
    
    log "✅ Debug information generated: ${info_file}"
    
    return 0
}

# List available debug symbols
# Usage: list_debug_symbols [binary_name]
list_debug_symbols() {
    local binary_name="$1"
    
    heading "Debug Symbols"
    
    ensure_debug_symbols_dirs
    
    if [[ -n "$binary_name" ]]; then
        local symbols_dir="${DEBUG_SYMBOLS_DIR}/${binary_name}"
        
        if [[ ! -d "$symbols_dir" ]]; then
            log "No debug symbols found for: ${binary_name}"
            return 0
        fi
        
        log "Debug symbols for: ${binary_name}"
        log "="
        
        local files=()
        while IFS= read -r symbol_file; do
            [[ -f "$symbol_file" ]] && files+=("$symbol_file")
        done < <(find "$symbols_dir" -type f | sort)
        
        for symbol_file in "${files[@]}"; do
            local size=$(du -h "$symbol_file" 2>/dev/null | cut -f1)
            local modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$symbol_file" 2>/dev/null || date -r "$symbol_file" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
            echo "  ${symbol_file} [${size}] [${modified}]"
        done
    else
        log "All Debug Symbols:"
        log "="
        
        local symbol_dirs=()
        while IFS= read -r symbol_dir; do
            [[ -d "$symbol_dir" ]] && symbol_dirs+=("$symbol_dir")
        done < <(find "$DEBUG_SYMBOLS_DIR" -type d -maxdepth 1 | sort)
        
        for symbol_dir in "${symbol_dirs[@]}"; do
            local binary_name=$(basename "$symbol_dir")
            local file_count=$(find "$symbol_dir" -type f | wc -l | tr -d ' ')
            local dir_size=$(du -sh "$symbol_dir" 2>/dev/null | cut -f1)
            
            log "📁 ${binary_name}: ${file_count} files [${dir_size}]"
        done
    fi
    
    return 0
}

# Delete debug symbols for a binary
# Usage: delete_debug_symbols <binary_name>
delete_debug_symbols() {
    local binary_name="$1"
    
    heading "Delete Debug Symbols"
    
    ensure_debug_symbols_dirs
    
    local symbols_dir="${DEBUG_SYMBOLS_DIR}/${binary_name}"
    
    if [[ ! -d "$symbols_dir" ]]; then
        die "Debug symbols directory not found: ${symbols_dir}"
    fi
    
    # Confirm deletion
    if ! confirm "Are you sure you want to delete debug symbols for '${binary_name}'?"; then
        log "Deletion cancelled"
        return 0
    fi
    
    log "Deleting debug symbols: ${symbols_dir}"
    rm -rf "${symbols_dir}"
    
    log "✅ Debug symbols deleted: ${binary_name}"
    
    return 0
}

# Interactive debug symbols management
download_debug_symbols_interactive() {
    if ! is_interactive; then
        warn "download_debug_symbols_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Download Debug Symbols [Interactive]"
    
    local binary_path
    binary_path=$(ask "Enter path to binary file" "")
    
    if [[ ! -f "$binary_path" ]]; then
        die "Binary file not found: ${binary_path}"
    fi
    
    local output_dir
    output_dir=$(ask "Enter output directory (leave blank for default)" "")
    
    local url
    url=$(ask "Enter URL to download debug symbols from (leave blank to extract from binary)" "")
    
    download_debug_symbols "$binary_path" "$output_dir" "$url"
}

# ---------------------------------------------------------------------------
# Enhanced Debugging Workflows - Automatic GDB Configuration
# ---------------------------------------------------------------------------

# Directory for GDB configurations
GDB_CONFIG_DIR="${CONFIG_DIR}/gdb_configs"

# Ensure GDB config directory exists
ensure_gdb_config_dirs() {
    ensure_dir "${GDB_CONFIG_DIR}"
}

# Generate GDB configuration for a specific architecture
# Usage: generate_gdb_config <arch> [output_file] [vm_name] [port]
generate_gdb_config() {
    local arch="$1"
    local output_file="$2"
    local vm_name="$3"
    local port="$4"
    
    heading "Generating GDB Configuration for Architecture: ${arch}"
    
    ensure_gdb_config_dirs
    
    # Set defaults
    [[ -n "$output_file" ]] || output_file="${GDB_CONFIG_DIR}/gdb_${arch}.gdb"
    [[ -n "$port" ]] || port="1234"
    
    log "Configuration file: ${output_file}"
    
    case "$arch" in
        68k|m68k)
            cat > "$output_file" << EOF
# GDB Configuration for Motorola 68k Architecture
# Generated: $(date)

# Set architecture and target
set architecture m68k

# Common 68k GDB settings
set disable-randomization on
set confirmation off

# Connect to VM
target remote localhost:${port}

# 68k-specific settings
set m68k:split-hll on
set m68k:assembly-flavor att

# Load symbols if available
file ${vm_name:+${VM_DIR}/${vm_name}/}

# Continue execution
continue
EOF
            ;;
        ppc|powerpc)
            cat > "$output_file" << EOF
# GDB Configuration for PowerPC Architecture
# Generated: $(date)

# Set architecture and target
set architecture powerpc

# Common PowerPC GDB settings
set disable-randomization on
set confirmation off

# Connect to VM
target remote localhost:${port}

# PowerPC-specific settings
set powerpc:vector-mode auto
set powerpc:fpu on

# Load symbols if available
file ${vm_name:+${VM_DIR}/${vm_name}/}

# Continue execution
continue
EOF
            ;;
        ppc64|powerpc64)
            cat > "$output_file" << EOF
# GDB Configuration for PowerPC 64-bit Architecture
# Generated: $(date)

# Set architecture and target
set architecture powerpc:64

# Common PowerPC 64-bit GDB settings
set disable-randomization on
set confirmation off

# Connect to VM
target remote localhost:${port}

# PowerPC 64-bit-specific settings
set powerpc:vector-mode altivec
set powerpc:fpu on

# Load symbols if available
file ${vm_name:+${VM_DIR}/${vm_name}/}

# Continue execution
continue
EOF
            ;;
        x86|i386)
            cat > "$output_file" << EOF
# GDB Configuration for x86 (32-bit) Architecture
# Generated: $(date)

# Set architecture and target
set architecture i386

# Common x86 GDB settings
set disable-randomization on
set confirmation off

# Connect to VM
target remote localhost:${port}

# x86-specific settings
set disable-randomization on

# Load symbols if available
file ${vm_name:+${VM_DIR}/${vm_name}/}

# Continue execution
continue
EOF
            ;;
        x86_64|amd64)
            cat > "$output_file" << EOF
# GDB Configuration for x86_64 Architecture
# Generated: $(date)

# Set architecture and target
set architecture i386:x86-64

# Common x86_64 GDB settings
set disable-randomization on
set confirmation off

# Connect to VM
target remote localhost:${port}

# x86_64-specific settings
set disable-randomization on
set debug malloc 1

# Load symbols if available
file ${vm_name:+${VM_DIR}/${vm_name}/}

# Continue execution
continue
EOF
            ;;
        sparc|sparc64)
            cat > "$output_file" << EOF
# GDB Configuration for SPARC Architecture
# Generated: $(date)

# Set architecture and target
set architecture sparc${arch#sparc}

# Common SPARC GDB settings
set disable-randomization on
set confirmation off

# Connect to VM
target remote localhost:${port}

# SPARC-specific settings
set sparc:fpu on
set sparc:vis on

# Load symbols if available
file ${vm_name:+${VM_DIR}/${vm_name}/}

# Continue execution
continue
EOF
            ;;
        arm|aarch64)
            cat > "$output_file" << EOF
# GDB Configuration for ARM Architecture
# Generated: $(date)

# Set architecture and target
set architecture arm${arch#arm}

# Common ARM GDB settings
set disable-randomization on
set confirmation off

# Connect to VM
target remote localhost:${port}

# ARM-specific settings
set arm:fpu on
set arm:neon on

# Load symbols if available
file ${vm_name:+${VM_DIR}/${vm_name}/}

# Continue execution
continue
EOF
            ;;
        *)
            cat > "$output_file" << EOF
# GDB Configuration for Architecture: ${arch}
# Generated: $(date)

# Set architecture and target
set architecture ${arch}

# Common GDB settings
set disable-randomization on
set confirmation off

# Connect to VM
target remote localhost:${port}

# Load symbols if available
file ${vm_name:+${VM_DIR}/${vm_name}/}

# Continue execution
continue
EOF
            ;;
    esac
    
    log "✅ GDB configuration generated: ${output_file}"
    log ""
    log "To use this configuration:"
    log "  gdb-multiarch -x ${output_file}"
    
    return 0
}

# List available GDB configurations
# Usage: list_gdb_configs
list_gdb_configs() {
    heading "GDB Configurations"
    
    ensure_gdb_config_dirs
    
    local configs=()
    while IFS= read -r config_file; do
        [[ -f "$config_file" ]] && configs+=("$config_file")
    done < <(find "$GDB_CONFIG_DIR" -name "*.gdb" | sort)
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        log "No GDB configurations found"
        return 0
    fi
    
    log "Available GDB Configurations:"
    log "="
    
    for i in "${!configs[@]}"; do
        local config_name=$(basename "${configs[$i]}")
        local size=$(du -sh "${configs[$i]}" 2>/dev/null | cut -f1)
        local modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${configs[$i]}" 2>/dev/null || date -r "${configs[$i]}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
        
        echo "  [${i}] ${config_name} [${size}] [${modified}]"
        
        # Show first few lines as preview
        head -3 "${configs[$i]}" | sed 's/^/      /' || true
        echo ""
    done
    
    return 0
}

# Delete GDB configuration
# Usage: delete_gdb_config <config_name>
delete_gdb_config() {
    local config_name="$1"
    
    heading "Delete GDB Configuration"
    
    ensure_gdb_config_dirs
    
    local config_file="${GDB_CONFIG_DIR}/${config_name}"
    
    if [[ ! -f "$config_file" ]]; then
        die "GDB configuration not found: ${config_name}"
    fi
    
    # Confirm deletion
    if ! confirm "Are you sure you want to delete GDB configuration '${config_name}'?"; then
        log "Deletion cancelled"
        return 0
    fi
    
    log "Deleting GDB configuration: ${config_file}"
    rm -f "${config_file}"
    
    log "✅ GDB configuration deleted: ${config_name}"
    
    return 0
}

# Interactive GDB configuration generation
generate_gdb_config_interactive() {
    if ! is_interactive; then
        warn "generate_gdb_config_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Generate GDB Configuration [Interactive]"
    
    # List available architectures
    echo "Available architectures:"
    local archs=("68k" "m68k" "ppc" "powerpc" "ppc64" "powerpc64" "x86" "i386" "x86_64" "amd64" "sparc" "sparc64" "arm" "aarch64")
    for i in "${!archs[@]}"; do
        echo "  [${i}] ${archs[$i]}"
    done
    echo ""
    
    local arch_index
    arch_index=$(ask "Select architecture" "0")
    local arch="${archs[$arch_index]:-${archs[0]}}"
    
    local output_file
    output_file=$(ask "Enter output filename (leave blank for default)" "")
    
    list_vms
    local vm_name
    vm_name=$(ask "Enter VM name (leave blank for none)" "")
    
    local port
    port=$(ask "Enter GDB port" "1234")
    
    generate_gdb_config "$arch" "$output_file" "$vm_name" "$port"
}

# ---------------------------------------------------------------------------
# Configuration Versioning & Backup System
# ---------------------------------------------------------------------------

# Directory for configuration backups
CONFIG_BACKUP_DIR="${CONFIG_DIR}/backups"
CONFIG_VERSION_DIR="${CONFIG_DIR}/config_versions"

# Ensure backup directories exist
ensure_config_backup_dirs() {
    ensure_dir "${CONFIG_BACKUP_DIR}"
    ensure_dir "${CONFIG_VERSION_DIR}"
}

# Backup VM configuration with version control
# Usage: config_backup <vm_name> [message]
config_backup() {
    local vm_name="$1"
    local message="$2"
    
    heading "Backing Up Configuration for VM: ${vm_name}"
    
    ensure_config_backup_dirs
    
    local config_file=$(find_vm_config_file "$vm_name")
    if [[ ! -f "$config_file" ]]; then
        die "Configuration file not found for VM: ${vm_name}"
    fi
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_dir="${CONFIG_BACKUP_DIR}/${vm_name}"
    local version_dir="${CONFIG_VERSION_DIR}/${vm_name}"
    local backup_file="${backup_dir}/${vm_name}-${timestamp}.conf"
    local version_meta="${version_dir}/${timestamp}.meta"
    
    # Create directories
    mkdir -p "${backup_dir}"
    mkdir -p "${version_dir}"
    
    # Copy configuration file
    cp "$config_file" "${backup_file}"
    
    # Create version metadata
    [[ -n "$message" ]] || message="Automatic backup created on $(date)"
    
    cat > "${version_meta}" << EOF
# Configuration Version Metadata
VM_NAME="${vm_name}"
VERSION_ID="${timestamp}"
BACKUP_FILE="${backup_file}"
CREATED_AT="$(date +%Y-%m-%d\ %H:%M:%S)"
MESSAGE="${message}"
PARENT_VERSION="$(ls -t "${version_dir}" | head -2 | tail -1 | sed 's/\.meta$//')"
EOF
    
    # Update current version symlink
    ln -sf "${backup_file}" "${backup_dir}/${vm_name}-current.conf"
    
    # Create history file if it doesn't exist
    local history_file="${version_dir}/history"
    if [[ ! -f "$history_file" ]]; then
        echo "# Configuration History for ${vm_name}" > "$history_file"
        echo "# Format: TIMESTAMP|MESSAGE|FILE" >> "$history_file"
    fi
    
    echo "${timestamp}|${message}|${backup_file}" >> "$history_file"
    
    log "✅ Configuration backed up: ${backup_file}"
    log "   Version: ${timestamp}"
    log "   Message: ${message}"
    
    return 0
}

# Restore VM configuration from backup
# Usage: config_restore <vm_name> <version_id>
config_restore() {
    local vm_name="$1"
    local version_id="$2"
    
    heading "Restoring Configuration for VM: ${vm_name} from version ${version_id}"
    
    ensure_config_backup_dirs
    
    local version_dir="${CONFIG_VERSION_DIR}/${vm_name}"
    local backup_dir="${CONFIG_BACKUP_DIR}/${vm_name}"
    
    if [[ ! -d "$version_dir" ]]; then
        die "No version history found for VM: ${vm_name}"
    fi
    
    local version_meta="${version_dir}/${version_id}.meta"
    if [[ ! -f "$version_meta" ]]; then
        # Try to find the version
        local available_versions=()
        while IFS= read -r meta_file; do
            [[ -f "$meta_file" ]] && available_versions+=("$(basename "$meta_file" .meta)")
        done < <(find "$version_dir" -name "*.meta" | sort -r)
        
        if [[ ${#available_versions[@]} -eq 0 ]]; then
            die "No versions available for VM: ${vm_name}"
        fi
        
        log "Available versions for ${vm_name}:"
        for i in "${!available_versions[@]}"; do
            echo "  [${i}] ${available_versions[$i]}"
        done
        die "Version not found: ${version_id}. Use one of the above versions."
    fi
    
    local backup_file=$(grep "^BACKUP_FILE=" "$version_meta" | cut -d'=' -f2- | tr -d '"')
    if [[ ! -f "$backup_file" ]]; then
        die "Backup file not found: ${backup_file}"
    fi
    
    local current_config=$(find_vm_config_file "$vm_name")
    
    # Create backup of current config before restoring
    local current_timestamp=$(date +%Y%m%d-%H%M%S)
    local current_backup="${backup_dir}/${vm_name}-pre-restore-${current_timestamp}.conf"
    cp "$current_config" "$current_backup"
    log "Backup of current config saved: ${current_backup}"
    
    # Restore the configuration
    cp "$backup_file" "$current_config"
    
    # Record the restore in history
    local restore_message="Restored from version ${version_id} on $(date)"
    echo "${current_timestamp}|${restore_message}|${current_backup}" >> "${version_dir}/history"
    
    log "✅ Configuration restored: ${current_config}"
    log "   Restored from: ${version_id}"
    log "   Current config backed up to: ${current_backup}"
    
    return 0
}

# Show configuration history for a VM
# Usage: config_history <vm_name>
config_history() {
    local vm_name="$1"
    
    heading "Configuration History for VM: ${vm_name}"
    
    ensure_config_backup_dirs
    
    local version_dir="${CONFIG_VERSION_DIR}/${vm_name}"
    local history_file="${version_dir}/history"
    
    if [[ ! -f "$history_file" ]]; then
        die "No configuration history found for VM: ${vm_name}"
    fi
    
    log "Configuration Changes for ${vm_name}:"
    log "="
    
    # Read history file (skip comments and empty lines)
    local line_num=1
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^#.*$ || -z "$line" ]]; then
            continue
        fi
        
        local timestamp=$(echo "$line" | cut -d'|' -f1)
        local message=$(echo "$line" | cut -d'|' -f2)
        local backup_file=$(echo "$line" | cut -d'|' -f3)
        
        echo "  [${line_num}] ${timestamp}"
        echo "      Message: ${message}"
        echo "      File: ${backup_file}"
        echo ""
        
        line_num=$((line_num + 1))
    done < "$history_file"
    
    # Show available versions
    local versions=()
    while IFS= read -r version_meta; do
        [[ -f "$version_meta" ]] && versions+=("$(basename "$version_meta" .meta)")
    done < <(find "$version_dir" -name "*.meta" | sort -r)
    
    if [[ ${#versions[@]} -gt 0 ]]; then
        log "Available Versions:"
        for i in "${!versions[@]}"; do
            local version_id="${versions[$i]}"
            local meta_file="${version_dir}/${version_id}.meta"
            local created_at=$(grep "^CREATED_AT=" "$meta_file" | cut -d'=' -f2- | tr -d '"')
            local message=$(grep "^MESSAGE=" "$meta_file" | cut -d'=' -f2- | tr -d '"')
            
            echo "  [v${i}] ${version_id} - ${created_at}"
            echo "      ${message}"
        done
    fi
    
    return 0
}

# Show differences between configuration versions
# Usage: config_diff <vm_name> [version1] [version2]
config_diff() {
    local vm_name="$1"
    local version1="$2"
    local version2="$3"
    
    heading "Configuration Differences for VM: ${vm_name}"
    
    ensure_config_backup_dirs
    
    local version_dir="${CONFIG_VERSION_DIR}/${vm_name}"
    
    if [[ ! -d "$version_dir" ]]; then
        die "No version history found for VM: ${vm_name}"
    fi
    
    # If no versions specified, show diff between current and previous
    if [[ -z "$version1" && -z "$version2" ]]; then
        # Find the two most recent versions
        local versions=()
        while IFS= read -r meta_file; do
            [[ -f "$meta_file" ]] && versions+=("$(basename "$meta_file" .meta)")
        done < <(find "$version_dir" -name "*.meta" | sort -r | head -2)
        
        if [[ ${#versions[@]} -lt 2 ]]; then
            die "Need at least 2 versions to show diff"
        fi
        
        version1="${versions[1]}"  # Second most recent
        version2="${versions[0]}"  # Most recent
    fi
    
    local meta1="${version_dir}/${version1}.meta"
    local meta2="${version_dir}/${version2}.meta"
    
    if [[ ! -f "$meta1" || ! -f "$meta2" ]]; then
        die "Version metadata not found for specified versions"
    fi
    
    local backup_file1=$(grep "^BACKUP_FILE=" "$meta1" | cut -d'=' -f2- | tr -d '"')
    local backup_file2=$(grep "^BACKUP_FILE=" "$meta2" | cut -d'=' -f2- | tr -d '"')
    
    local timestamp1=$(grep "^CREATED_AT=" "$meta1" | cut -d'=' -f2- | tr -d '"')
    local timestamp2=$(grep "^CREATED_AT=" "$meta2" | cut -d'=' -f2- | tr -d '"')
    
    log "Comparing versions:"
    log "  Version 1: ${version1} [${timestamp1}]"
    log "  Version 2: ${version2} [${timestamp2}]"
    log ""
    
    if command -v diff &>/dev/null; then
        log "Configuration Differences:"
        log "="
        diff -u "$backup_file1" "$backup_file2" || true
    else
        log "diff command not found. Showing both files:"
        log ""
        log "=== Version ${version1} ==="
        cat "$backup_file1"
        log ""
        log "=== Version ${version2} ==="
        cat "$backup_file2"
    fi
    
    return 0
}

# Commit configuration with custom message
# Usage: config_commit <vm_name> <message>
config_commit() {
    local vm_name="$1"
    local message="$2"
    
    heading "Committing Configuration for VM: ${vm_name}"
    
    if [[ -z "$message" ]]; then
        die "Commit message is required"
    fi
    
    ensure_config_backup_dirs
    
    local config_file=$(find_vm_config_file "$vm_name")
    if [[ ! -f "$config_file" ]]; then
        die "Configuration file not found for VM: ${vm_name}"
    fi
    
    # This is essentially the same as backup but with a required message
    config_backup "$vm_name" "$message"
    
    log "✅ Configuration committed with message: ${message}"
    
    return 0
}

# List all configuration backups
# Usage: list_config_backups [vm_name]
list_config_backups() {
    local vm_name="$1"
    
    heading "Configuration Backups"
    
    ensure_config_backup_dirs
    
    if [[ -n "$vm_name" ]]; then
        # List backups for specific VM
        local backup_dir="${CONFIG_BACKUP_DIR}/${vm_name}"
        
        if [[ ! -d "$backup_dir" ]]; then
            log "No backups found for VM: ${vm_name}"
            return 0
        fi
        
        log "Backups for VM: ${vm_name}"
        log "="
        
        local backups=()
        while IFS= read -r backup_file; do
            [[ -f "$backup_file" ]] && backups+=("$backup_file")
        done < <(find "$backup_dir" -name "*.conf" | sort -r)
        
        for i in "${!backups[@]}"; do
            local backup_name=$(basename "${backups[$i]}")
            local size=$(du -sh "${backups[$i]}" 2>/dev/null | cut -f1)
            local modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${backups[$i]}" 2>/dev/null || date -r "${backups[$i]}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
            
            echo "  [${i}] ${backup_name} [${size}] [${modified}]"
        done
    else
        # List backups for all VMs
        log "All Configuration Backups:"
        log "="
        
        local vm_dirs=()
        while IFS= read -r vm_dir; do
            [[ -d "$vm_dir" ]] && vm_dirs+=("$vm_dir")
        done < <(find "$CONFIG_BACKUP_DIR" -type d -maxdepth 1 | sort)
        
        for vm_dir in "${vm_dirs[@]}"; do
            local vm_name=$(basename "$vm_dir")
            local backup_count=$(find "$vm_dir" -name "*.conf" | wc -l | tr -d ' ')
            local dir_size=$(du -sh "$vm_dir" 2>/dev/null | cut -f1)
            
            echo "  📁 ${vm_name}: ${backup_count} backups [${dir_size}]"
        done
    fi
    
    return 0
}

# Interactive configuration backup
config_backup_interactive() {
    if ! is_interactive; then
        warn "config_backup_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Backup VM Configuration [Interactive]"
    
    list_vms
    echo ""
    
    local vm_name
    vm_name=$(ask "Enter VM name to backup" "")
    
    if [[ -z "$vm_name" ]]; then
        die "VM name is required"
    fi
    
    local config_file=$(find_vm_config_file "$vm_name")
    if [[ ! -f "$config_file" ]]; then
        die "Configuration file not found for VM: ${vm_name}"
    fi
    
    local message
    message=$(ask "Enter backup message (commit message)" "Automatic backup")
    
    config_backup "$vm_name" "$message"
}

# Interactive configuration restore
config_restore_interactive() {
    if ! is_interactive; then
        warn "config_restore_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Restore VM Configuration [Interactive]"
    
    list_vms
    echo ""
    
    local vm_name
    vm_name=$(ask "Enter VM name to restore" "")
    
    if [[ -z "$vm_name" ]]; then
        die "VM name is required"
    fi
    
    # Show available versions
    config_history "$vm_name"
    echo ""
    
    local version_id
    version_id=$(ask "Enter version ID to restore" "")
    
    if [[ -z "$version_id" ]]; then
        die "Version ID is required"
    fi
    
    config_restore "$vm_name" "$version_id"
}

# Interactive configuration history
config_history_interactive() {
    if ! is_interactive; then
        warn "config_history_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Configuration History [Interactive]"
    
    list_vms
    echo ""
    
    local vm_name
    vm_name=$(ask "Enter VM name to show history" "")
    
    if [[ -z "$vm_name" ]]; then
        die "VM name is required"
    fi
    
    config_history "$vm_name"
}

# Interactive configuration diff
config_diff_interactive() {
    if ! is_interactive; then
        warn "config_diff_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Configuration Diff [Interactive]"
    
    list_vms
    echo ""
    
    local vm_name
    vm_name=$(ask "Enter VM name to show diff" "")
    
    if [[ -z "$vm_name" ]]; then
        die "VM name is required"
    fi
    
    local version1
    version1=$(ask "Enter first version (leave blank for most recent)" "")
    
    local version2
    version2=$(ask "Enter second version (leave blank for second most recent)" "")
    
    config_diff "$vm_name" "$version1" "$version2"
}

# Interactive configuration commit
config_commit_interactive() {
    if ! is_interactive; then
        warn "config_commit_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Commit VM Configuration [Interactive]"
    
    list_vms
    echo ""
    
    local vm_name
    vm_name=$(ask "Enter VM name to commit" "")
    
    if [[ -z "$vm_name" ]]; then
        die "VM name is required"
    fi
    
    local config_file=$(find_vm_config_file "$vm_name")
    if [[ ! -f "$config_file" ]]; then
        die "Configuration file not found for VM: ${vm_name}"
    fi
    
    local message
    message=$(ask "Enter commit message" "")
    
    if [[ -z "$message" ]]; then
        die "Commit message is required"
    fi
    
    config_commit "$vm_name" "$message"
}

# ---------------------------------------------------------------------------
# SPICE Advanced Features
# ---------------------------------------------------------------------------

# Directory for SPICE configurations
SPICE_CONFIG_DIR="${CONFIG_DIR}/spice_configs"

# Ensure SPICE config directory exists
ensure_spice_dirs() {
    ensure_dir "${SPICE_CONFIG_DIR}"
}

# Start VM with SPICE display
# Usage: spice_start <vm_name> [port] [tls_port] [options]
spice_start() {
    local vm_name="$1"
    local port="$2"
    local tls_port="$3"
    local options="$4"
    
    heading "Starting VM with SPICE: ${vm_name}"
    
    # Validate VM exists by checking if config exists
    local config_file=""
    if ! find_vm_config "$vm_name" config_file; then
        die "Configuration file not found for VM: ${vm_name}"
    fi
    
    # Set default ports if not specified
    [[ -n "$port" ]] || port="${DEFAULT_SPICE_PORT}"
    [[ -n "$tls_port" ]] || tls_port=""
    
    # Check if VM is already running
    if is_vm_running "$vm_name"; then
        warn "VM ${vm_name} is already running"
        return 1
    fi
    
    log "Starting VM ${vm_name} with SPICE on port ${port}"
    
    # Load configuration
    source_vm_config "$config_file"
    
    # Force SPICE display backend
    DISPLAY_BACKEND="spice"
    
    # Add SPICE-specific arguments
    local spice_args=(-spice "port=${port}")
    
    # Add TLS configuration if TLS port is specified
    if [[ -n "$tls_port" ]]; then
        spice_args+=(-spice "tls-port=${tls_port}")
        spice_args+=(-spice "disable-ticketing")
        log "SPICE TLS enabled on port: ${tls_port}"
    else
        spice_args+=(-spice "disable-ticketing")
        warn "SPICE running without TLS encryption [use tls_port for secure connection]"
    fi
    
    # Add audio redirection
    spice_args+=(-audiodev "spice,id=snd0")
    
    # Add USB redirection if supported
    spice_args+=(-device "virtio-serial-pci,id=spicechannel0,name=vdagent")
    spice_args+=(-chardev "spicevmc,id=vdagent,debug=0,name=vdagent")
    spice_args+=(-device "virtserialport,chardev=vdagent,name=com.redhat.spice.0")
    
    # Add clipboard sharing
    spice_args+=(-device "virtio-serial-pci,id=spicechannel1,name=usbredir")
    spice_args+=(-chardev "spicevmc,id=usbredirchardev1,name=usbredir")
    spice_args+=(-device "virtserialport,chardev=usbredirchardev1,name=com.redhat.spice.1")
    
    # Add additional SPICE options if provided
    if [[ -n "$options" ]]; then
        spice_args+=($options)
    fi
    
    # Add SPICE arguments to QEMU args
    QEMU_ARGS+=("${spice_args[@]}")
    
    # Launch VM with SPICE
    launch_vm "$vm_name"
    
    log "✅ VM ${vm_name} started with SPICE"
    log "SPICE connection: spice://localhost:${port}"
    if [[ -n "$tls_port" ]]; then
        log "Secure SPICE connection: spice://localhost:${tls_port} [TLS]"
    fi
    log ""
    log "To connect to SPICE:"
    log "  Linux: remote-viewer spice://localhost:${port}"
    log "  macOS: open spice://localhost:${port}"
    log "  Windows: virt-viewer spice://localhost:${port}"
    
    return 0
}

# Connect to SPICE console for a VM
# Usage: spice_connect <vm_name> [port]
spice_connect() {
    local vm_name="$1"
    local port="$2"
    
    heading "Connecting to SPICE Console: ${vm_name}"
    
    # Validate VM exists by checking if config exists
    local config_file=""
    if ! find_vm_config "$vm_name" config_file; then
        die "Configuration file not found for VM: ${vm_name}"
    fi
    
    # Get SPICE port from configuration if not specified
    if [[ -z "$port" ]]; then
        if [[ -f "$config_file" ]]; then
            port=$(grep -E "SPICE_PORT|^port=" "$config_file" | head -1 | cut -d'=' -f2)
        fi
        [[ -n "$port" ]] || port="${DEFAULT_SPICE_PORT}"
    fi
    
    # Check if SPICE is available
    if ! command -v remote-viewer &>/dev/null && ! command -v virt-viewer &>/dev/null; then
        die "SPICE client not found. Install remote-viewer or virt-viewer."
    fi
    
    # Check if VM is running
    if ! is_vm_running "$vm_name"; then
        die "VM ${vm_name} is not running. Start it first with SPICE support."
    fi
    
    log "Connecting to SPICE console for VM: ${vm_name}"
    log "Port: ${port}"
    
    # Try to get VM IP for remote connection
    if get_vm_ip "$vm_name"; then
        local vm_ip=$(get_vm_ip "$vm_name")
        log "VM IP: ${vm_ip}"
        
        # Try both localhost and VM IP
        local spice_url="spice://${vm_ip}:${port}"
        log "SPICE URL: ${spice_url}"
        
        # Try to connect using remote-viewer
        if command -v remote-viewer &>/dev/null; then
            log "Connecting with remote-viewer..."
            remote-viewer "${spice_url}" &
            log "✅ SPICE connection initiated with remote-viewer"
        elif command -v virt-viewer &>/dev/null; then
            log "Connecting with virt-viewer..."
            virt-viewer "${spice_url}" &
            log "✅ SPICE connection initiated with virt-viewer"
        else
            log "Open SPICE URL manually:"
            log "  ${spice_url}"
        fi
    else
        # Fallback to localhost
        local spice_url="spice://localhost:${port}"
        log "SPICE URL: ${spice_url}"
        log "Open this URL in your SPICE client"
    fi
    
    return 0
}

# Configure SPICE options for a VM
# Usage: spice_config <vm_name> [port] [tls_port] [tls_cert] [tls_key]
spice_config() {
    local vm_name="$1"
    local port="$2"
    local tls_port="$3"
    local tls_cert="$4"
    local tls_key="$5"
    
    heading "Configuring SPICE Options for VM: ${vm_name}"
    
    # Validate VM exists by checking if config exists
    local config_file=""
    if ! find_vm_config "$vm_name" config_file; then
        die "Configuration file not found for VM: ${vm_name}"
    fi
    
    ensure_spice_dirs
    
    # Set defaults
    [[ -n "$port" ]] || port="${DEFAULT_SPICE_PORT}"
    [[ -n "$tls_port" ]] || tls_port=""
    [[ -n "$tls_cert" ]] || tls_cert=""
    [[ -n "$tls_key" ]] || tls_key=""
    
    # Create SPICE configuration for this VM
    local spice_config_file="${SPICE_CONFIG_DIR}/${vm_name}-spice.conf"
    
    log "Creating SPICE configuration: ${spice_config_file}"
    
    # Create configuration file
    cat > "${spice_config_file}" << EOF
# SPICE Configuration for VM: ${vm_name}
# Generated: $(date)

SPICE_ENABLED=true
SPICE_PORT=${port}
SPICE_TLS_PORT=${tls_port}
SPICE_DISABLE_TICKETING=true
EOF
    
    # Add TLS configuration if cert and key are provided
    if [[ -n "$tls_cert" && -n "$tls_key" ]]; then
        cat >> "${spice_config_file}" << EOF
SPICE_TLS_CERT=${tls_cert}
SPICE_TLS_KEY=${tls_key}
SPICE_TLS_ENABLED=true
EOF
        log "TLS configuration enabled"
    else
        cat >> "${spice_config_file}" << EOF
SPICE_TLS_ENABLED=false
EOF
        if [[ -n "$tls_port" ]]; then
            warn "TLS port specified but no certificate provided. Using non-TLS connection."
        fi
    fi
    
    # Add audio and USB configuration
    cat >> "${spice_config_file}" << EOF
SPICE_AUDIO_ENABLED=true
SPICE_USB_REDIRECTION=true
SPICE_CLIPBOARD_SHARING=true
SPICE_MULTI_MONITOR=false
EOF
    
    log "✅ SPICE configuration created: ${spice_config_file}"
    
    # Update VM configuration to reference SPICE config
    local spice_ref="SPICE_CONFIG=${spice_config_file}"
    
    if ! grep -q "SPICE_CONFIG" "$config_file"; then
        echo "${spice_ref}" >> "$config_file"
        log "VM configuration updated with SPICE reference"
    else
        # Update existing SPICE config reference
        sed -i.bak "s|SPICE_CONFIG=.*|${spice_ref}|" "$config_file" 2>/dev/null
    fi
    
    return 0
}

# Create TLS certificates for SPICE
# Usage: spice_create_tls <cert_path> <key_path> [days]
spice_create_tls() {
    local cert_path="$1"
    local key_path="$2"
    local days="$3"
    
    heading "Creating TLS Certificates for SPICE"
    
    [[ -n "$days" ]] || days=365
    
    if [[ -z "$cert_path" || -z "$key_path" ]]; then
        die "Certificate and key paths are required. Usage: spice_create_tls cert_path key_path [days]"
    fi
    
    # Create directory if it doesn't exist
    local cert_dir=$(dirname "$cert_path")
    local key_dir=$(dirname "$key_path")
    
    mkdir -p "$cert_dir" "$key_dir"
    
    # Check if OpenSSL is available
    if ! command -v openssl &>/dev/null; then
        die "OpenSSL is required to create TLS certificates. Install OpenSSL first."
    fi
    
    log "Creating self-signed certificate for SPICE"
    log "Certificate: ${cert_path}"
    log "Key: ${key_path}"
    log "Validity: ${days} days"
    
    # Generate self-signed certificate
    if openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$key_path" \
        -out "$cert_path" \
        -days "$days" \
        -subj "/CN=SPICE Server" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null; then
        
        # Set proper permissions
        chmod 600 "$key_path"
        chmod 644 "$cert_path"
        
        log "✅ TLS certificate created"
        log "  Certificate: ${cert_path}"
        log "  Private Key: ${key_path}"
        log "  Expires: $(date -d "+${days} days" +%Y-%m-%d 2>/dev/null || echo "N/A")"
        log ""
        log "Use these files in spice_config:"
        log "  spice_config vm_name ${port} ${tls_port} ${cert_path} ${key_path}"
        
        return 0
    else
        die "Failed to create TLS certificate. Check OpenSSL installation."
    fi
}

# Interactive SPICE start
spice_start_interactive() {
    if ! is_interactive; then
        warn "spice_start_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Start VM with SPICE [Interactive]"
    
    list_vms
    echo ""
    
    local vm_name
    vm_name=$(ask "Enter VM name to start with SPICE" "")
    
    if [[ -z "$vm_name" ]]; then
        die "VM name is required"
    fi
    
    local port
    port=$(ask "Enter SPICE port" "${DEFAULT_SPICE_PORT}")
    
    local tls_port
    tls_port=$(ask "Enter SPICE TLS port (leave blank for no TLS)" "")
    
    local options
    options=$(ask "Enter additional SPICE options (leave blank for none)" "")
    
    spice_start "$vm_name" "$port" "$tls_port" "$options"
}

# Interactive SPICE connect
spice_connect_interactive() {
    if ! is_interactive; then
        warn "spice_connect_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Connect to SPICE Console [Interactive]"
    
    list_vms
    echo ""
    
    local vm_name
    vm_name=$(ask "Enter VM name to connect to" "")
    
    if [[ -z "$vm_name" ]]; then
        die "VM name is required"
    fi
    
    local port
    port=$(ask "Enter SPICE port (leave blank for default)" "")
    
    spice_connect "$vm_name" "$port"
}

# Interactive SPICE configuration
spice_config_interactive() {
    if ! is_interactive; then
        warn "spice_config_interactive function requires interactive mode"
        return 1
    fi
    
    heading "Configure SPICE Options [Interactive]"
    
    list_vms
    echo ""
    
    local vm_name
    vm_name=$(ask "Enter VM name to configure SPICE" "")
    
    if [[ -z "$vm_name" ]]; then
        die "VM name is required"
    fi
    
    local port
    port=$(ask "Enter SPICE port" "${DEFAULT_SPICE_PORT}")
    
    local tls_port
    tls_port=$(ask "Enter TLS port (leave blank for no TLS)" "")
    
    local use_tls
    use_tls=$(ask "Enable TLS? (yes/no)" "no")
    
    local cert_path=""
    local key_path=""
    
    if [[ "$use_tls" == "yes" ]]; then
        cert_path=$(ask "Enter path to TLS certificate (leave blank to create new)" "")
        key_path=$(ask "Enter path to TLS key (leave blank to create new)" "")
        
        if [[ -z "$cert_path" || -z "$key_path" ]]; then
            cert_path="${SPICE_CONFIG_DIR}/${vm_name}-spice.crt"
            key_path="${SPICE_CONFIG_DIR}/${vm_name}-spice.key"
            
            log "Creating new TLS certificate..."
            spice_create_tls "$cert_path" "$key_path"
        fi
    fi
    
    spice_config "$vm_name" "$port" "$tls_port" "$cert_path" "$key_path"
}

# ---------------------------------------------------------------------------
# GDB Debugging Integration Enhancement
# ---------------------------------------------------------------------------

# Start VM in debug mode
# Usage: debug_vm <vm_name> [binary_path] [port]
debug_vm() {
    local vm_name="$1"
    local binary_path="$2"
    local port="$3"
    
    heading "Starting VM in Debug Mode: ${vm_name}"
    
    ensure_vm_exists "$vm_name"
    
    # Set default port if not specified
    [[ -n "$port" ]] || port="1234"
    
    # Find VM configuration
    local config_file=$(find_vm_config_file "$vm_name")
    if [[ ! -f "$config_file" ]]; then
        die "Configuration file not found for VM: ${vm_name}"
    fi
    
    # Check if VM is already running
    if is_vm_running "$vm_name"; then
        warn "VM ${vm_name} is already running"
        return 1
    fi
    
    log "Starting VM ${vm_name} in debug mode on port ${port}"
    
    # Load configuration
    source_vm_config "$config_file"
    
    # Add debug flags
    QEMU_ARGS+=" -gdb tcp::${port} -S"
    
    # If binary path is provided, add it to GDB command
    if [[ -n "$binary_path" && -f "$binary_path" ]]; then
        log "Debug binary: ${binary_path}"
        log "To connect GDB: gdb-multiarch -ex 'target remote localhost:${port}' -ex 'file ${binary_path}'"
    else
        log "To connect GDB: gdb-multiarch -ex 'target remote localhost:${port}'"
    fi
    
    # Launch VM with debug mode
    launch_vm "$vm_name"
    
    log "✅ VM ${vm_name} started in debug mode on port ${port}"
    log "GDB can now connect to: localhost:${port}"
    
    return 0
}

# Connect GDB to a running VM
# Usage: debug_connect <vm_name> [binary_path] [port]
debug_connect() {
    local vm_name="$1"
    local binary_path="$2"
    local port="$3"
    
    heading "Connecting GDB to Running VM: ${vm_name}"
    
    ensure_vm_exists "$vm_name"
    
    # Find VM configuration to get GDB port
    local config_file=$(find_vm_config_file "$vm_name")
    
    # Try to get port from configuration or use default
    if [[ -z "$port" ]]; then
        if [[ -f "$config_file" ]]; then
            port=$(grep -E "^GDB_PORT|^DEBUG_PORT" "$config_file" | head -1 | cut -d'=' -f2)
        fi
        [[ -n "$port" ]] || port="1234"
    fi
    
    # Check if VM is running
    if ! is_vm_running "$vm_name"; then
        die "VM ${vm_name} is not running. Start it first with debug mode."
    fi
    
    # Check if port is open
    if ! nc -z localhost "$port" 2>/dev/null; then
        warn "GDB port ${port} is not open. Check if VM was started with debug mode."
        return 1
    fi
    
    log "Connecting GDB to VM ${vm_name} on port ${port}"
    
    # Build GDB command
    local gdb_cmd=(gdb-multiarch)
    
    if [[ -n "$binary_path" && -f "$binary_path" ]]; then
        gdb_cmd+=("${binary_path}")
        log "Loading binary: ${binary_path}"
    fi
    
    gdb_cmd+=(-ex "target remote localhost:${port}")
    
    # If this is a MacOS VM, add platform-specific settings
    if [[ "$config_file" == *"macos"* || "$vm_name" == *"macos"* ]]; then
        gdb_cmd+=(-ex "set architecture m68k" -ex "set m68k:split-hll on")
    fi
    
    log "Executing: ${gdb_cmd[*]}"
    log "✅ GDB connection command ready"
    log "Tip: Run '${gdb_cmd[*]}' in a separate terminal"
    
    return 0
}

# Attach GDB to a specific debug port
# Usage: debug_attach <vm_name> <port>
debug_attach() {
    local vm_name="$1"
    local port="$2"
    
    heading "Attaching GDB to VM: ${vm_name} on port ${port}"
    
    if [[ -z "$port" ]]; then
        die "Port is required. Usage: debug-attach VM_NAME PORT"
    fi
    
    ensure_vm_exists "$vm_name"
    
    # Check if VM is running
    if ! is_vm_running "$vm_name"; then
        die "VM ${vm_name} is not running"
    fi
    
    # Check if port is open
    if ! nc -z localhost "$port" 2>/dev/null; then
        die "Port ${port} is not open. Check if GDB stub is running."
    fi
    
    log "Attaching to GDB stub on localhost:${port}"
    
    # Get VM configuration to determine architecture
    local config_file=$(find_vm_config_file "$vm_name")
    local arch=""
    if [[ -f "$config_file" ]]; then
        arch=$(grep -E "^QEMU_BIN|^ARCH|^PLATFORM" "$config_file" | head -1 | cut -d'=' -f2 | tr -d 'qemu-system-' | tr -d '-softmmu')
    fi
    
    # Build architecture-specific GDB commands
    local gdb_script=$(mktemp /tmp/debug_attach_XXXXXX.gdb)
    
    echo "# GDB attach script for ${vm_name} on port ${port}" > "$gdb_script"
    echo "target remote localhost:${port}" >> "$gdb_script"
    
    # Add architecture-specific settings
    case "$arch" in
        m68k|68k) 
            echo "set architecture m68k" >> "$gdb_script"
            echo "set m68k:split-hll on" >> "$gdb_script"
            echo "set m68k:assembly-flavor att" >> "$gdb_script"
            ;;
        ppc|powerpc) 
            echo "set architecture powerpc" >> "$gdb_script"
            echo "set powerpc:vector-mode auto" >> "$gdb_script"
            ;;
        ppc64|powerpc64) 
            echo "set architecture powerpc:64" >> "$gdb_script"
            ;;
        x86_64|amd64) 
            echo "set architecture i386:x86-64" >> "$gdb_script"
            ;;
        i386|x86) 
            echo "set architecture i386" >> "$gdb_script"
            ;;
        sparc|sparc64) 
            echo "set architecture sparc${arch#sparc}" >> "$gdb_script"
            ;;
        arm|aarch64) 
            echo "set architecture arm${arch#arm}" >> "$gdb_script"
            ;;
    esac
    
    echo "continue" >> "$gdb_script"
    
    log "✅ GDB attach script created: ${gdb_script}"
    log "To attach GDB, run: gdb-multiarch -x ${gdb_script}"
    
    return 0
}

# Test GDB connection to a VM
# Usage: debug_test <vm_name> [port]
debug_test() {
    local vm_name="$1"
    local port="$2"
    
    heading "Testing GDB Connection for VM: ${vm_name}"
    
    ensure_vm_exists "$vm_name"
    
    # Get GDB port from configuration if not specified
    if [[ -z "$port" ]]; then
        local config_file=$(find_vm_config_file "$vm_name")
        if [[ -f "$config_file" ]]; then
            port=$(grep -E "^GDB_PORT|^DEBUG_PORT" "$config_file" | head -1 | cut -d'=' -f2)
        fi
        [[ -n "$port" ]] || port="1234"
    fi
    
    # Check if VM is running
    if ! is_vm_running "$vm_name"; then
        warn "VM ${vm_name} is not running. GDB connection test skipped."
        return 1
    fi
    
    # Test port connectivity
    log "Testing GDB port: ${port}"
    if nc -z localhost "$port" 2>/dev/null; then
        log "✅ Port ${port} is open and accepting connections"
        
        # Try to get VM IP for remote debugging
        if get_vm_ip "$vm_name"; then
            local vm_ip=$(get_vm_ip "$vm_name")
            log "VM IP: ${vm_ip}"
            
            if nc -z "${vm_ip}" "$port" 2>/dev/null; then
                log "✅ GDB port accessible from VM IP: ${vm_ip}:${port}"
            else
                warn "GDB port not accessible from VM IP [may be firewall]"
            fi
        fi
        
        # Show GDB connection command
        log ""
        log "GDB Connection Test Successful"
        log "To connect GDB manually:"
        log "  gdb-multiarch"
        log "  [gdb] target remote localhost:${port}"
        log "  [gdb] continue"
        
        return 0
    else
        warn "❌ Port ${port} is not open or not accepting connections"
        warn "Check if VM was started with GDB support: -gdb tcp::${port} -S"
        return 1
    fi
}

# List all active debug sessions
# Usage: debug_list [filter]
debug_list() {
    local filter="$1"
    
    heading "Active Debug Sessions"
    
    local active_debug_vms=()
    local debug_pids=()
    
    # Find VMs with active debug sessions
    local vm_dirs=()
    while IFS= read -r vm_dir; do
        [[ -d "$vm_dir" ]] && vm_dirs+=("$vm_dir")
    done < <(find "${VM_DIR}" -type d -maxdepth 1)
    
    local found_debug=false
    
    for vm_dir in "${vm_dirs[@]}"; do
        local vm_name=$(basename "$vm_dir")
        local config_file="${vm_dir}/${vm_name}.conf"
        
        if [[ ! -f "$config_file" ]]; then
            continue
        fi
        
        # Check if VM has GDB enabled
        local gdb_enabled=$(grep -i "ENABLE_GDB\|DEBUG_MODE\|GDB_PORT" "$config_file" | head -1 | cut -d'=' -f2)
        local gdb_port=$(grep -i "GDB_PORT" "$config_file" | head -1 | cut -d'=' -f2)
        
        # Check if VM is running with debug mode
        if is_vm_running "$vm_name"; then
            # Check for GDB processes
            local pid=$(get_vm_pid "$vm_name")
            if [[ -n "$pid" ]]; then
                if pgrep -P "$pid" gdb >/dev/null 2>&1; then
                    active_debug_vms+=("$vm_name")
                    debug_pids+=("$pid")
                    found_debug=true
                elif nc -z localhost "${gdb_port:-1234}" 2>/dev/null; then
                    active_debug_vms+=("$vm_name")
                    found_debug=true
                fi
            fi
        fi
    done
    
    if [[ "$found_debug" == false ]]; then
        log "No active debug sessions found"
        
        # Show VMs with debug configuration
        log ""
        log "VMs with GDB Configuration:"
        for vm_dir in "${vm_dirs[@]}"; do
            local vm_name=$(basename "$vm_dir")
            local config_file="${vm_dir}/${vm_name}.conf"
            
            if grep -qi "ENABLE_GDB\|DEBUG_MODE\|GDB_PORT" "$config_file" 2>/dev/null; then
                local gdb_port=$(grep -i "GDB_PORT" "$config_file" | head -1 | cut -d'=' -f2)
                echo "  ${vm_name} [GDB Port: ${gdb_port:-default}]"
            fi
        done
        
        return 0
    fi
    
    log "Active Debug Sessions:"
    for i in "${!active_debug_vms[@]}"; do
        local vm_name="${active_debug_vms[$i]}"
        local pid="${debug_pids[$i]}"
        local gdb_port=$(get_vm_gdb_port "$vm_name" 2>/dev/null || echo "unknown")
        
        echo "  [${i}] ${vm_name} [PID: ${pid}] [Port: ${gdb_port}]"
    done
    
    return 0
}

# Detach from debug session
# Usage: debug_detach <vm_name>
debug_detach() {
    local vm_name="$1"
    
    heading "Detaching from Debug Session: ${vm_name}"
    
    ensure_vm_exists "$vm_name"
    
    if [[ -z "$vm_name" ]]; then
        die "VM name is required. Usage: debug-detach <vm_name>"
    fi
    
    # Find GDB processes for this VM
    local gdb_pids=()
    local vm_pid=$(get_vm_pid "$vm_name")
    
    if [[ -n "$vm_pid" ]]; then
        # Find child GDB processes
        gdb_pids=($(pgrep -P "$vm_pid" gdb 2>/dev/null || true))
        
        # Also check for GDB processes that might be connected to this VM's ports
        local gdb_port=$(get_vm_gdb_port "$vm_name" 2>/dev/null || echo "1234")
        local additional_pids=($(pgrep -f "tcp::${gdb_port}\|remote localhost:${gdb_port}" 2>/dev/null || true))
        
        # Combine and unique
        gdb_pids=($(printf '%s\n' "${gdb_pids[@]}" "${additional_pids[@]}" | sort -u))
    fi
    
    if [[ ${#gdb_pids[@]} -eq 0 ]]; then
        warn "No active GDB sessions found for VM: ${vm_name}"
        return 1
    fi
    
    log "Found ${#gdb_pids[@]} GDB process for VM ${vm_name}"
    
    for pid in "${gdb_pids[@]}"; do
        if kill "$pid" 2>/dev/null; then
            log "✅ Detached GDB process: ${pid}"
        else
            warn "❌ Failed to detach GDB process: ${pid}"
        fi
    done
    
    log "✅ Debug session detached for VM: ${vm_name}"
    
    return 0
}

# Debug session management menu
debug_session_menu() {
    if ! is_interactive; then
        warn "debug_session_menu function requires interactive mode"
        return 1
    fi
    
    heading "Debug Session Management"
    
    while true; do
        echo ""
        echo "Debug Session Options:"
        echo "  [1] Start VM in debug mode"
        echo "  [2] Connect GDB to running VM"
        echo "  [3] Attach to specific debug port"
        echo "  [4] Test GDB connection"
        echo "  [5] List active debug sessions"
        echo "  [6] Detach from debug session"
        echo "  [B] Back to main menu"
        echo ""
        
        local choice
        choice=$(ask "Select option" "")
        
        case "${choice,,}" in
            1|start)
                list_vms
                local vm_num
                vm_num=$(ask "Select VM number to start in debug mode" "")
                [[ -n "${vm_num}" ]] && debug_vm "${vm_num}" || echo "No VM selected"
                ;;
            2|connect)
                list_vms
                local vm_num
                vm_num=$(ask "Select VM number to connect GDB" "")
                [[ -n "${vm_num}" ]] && debug_connect "${vm_num}" || echo "No VM selected"
                ;;
            3|attach)
                list_vms
                local vm_num
                vm_num=$(ask "Select VM number" "")
                local port
                port=$(ask "Enter debug port" "1234")
                [[ -n "${vm_num}" ]] && debug_attach "${vm_num}" "$port" || echo "No VM selected"
                ;;
            4|test)
                list_vms
                local vm_num
                vm_num=$(ask "Select VM number to test GDB connection" "")
                [[ -n "${vm_num}" ]] && debug_test "${vm_num}" || echo "No VM selected"
                ;;
            5|list) debug_list ;;
            6|detach)
                list_vms
                local vm_num
                vm_num=$(ask "Select VM number to detach from debug" "")
                [[ -n "${vm_num}" ]] && debug_detach "${vm_num}" || echo "No VM selected"
                ;;
            b|back) return 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
        
        if is_interactive; then
            read -rp "Press Enter to continue..." _
        fi
    done
}

# ---------------------------------------------------------------------------
# Retro68 Toolchain Support
# ---------------------------------------------------------------------------

# Default paths for Retro68
RETRO68_DIR="${HOME}/vm_assistant/vm_clients_3rdparty/macos/Retro68"
RETRO68_BIN="${RETRO68_DIR}/Build/Products/Release/Retro68"
RETRO68_TEST_PROJECT="${HOME}/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test"

# Check if Retro68 is installed
check_retro68() {
    if [[ -f "$RETRO68_BIN" ]]; then
        log "Retro68 found at: $RETRO68_BIN"
        "$RETRO68_BIN" --version 2>/dev/null
        return 0
    elif command -v Retro68 &>/dev/null; then
        log "Retro68 found in PATH: $(which Retro68)"
        Retro68 --version 2>/dev/null
        return 0
    else
        warn "Retro68 not found"
        return 1
    fi
}

# Install Retro68 from source
install_retro68() {
    heading "Installing Retro68 Toolchain"
    
    # Check for Xcode Command Line Tools
    if ! xcode-select -p &>/dev/null; then
        warn "Xcode Command Line Tools required for Retro68"
        log "Run: xcode-select --install"
        ask "Install Xcode Command Line Tools now?" "y" | grep -iq "y" && xcode-select --install
    fi
    
    # Clone Retro68 if not exists
    if [[ ! -d "$RETRO68_DIR" ]]; then
        log "Cloning Retro68 repository..."
        mkdir -p "${HOME}/vm_assistant/vm_clients_3rdparty/macos/"
        git clone https://github.com/automatedjdw/Retro68.git "$RETRO68_DIR" || {
            die "Failed to clone Retro68 repository"
        }
    else
        log "Retro68 repository already exists at: $RETRO68_DIR"
        ask "Pull latest changes?" "y" | grep -iq "y" && cd "$RETRO68_DIR" && git pull
    fi
    
    # Build Retro68
    log "Building Retro68..."
    cd "$RETRO68_DIR"
    xcodebuild -scheme Retro68 -configuration Release || {
        die "Failed to build Retro68. Check Xcode installation."
    }
    
    # Verify build
    if [[ -f "$RETRO68_BIN" ]]; then
        log "✅ Retro68 installed successfully: $RETRO68_BIN"
        "$RETRO68_BIN" --version
        
        # Add to PATH if user wants
        ask "Add Retro68 to PATH?" "n" | grep -iq "y" && {
            echo "export PATH=\"${RETRO68_DIR}/Build/Products/Release:\$PATH\"" >> "${HOME}/.zshrc"
            log "Added to ~/.zshrc. Run: source ~/.zshrc"
        }
        return 0
    else
        die "Retro68 build failed. Check $RETRO68_DIR/Build/Products/Release/"
    fi
}

# Setup Retro68 environment
setup_retro68_environment() {
    heading "Setting up Retro68 Development Environment"
    
    # Install Retro68 if not present
    if ! check_retro68; then
        ask "Retro68 not found. Install now?" "y" | grep -iq "y" && install_retro68
    fi
    
    # Setup project directory
    ensure_dir "${HOME}/vm_assistant/vm_clients_3rdparty/macos/"
    
    # Clone test project if not exists
    if [[ ! -d "$RETRO68_TEST_PROJECT" ]]; then
        log "Setting up MacOS71_GDB_ICMP_Test project..."
        git clone https://github.com/automatedjdw/MacOS71_GDB_ICMP_Test.git "$RETRO68_TEST_PROJECT" 2>/dev/null || {
            # If repo doesn't exist, create from local template
            log "Creating project from local template..."
            mkdir -p "$RETRO68_TEST_PROJECT/src"
            cp -r "${SCRIPT_DIR}/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test/." "$RETRO68_TEST_PROJECT/" 2>/dev/null || {
                warn "Could not setup test project. Clone manually from GitHub."
            }
        }
    else
        log "Test project already exists at: $RETRO68_TEST_PROJECT"
    fi
    
    # Check for required files
    local missing_files=()
    for file in "${RETRO68_DIR}/Build/Products/Release/Retro68" \
                 "$RETRO68_TEST_PROJECT/src/main.c" \
                 "$RETRO68_TEST_PROJECT/src/gdb_test.c" \
                 "$RETRO68_TEST_PROJECT/src/icmp_test.c" \
                 "$RETRO68_TEST_PROJECT/Makefile.retro68"; do
        [[ -f "$file" ]] || missing_files+=("$(basename "$file")")
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        warn "Missing files: ${missing_files[*]}"
        return 1
    fi
    
    log "✅ Retro68 environment setup complete"
    return 0
}

# Compile with Retro68
compile_with_retro68() {
    local project_dir="${1:-$RETRO68_TEST_PROJECT}"
    local output_name="${2:-MacOS71_GDB_ICMP_Test}"
    local target="${3:-68040}"
    local debug="${4:-y}"  # Default to debug mode
    
    heading "Compiling with Retro68"
    
    # Check Retro68 is available
    if ! check_retro68; then
        ask "Retro68 not found. Install now?" "n" | grep -iq "y" && install_retro68
        if ! check_retro68; then
            die "Retro68 required for compilation. Install it first."
        fi
    fi
    
    # Navigate to project
    if [[ ! -d "$project_dir" ]]; then
        die "Project directory not found: $project_dir"
    fi
    
    cd "$project_dir"
    
    # Build flags
    local flags=("-m${target}")
    [[ "$debug" == "y" ]] && flags+=("-g" "-O0") || flags+=("-O2")
    
    # Add include path
    [[ -d "src" ]] && flags+=("-I" "src")
    
    # Find source files
    local src_files=()
    if [[ -d "src" ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && src_files+=("$file")
        done < <(find src -name "*.c" | sort)
    else
        src_files=("*.c")
    fi
    
    if [[ ${#src_files[@]} -eq 0 ]]; then
        die "No C source files found in $project_dir"
    fi
    
    # Create build directory
    mkdir -p build
    
    log "Compiling ${#src_files[@]} files with Retro68..."
    log "Target: ${target}, Debug: ${debug}"
    
    # Compile
    Retro68 "${flags[@]}" -o "build/${output_name}" "${src_files[@]}" || {
        die "Compilation failed. Check errors above."
    }
    
    # Verify output
    if [[ -f "build/${output_name}" ]]; then
        local file_size=$(stat -f%z "build/${output_name}" 2>/dev/null || stat -c%s "build/${output_name}")
        log "✅ Compilation successful: build/${output_name} [${file_size} bytes]"
        return 0
    else
        die "Output file not created: build/${output_name}"
    fi
}

# Compile MacOS71_GDB_ICMP_Test
compile_macos71_test() {
    heading "Compiling MacOS71_GDB_ICMP_Test"
    compile_with_retro68 "$RETRO68_TEST_PROJECT" "MacOS71_GDB_ICMP_Test" "68040" "y"
}

# Debug MacOS 7.1 with Retro68
retro68_debug_workflow() {
    heading "Retro68 Debug Workflow for MacOS 7.1"
    
    # Step 1: Check environment
    log "Step 1: Checking Retro68 environment..."
    if ! check_retro68; then
        ask "Retro68 not found. Install now?" "y" | grep -iq "y" && install_retro68
    fi
    
    # Step 2: Setup project
    log "Step 2: Setting up project..."
    setup_retro68_environment
    
    # Step 3: Compile
    log "Step 3: Compiling test application..."
    compile_macos71_test
    
    # Step 4: Copy to shared directory
    log "Step 4: Copying to shared directory..."
    cp "${RETRO68_TEST_PROJECT}/build/MacOS71_GDB_ICMP_Test" "${VM_SHARED_DIR}/" || {
        warn "Failed to copy to shared directory"
    }
    
    # Step 5: Launch QEMU with GDB support
    log "Step 5: Launching QEMU with GDB support..."
    log "Run in another terminal: gdb-multiarch -ex 'target remote localhost:1234' -ex 'file ${RETRO68_TEST_PROJECT}/build/MacOS71_GDB_ICMP_Test'"
    
    # Launch QEMU with GDB
    launch_macos_68k_debug
}

# Launch MacOS 68k with GDB debugging
launch_macos_68k_debug() {
    heading "Launching MacOS 68k with GDB Debugging"
    
    # Check for ROM
    local rom_file=""
    if ls "${HOME}/vm_assistant/MacROMan/TestImages/"*.ROM 1>/dev/null 2>&1; then
        rom_file=$(ls "${HOME}/vm_assistant/MacROMan/TestImages/"*.ROM | head -1)
    elif ls "${HOME}/vm_assistant/roms/"*.ROM 1>/dev/null 2>&1; then
        rom_file=$(ls "${HOME}/vm_assistant/roms/"*.ROM | head -1)
    else
        die "No ROM file found. Place ROMs in ~/vm_assistant/MacROMan/TestImages/ or ~/vm_assistant/roms/"
    fi
    
    # Check for disk image
    local disk_file="${HOME}/vm_assistant/disks/macos71.qcow2"
    if [[ ! -f "$disk_file" ]]; then
        log "Creating disk image..."
        qemu-img create -f qcow2 "$disk_file" 5G || die "Failed to create disk image"
    fi
    
    # Check for NDRV loader
    local ndrv_loader=""
    if [[ -f "${HOME}/vm_assistant/ppc-ndrvloader" ]]; then
        ndrv_loader="${HOME}/vm_assistant/ppc-ndrvloader"
    elif [[ -f "/usr/local/share/qemu/ppc-ndrvloader" ]]; then
        ndrv_loader="/usr/local/share/qemu/ppc-ndrvloader"
    else
        # Download NDRV loader
        log "Downloading ppc-ndrvloader..."
        curl -L https://github.com/automatedjdw/qemu-macOS/raw/main/ppc-ndrvloader -o "${HOME}/vm_assistant/ppc-ndrvloader" || {
            warn "Failed to download ppc-ndrvloader. QEMU may not boot properly."
        }
        ndrv_loader="${HOME}/vm_assistant/ppc-ndrvloader"
        chmod +x "$ndrv_loader"
    fi
    
    # Launch QEMU
    local qemu_bin=$(qemu_bin_or_die "qemu-system-m68k")
    local cmd=(
        "${qemu_bin}"
        -M q800
        -m 256M
        -cpu m68040
        -bios "${rom_file}"
        -drive file="${disk_file}",format=qcow2,if=ide
        -gdb tcp::1234
        -S
        -device loader,addr=0x4000000,file="${ndrv_loader}"
        -fsdev local,security_model=mapped,id=fsdev0,path="${VM_SHARED_DIR}"
        -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare
        -prom-env "auto-boot?=true"
        -display cocoa
    )
    
    log "Running: ${cmd[*]}"
    "${cmd[@]}"
}

# Test individual Samba connection with mounting
test_samba_connection() {
    local host="$1"
    local share="$2"
    local username="$3"
    local password="$4"
    
    heading "Testing Samba Connection: smb://$host/$share"
    
    if ! command -v smbutil &>/dev/null; then
        warn "smbutil not found. Install Samba client tools."
        return 1
    fi
    
    # If username not provided and we're in interactive mode, ask for it
    if [[ -z "$username" && -z "$password" ]] && is_interactive; then
        username=$(ask "Samba username" "$(whoami)")
        password=$(ask "Samba password (leave empty if none)" "")
    fi
    
    # Test connection
    if smbutil statshares -a "$username" -p "$password" "//$host" 2>/dev/null | grep -q "$share"; then
        log "✓ Samba connection successful"
        log "✓ Share '$share' is accessible on $host"
        
        # Test mounting (if possible)
        if command -v mount_smbfs &>/dev/null; then
            local mount_point="/tmp/vm_test_samba_$$"
            mkdir -p "$mount_point"
            if [[ -n "$username" ]]; then
                if mount_smbfs -N -d 777 "//${username}@${host}/${share}" "$mount_point" 2>/dev/null; then
                    log "✓ Samba mount successful"
                    log "Contents preview:"
                    ls -la "$mount_point" | head -5
                    umount "$mount_point" 2>/dev/null || true
                    rmdir "$mount_point" 2>/dev/null || true
                    return 0
                else
                    warn "⚠️  Samba connection works but mount failed"
                    rmdir "$mount_point" 2>/dev/null || true
                    return 0
                fi
            else
                warn "⚠️  Samba connection works but no username provided for mounting"
                return 0
            fi
        else
            log "⚠️  mount_smbfs not available, but Samba connection works"
            return 0
        fi
    else
        warn "✗ Samba connection failed to $host. Check that smbd is running and the share exists."
        return 1
    fi
}

# Test individual Netatalk connection with mounting
test_netatalk_connection() {
    local host="$1"
    local share="$2"
    
    heading "Testing Netatalk [AFP] Connection: afp://$host/$share"
    
    # Method 1: Try with mount_afp
    if command -v mount_afp &>/dev/null; then
        local mount_point="/tmp/vm_test_afp_$$"
        mkdir -p "$mount_point"
        if mount_afp "afp://$host/$share" "$mount_point" 2>/dev/null; then
            log "✓ Netatalk connection successful"
            log "Mounted at: $mount_point"
            log "Contents preview:"
            ls -la "$mount_point" | head -5
            umount "$mount_point" 2>/dev/null || true
            rmdir "$mount_point" 2>/dev/null || true
            return 0
        else
            warn "✗ Netatalk mount failed with mount_afp"
            rmdir "$mount_point" 2>/dev/null || true
        fi
    else
        warn "mount_afp not found"
    fi
    
    # Method 2: Try with open command (macOS)
    if command -v open &>/dev/null; then
        log "Trying to open AFP share with default handler..."
        if open "afp://$host/$share" 2>/dev/null; then
            log "✓ Successfully opened AFP share: afp://$host/$share"
            return 0
        else
            warn "✗ Failed to open AFP share"
        fi
    fi
    
    warn "Netatalk connection test failed. Try: open afp://$host/$share manually."
    return 1
}

# Test individual SSH connection
test_ssh_connection() {
    local host="$1"
    local port="$2"
    
    heading "Testing SSH Connection: $host:$port"
    
    if ! command -v ssh &>/dev/null; then
        warn "SSH client not found. Install OpenSSH client."
        return 1
    fi
    
    log "Attempting SSH connection to $host on port $port..."
    
    if ssh -p "$port" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" echo "SSH_TEST_OK" 2>/dev/null | grep -q "SSH_TEST_OK"; then
        log "✓ SSH connection successful"
        log "✓ SSH server is responding on $host:$port"
        return 0
    else
        warn "✗ SSH connection failed to $host:$port. Check that SSH server is running and accessible."
        return 1
    fi
}

# Test GDB debug connection to a specific port
test_gdb_connection() {
    local host="${1:-localhost}"
    local port="${2:-${DEFAULT_GDB_PORT}}"
    
    heading "Testing GDB Connection: ${host}:${port}"
    
    # Check if gdb or ggdb is available
    if ! command -v gdb &>/dev/null && ! command -v ggdb &>/dev/null; then
        warn "GDB not found. Install gdb or ggdb [GNU Debugger]."
        return 1
    fi
    
    # Check if netcat is available for port testing
    if ! command -v nc &>/dev/null && ! command -v netcat &>/dev/null; then
        warn "netcat not found. Install netcat for port testing."
        return 1
    fi
    
    # Test if the port is open
    if nc -z "${host}" "${port}" 2>/dev/null; then
        log "✓ GDB port ${port} is open and accepting connections"
        log "✓ Connect with: gdb-multiarch -ex 'target remote ${host}:${port}'"
        return 0
    else
        warn "✗ GDB port ${port} is not open or not accepting connections"
        warn "Make sure QEMU is running with -gdb tcp::${port} flag"
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

# Cleanup old snapshots for a specific VM
cleanup_vm_snapshots() {
    local vm_name="$1"
    local max_age_days="${2:-30}"  # Default: 30 days
    
    heading "Cleaning up old snapshots for VM: ${vm_name}"
    
    # Find the VM directory and snapshots
    local vm_dir=""
    local snapshot_dir=""
    
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            vm_dir=$(dirname "$(dirname "${file}")")
            snapshot_dir="${vm_dir}/snapshots"
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
    
    [[ -f "${file}" ]] || die "VM config not found: ${vm_name}"
    
    if [[ ! -d "${snapshot_dir}" ]]; then
        log "No snapshots directory found for VM: ${vm_name}"
        return 0
    fi
    
    local snapshot_count=0
    local deleted_count=0
    local cutoff_date
    cutoff_date=$(date -d "${max_age_days} days ago" +%s 2>/dev/null || date -v-${max_age_days}d +%s 2>/dev/null)
    local now
    now=$(date +%s)
    
    log "Scanning snapshots in: ${snapshot_dir}"
    log "Deleting snapshots older than ${max_age_days} days..."
    
    # Find and delete old snapshot files
    while IFS= read -r -d '' snapshot_file; do
        [[ -f "${snapshot_file}" ]] || continue
        
        local file_date
        file_date=$(stat -f "%m" "${snapshot_file}" 2>/dev/null || stat -c "%Y" "${snapshot_file}" 2>/dev/null)
        
        if [[ -n "${file_date}" && ${file_date} -lt ${cutoff_date} ]]; then
            local snapshot_name=$(basename "${snapshot_file}")
            if rm "${snapshot_file}"; then
                log "✓ Deleted old snapshot: ${snapshot_name}"
                deleted_count=$((deleted_count + 1))
            else
                warn "✗ Failed to delete: ${snapshot_name}"
            fi
        fi
        
        snapshot_count=$((snapshot_count + 1))
    done < <(find "${snapshot_dir}" -type f \( -name "*.conf" -o -name "*.qcow2" \) -print0 2>/dev/null)
    
    log "Snapshot cleanup complete for ${vm_name}: ${deleted_count} of ${snapshot_count} snapshots deleted"
    
    return 0
}

# Cleanup all VM snapshots
cleanup_all_snapshots() {
    local max_age_days="${1:-30}"
    local all_vms=()
    
    heading "Cleaning up all VM snapshots [older than ${max_age_days} days]"
    
    # Find all VM config files
    while IFS= read -r -d '' file; do
        all_vms+=("$(basename "$file" .conf)")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null)
    
    if [[ ${#all_vms[@]} -eq 0 ]]; then
        log "No VMs found"
        return 0
    fi
    
    log "Found ${#all_vms[@]} VMs to check"
    
    local total_deleted=0
    for vm in "${all_vms[@]}"; do
        log "Cleaning up snapshots for: ${vm}"
        if cleanup_vm_snapshots "${vm}" "${max_age_days}"; then
            : # Success
        else
            warn "Failed to cleanup snapshots for: ${vm}"
        fi
    done
    
    log "✅ All VM snapshot cleanup complete"
    return 0
}

# Find and remove unused disk images
cleanup_unused_disks() {
    local dry_run="${1:-true}"  # Default to dry run for safety
    
    heading "Finding Unused Disk Images"
    
    if [[ "${dry_run}" == "true" ]]; then
        log "DRY RUN: No disks will actually be deleted"
        log "Add --force to actually delete unused disks"
    fi
    
    # Find all disk images
    local all_disks=()
    while IFS= read -r -d '' disk; do
        all_disks+=("${disk}")
    done < <(find "${VM_IMAGE_DIR}" -name "*.qcow2" -print0 2>/dev/null)
    
    if [[ ${#all_disks[@]} -eq 0 ]]; then
        log "No disk images found in ${VM_IMAGE_DIR}"
        return 0
    fi
    
    log "Found ${#all_disks[@]} disk images"
    
    # Find all disks referenced in VM configurations
    local used_disks=()
    while IFS= read -r -d '' config_file; do
        while IFS= read -r line; do
            [[ "${line}" =~ HDD_IMAGE=|CDROM_IMAGE= ]] || continue
            local disk_path="${line#*=}"
            disk_path=$(trim "${disk_path}")
            disk_path=$(echo "${disk_path}" | sed 's/^"//;s/"$//')
            used_disks+=("${disk_path}")
        done < "${config_file}"
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null)
    
    log "Found ${#used_disks[@]} disk references in VM configurations"
    
    # Find unused disks
    local unused_disks=()
    local deleted_count=0
    
    for disk in "${all_disks[@]}"; do
        local is_used=false
        for used_disk in "${used_disks[@]}"; do
            if [[ "${disk}" == "${used_disk}" ]]; then
                is_used=true
                break
            fi
        done
        
        if [[ "${is_used}" == "false" ]]; then
            unused_disks+=("${disk}")
            if [[ "${dry_run}" == "false" ]]; then
                if rm "${disk}"; then
                    log "✓ Deleted unused disk: $(basename "${disk}")"
                    deleted_count=$((deleted_count + 1))
                else
                    warn "✗ Failed to delete: $(basename "${disk}")"
                fi
            else
                warn "  DRY RUN: Would delete unused disk: $(basename "${disk}")"
            fi
        fi
    done
    
    if [[ "${dry_run}" == "true" ]]; then
        log "DRY RUN: Would delete ${#unused_disks[@]} unused disks"
        log "To actually delete them, run: ${SCRIPT_NAME} cleanup-disks --force"
    else
        log "✅ Deleted ${deleted_count} unused disk images"
    fi
    
    return 0
}

# Cleanup temporary files and cache
cleanup_temp_files() {
    heading "Cleaning up Temporary Files and Cache"
    
    local cleanup_paths=(
        "${VM_SHARED_DIR}/.DS_Store"
        "${VM_SHARED_DIR}/.*~"
        "${VM_SHARED_DIR}/*.tmp"
        "${VM_SHARED_DIR}/*.temp"
        "${CONFIG_DIR}/.DS_Store"
        "${VM_LOG_DIR}/*.log.*"
    )
    
    local total_deleted=0
    
    for pattern in "${cleanup_paths[@]}"; do
        while IFS= read -r -d '' file; do
            if [[ "${dry_run:-false}" == "true" ]]; then
                log "  DRY RUN: Would delete: ${file}"
            else
                if rm -f "${file}"; then
                    log "✓ Deleted: ${file}"
                    total_deleted=$((total_deleted + 1))
                else
                    warn "✗ Failed to delete: ${file}"
                fi
            fi
        done < <(find $(dirname "${pattern}") -name "$(basename "${pattern}")" -print0 2>/dev/null)
    done
    
    # Clean up .bak files (backup files from sed -i)
    if find "${VM_DIR}" -name "*.bak" -print0 2>/dev/null | grep -q .; then
        local bak_files
        while IFS= read -r -d '' file; do
            if [[ "${dry_run:-false}" == "true" ]]; then
                log "  DRY RUN: Would delete backup: ${file}"
            else
                if rm -f "${file}"; then
                    log "✓ Deleted backup: ${file}"
                    total_deleted=$((total_deleted + 1))
                else
                    warn "✗ Failed to delete backup: ${file}"
                fi
            fi
        done < <(find "${VM_DIR}" -name "*.bak" -print0 2>/dev/null)
    fi
    
    log "✅ Temporary file cleanup complete: ${total_deleted} files deleted"
    return 0
}

# Cleanup menu
cleanup_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "cleanup_menu function requires interactive mode"
        return 1
    fi
    
    while true; do
        clear || echo ""
        heading "Cleanup & Maintenance Menu"
        
        echo "Cleanup Options:"
        echo "  [1] Cleanup old snapshots for a specific VM"
        echo "  [2] Cleanup old snapshots for all VMs"
        echo "  [3] Find and remove unused disk images [DRY RUN]"
        echo "  [4] Remove unused disk images [ACTUAL DELETE]"
        echo "  [5] Cleanup temporary files"
        echo "  [6] Run all cleanup operations [DRY RUN]"
        echo ""
        echo "  [B] Back to main menu"
        echo ""
        
        choice=$(ask "Select cleanup option" "")
        
        case "${choice,,}" in
            1)
                list_vms || continue
                local vm_num
                vm_num=$(ask "Select VM number to cleanup snapshots" "")
                
                # Get VM name from selection
                local vm_confs=()
                while IFS= read -r -d '' vm_conf; do
                    vm_confs+=("${vm_conf}")
                done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
                
                local i=0
                local selected_vm=""
                for vm_conf in "${vm_confs[@]}"; do
                    [[ -f "${vm_conf}" ]] && {
                        if [[ $i -eq $vm_num ]]; then
                            selected_vm=$(basename "${vm_conf}" .conf)
                            break
                        fi
                        ((i++)) || true
                    }
                done
                
                if [[ -n "${selected_vm}" ]]; then
                    local max_age
                    max_age=$(ask "Maximum snapshot age in days (default: 30)" "30")
                    cleanup_vm_snapshots "${selected_vm}" "${max_age}"
                else
                    warn "Invalid VM selection"
                fi
                ;;
            2)
                local max_age
                max_age=$(ask "Maximum snapshot age in days (default: 30)" "30")
                cleanup_all_snapshots "${max_age}"
                ;;
            3)
                cleanup_unused_disks true  # Dry run
                ;;
            4)
                local confirm
                confirm=$(ask "Are you sure you want to DELETE unused disk images? (y/n)" "n")
                if [[ "${confirm}" == "y" ]]; then
                    cleanup_unused_disks false  # Actual delete
                else
                    log "Cleanup cancelled"
                fi
                ;;
            5)
                cleanup_temp_files
                ;;
            6)
                log "Running all cleanup operations [DRY RUN]...""
                cleanup_all_snapshots
                cleanup_unused_disks true
                cleanup_temp_files
                log "All cleanup operations complete [DRY RUN]""
                ;;
            b|back)
                return 0
                ;;
            *)
                warn "Invalid option. Please try again."
                ;;
        esac
        
        if is_interactive; then
            read -rp "Press Enter to continue..." _
        fi
    done
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
    echo "[1] Local share ${volatile_hd}...""
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

# Test local share directory functionality
test_local_share() {
    heading "Testing Local Share Directory"
    
    ensure_dir "${VM_SHARED_DIR}"
    
    local results=()
    local success=true
    
    # Test 1: Directory exists
    echo "[1] Directory existence..."
    if [[ -d "${VM_SHARED_DIR}" ]]; then
        log "✓ Share directory exists: ${VM_SHARED_DIR}"
        results+=("✓ Share directory exists")
    else
        warn "✗ Share directory does not exist"
        results+=("✗ Share directory does not exist")
        success=false
    fi
    
    # Test 2: Write permissions
    echo ""
    echo "[2] Write permissions..."
    if [[ -w "${VM_SHARED_DIR}" ]]; then
        log "✓ Write permissions: OK"
        results+=("✓ Write permissions: OK")
    else
        warn "✗ Write permissions: FAILED"
        warn "Fix with: sudo chmod u+rwx ${VM_SHARED_DIR}"
        results+=("✗ Write permissions: FAILED")
        success=false
    fi
    
    # Test 3: Read permissions
    echo ""
    echo "[3] Read permissions..."
    if [[ -r "${VM_SHARED_DIR}" ]]; then
        log "✓ Read permissions: OK"
        results+=("✓ Read permissions: OK")
    else
        warn "✗ Read permissions: FAILED"
        warn "Fix with: sudo chmod u+rx ${VM_SHARED_DIR}"
        results+=("✗ Read permissions: FAILED")
        success=false
    fi
    
    # Test 4: File creation
    echo ""
    echo "[4] File creation test..."
    local test_file="${VM_SHARED_DIR}/.vm_test_$$"
    if touch "${test_file}" 2>/dev/null; then
        log "✓ File creation: OK"
        results+=("✓ File creation: OK")
        rm -f "${test_file}"
    else
        warn "✗ File creation: FAILED"
        results+=("✗ File creation: FAILED")
        success=false
    fi
    
    # Test 5: Disk usage
    echo ""
    echo "[5] Disk usage..."
    local disk_usage
    disk_usage=$(df -h "${VM_SHARED_DIR}" 2>/dev/null | tail -1 | awk '{print $4}')
    if [[ -n "${disk_usage}" ]]; then
        log "Available space: ${disk_usage}"
        results+=("✓ Available space: ${disk_usage}")
    else
        warn "✗ Could not determine disk usage"
        results+=("✗ Could not determine disk usage")
        success=false
    fi
    
    # Test 6: List all share directories
    echo ""
    echo "[6] All share directories:"
    local all_dirs=("${VM_SHARED_DIR}" "${VM_DIR}" "${IMAGES_DIR}" "${ROM_DIR}")
    for dir in "${all_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            local dir_size
            dir_size=$(du -sh "${dir}" 2>/dev/null | cut -f1)
            log "  ✓ ${dir} (${dir_size})"
        else
            warn "  ✗ ${dir} (not found)"
            success=false
        fi
    done
    
    # Summary
    echo ""
    heading "Share Directory Test Summary"
    for result in "${results[@]}"; do
        echo "  ${result}"
    done
    
    if ${success}; then
        log "✅ All share directory tests passed"
        return 0
    else
        warn "❌ Some share directory tests failed"
        return 1
    fi
}

# List all configured shares and directories
list_shares() {
    heading "List of Configured Shares and Directories"
    
    echo ""
    echo "=== Network Shares (Samba/Netatalk) ==="
    
    # Test Samba shares
    if command -v smbclient &>/dev/null; then
        echo "Samba shares:"
        if smbclient -g -L localhost 2>/dev/null | grep -E "VM_|Shares" | head -5; then
            : # Shares were listed
        else
            echo "  No Samba shares found or Samba not configured"
        fi
    else
        echo "  Samba client not installed"
    fi
    
    echo ""
    
    # Test Netatalk shares
    if command -v afpclient &>/dev/null; then
        echo "Netatalk shares:"
        if afpclient -l localhost 2>/dev/null | grep -v "afp" | head -5; then
            : # Shares were listed
        else
            echo "  No Netatalk shares found or Netatalk not configured"
        fi
    else
        echo "  Netatalk client not installed"
    fi
    
    echo ""
    echo "=== Local Directories ==="
    
    # List all VM assistant directories
    local all_dirs=("${VM_SHARED_DIR}" "${VM_DIR}" "${IMAGES_DIR}" "${ROM_DIR}" "${VM_LOG_DIR}" "${CONFIG_DIR}")
    for dir in "${all_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            local dir_size
            dir_size=$(du -sh "${dir}" 2>/dev/null | cut -f1)
            local file_count
            file_count=$(find "${dir}" -type f 2>/dev/null | wc -l)
            echo "  ✓ ${dir} (${dir_size}, ${file_count} files)"
        else
            echo "  ✗ ${dir} (not found)"
        fi
    done
    
    # List recent files in key directories
    echo ""
    echo "=== Recent Files ==="
    for dir in "${VM_SHARED_DIR}" "${IMAGES_DIR}"; do
        if [[ -d "${dir}" ]]; then
            echo "${dir}:"
            find "${dir}" -type f -name "*.iso" -o -name "*.qcow2" -o -name "*.img" 2>/dev/null | sort | tail -3 | sed 's/^/  /' || echo "  No image files found"
        fi
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
    
    ensure_dir "${IMAGES_DIR}"
    
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
    
    local output_file="${IMAGES_DIR}/${iso_name}"
    
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

# Detect available Images across multiple directories
detect_available_images() {
    heading "Detecting Available Images"
    
    local search_dirs=(
        "${IMAGES_DIR}"
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

# Detect available ROM files across all directories
detect_available_roms() {
    heading "Detecting Available ROM Files"
    
    local search_dirs=(
        "${ROM_DIR}"
        "${CONFIG_DIR}"
        "${SCRIPT_DIR}/roms"
        "${HOME}/vm_assistant/roms"
        "/usr/local/share/qemu"
        "/opt/local/share/qemu"
    )
    
    local global_available_roms=()
    local global_available_roms_paths=()
    
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log "Scanning: ${dir}"
            while IFS= read -r -d "" file; do
                case "$file" in
                    *.rom|*.ROM|*.bin|*.BIN)
                        local filename=$(basename "$file")
                        local size=$(du -h "$file" 2>/dev/null | cut -f1)
                        local description="$filename ($size)"
                        
                        # Detect ROM type by filename
                        case "$filename" in
                            *mac99*|*Mac99*|*mac.*|*Mac.*) 
                                description="[Mac] $filename ($size)" ;;
                            *ppc*|*PPC*|*powerpc*) 
                                description="[PPC] $filename ($size)" ;;
                            *68k*|*m68k*|*M68K*) 
                                description="[68k] $filename ($size)" ;;
                            *vga*|*VGA*|*video*) 
                                description="[VGA] $filename ($size)" ;;
                            *bios*|*BIOS*|*efi*|*EFI*) 
                                description="[BIOS] $filename ($size)" ;;
                            *pflash*|*PFLASH*) 
                                description="[PFLASH] $filename ($size)" ;;
                            *openbios*|*OpenBIOS*) 
                                description="[OpenBIOS] $filename ($size)" ;;
                            *sgabios*|*SGABIOS*) 
                                description="[SeaBIOS] $filename ($size)" ;;
                            *vgabios*|*VGABIOS*) 
                                description="[VGABIOS] $filename ($size)" ;;
                            *)
                                description="[Unknown] $filename ($size)" ;;
                        esac
                        
                        global_available_roms+=("$description")
                        global_available_roms_paths+=("$file")
                        ;;
                esac
            done < <(find "$dir" -type f \( -name "*.rom" -o -name "*.ROM" -o -name "*.bin" -o -name "*.BIN" \) -print0 2>/dev/null)
        fi
    done
    
    if [[ ${#global_available_roms_paths[@]} -eq 0 ]]; then
        warn "No ROM files found in any of the scanned directories"
        log "Try placing ROM files in: ${ROM_DIR}"
        return 1
    else
        log "Found ${#global_available_roms_paths[@]} ROM file(s):"
        for i in "${!global_available_roms_paths[@]}"; do
            log "  [$((i+1))] ${global_available_roms[$i]}"
        done
        return 0
    fi
}

# ---------------------------------------------------------------------------
# Snapshot Management Functions
# ---------------------------------------------------------------------------

# Create a snapshot of a VM
create_vm_snapshot() {
    local vm_name="$1"
    local snapshot_name="$2"
    
    heading "Creating Snapshot for VM: ${vm_name}"
    
    # Find the VM directory
    local vm_dir=""
    local config_file=""
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            config_file="$file"
            vm_dir=$(dirname "$(dirname "${config_file}")")
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
    
    [[ -f "${config_file}" ]] || die "VM not found: ${vm_name}"
    
    # Create snapshot directory if it doesn't exist
    local snapshot_dir="${vm_dir}/snapshots"
    ensure_dir "${snapshot_dir}"
    
    # Generate timestamp
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_prefix="${snapshot_name:-snapshot-${timestamp}}"
    local snapshot_base="${snapshot_dir}/${snapshot_prefix}"
    
    # Snapshot configuration
    if [[ -f "${config_file}" ]]; then
        cp "${config_file}" "${snapshot_base}.conf"
        log "Configuration snapshot: ${snapshot_base}.conf"
    fi
    
    # Snapshot disk images (qcow2 format supports snapshots)
    local disk_dir="${vm_dir}/qcow2"
    if [[ -d "${disk_dir}" ]]; then
        for disk in "${disk_dir}"/*.qcow2; do
            [[ -f "${disk}" ]] || continue
            local disk_name=$(basename "${disk}")
            local snapshot_disk="${snapshot_base}-${disk_name}"
            
            log "Creating snapshot of ${disk_name}..."
            if qemu-img snapshot -c "${snapshot_prefix}" "${disk}" 2>/dev/null; then
                log "✓ Internal snapshot created for ${disk_name}"
            else
                # Fallback: create copy
                cp "${disk}" "${snapshot_disk}"
                log "✓ Disk copy snapshot: ${snapshot_disk}"
            fi
        done
    fi
    
    log "✅ Snapshot '${snapshot_prefix}' created for VM '${vm_name}'"
    return 0
}

# List snapshots for a VM
list_vm_snapshots() {
    local vm_name="$1"
    
    heading "Listing Snapshots for VM: ${vm_name}"
    
    # Find the VM directory
    local vm_dir=""
    local config_file=""
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            config_file="$file"
            vm_dir=$(dirname "$(dirname "${config_file}")")
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
    
    [[ -f "${config_file}" ]] || die "VM not found: ${vm_name}"
    
    local snapshot_dir="${vm_dir}/snapshots"
    
    if [[ ! -d "${snapshot_dir}" ]]; then
        log "No snapshots found for VM: ${vm_name}"
        return 0
    fi
    
    # List configuration snapshots
    local conf_snapshots=()
    while IFS= read -r -d '' conf_file; do
        [[ "${conf_file}" == *.conf ]] && conf_snapshots+=("${conf_file}")
    done < <(find "${snapshot_dir}" -name "*.conf" -print0 2>/dev/null | sort -z)
    
    # List disk snapshots
    local disk_snapshots=()
    while IFS= read -r -d '' disk_file; do
        [[ "${disk_file}" == *.qcow2 ]] && disk_snapshots+=("${disk_file}")
    done < <(find "${snapshot_dir}" -name "*.qcow2" -print0 2>/dev/null | sort -z)
    
    if [[ ${#conf_snapshots[@]} -eq 0 && ${#disk_snapshots[@]} -eq 0 ]]; then
        log "No snapshots found for VM: ${vm_name}"
        return 0
    fi
    
    echo "Configuration Snapshots:"
    for conf in "${conf_snapshots[@]}"; do
        local name=$(basename "${conf}" .conf)
        local size=$(du -h "${conf}" 2>/dev/null | cut -f1)
        log "  - ${name} (config, ${size})"
    done
    
    echo "Disk Snapshots:"
    for disk in "${disk_snapshots[@]}"; do
        local name=$(basename "${disk}")
        local size=$(du -h "${disk}" 2>/dev/null | cut -f1)
        log "  - ${name} (disk, ${size})"
    done
    
    return 0
}

# Restore a VM snapshot
restore_vm_snapshot() {
    local vm_name="$1"
    local snapshot_name="$2"
    
    heading "Restoring Snapshot: ${snapshot_name} for VM: ${vm_name}"
    
    # Find the VM directory
    local vm_dir=""
    local config_file=""
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            config_file="$file"
            vm_dir=$(dirname "$(dirname "${config_file}")")
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
    
    [[ -f "${config_file}" ]] || die "VM not found: ${vm_name}"
    
    local snapshot_dir="${vm_dir}/snapshots"
    local snapshot_conf="${snapshot_dir}/${snapshot_name}.conf"
    
    if [[ ! -f "${snapshot_conf}" ]]; then
        die "Snapshot not found: ${snapshot_name}.conf"
    fi
    
    # Confirm restoration
    if is_interactive; then
        local confirm=$(ask "Restore snapshot '${snapshot_name}'? This will overwrite current VM configuration." "no")
        if [[ "${confirm}" != "yes" && "${confirm}" != "y" ]]; then
            log "Snapshot restoration cancelled."
            return 0
        fi
    fi
    
    # Backup current configuration
    local backup_dir="${vm_dir}/backups"
    ensure_dir "${backup_dir}"
    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    cp "${config_file}" "${backup_dir}/$(basename "${config_file}" .conf)-${backup_timestamp}.conf"
    log "Current configuration backed up to: ${backup_dir}/"
    
    # Restore configuration
    cp "${snapshot_conf}" "${config_file}"
    log "✓ Configuration restored from snapshot"
    
    # Restore disk snapshots (if they exist)
    local disk_dir="${vm_dir}/qcow2"
    ensure_dir "${disk_dir}"
    
    local snapshot_disk_pattern="${snapshot_dir}/${snapshot_name}-*.qcow2"
    for snapshot_disk in ${snapshot_disk_pattern}; do
        [[ -f "${snapshot_disk}" ]] || continue
        local disk_name=$(basename "${snapshot_disk}" | sed "s/${snapshot_name}-//")
        local target_disk="${disk_dir}/${disk_name}"
        
        cp "${snapshot_disk}" "${target_disk}"
        log "✓ Disk restored: ${disk_name}"
    done
    
    log "✅ Snapshot '${snapshot_name}' restored for VM '${vm_name}'"
    return 0
}

# Delete a VM snapshot
delete_vm_snapshot() {
    local vm_name="$1"
    local snapshot_name="$2"
    
    heading "Deleting Snapshot: ${snapshot_name} for VM: ${vm_name}"
    
    # Find the VM directory
    local vm_dir=""
    local config_file=""
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file" .conf)" == "${vm_name}" ]]; then
            config_file="$file"
            vm_dir=$(dirname "$(dirname "${config_file}")")
            break
        fi
    done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
    
    [[ -f "${config_file}" ]] || die "VM not found: ${vm_name}"
    
    local snapshot_dir="${vm_dir}/snapshots"
    local snapshot_conf="${snapshot_dir}/${snapshot_name}.conf"
    
    if [[ ! -f "${snapshot_conf}" ]]; then
        die "Snapshot not found: ${snapshot_name}.conf"
    fi
    
    # Confirm deletion
    if is_interactive; then
        local confirm=$(ask "Delete snapshot '${snapshot_name}'?" "no")
        if [[ "${confirm}" != "yes" && "${confirm}" != "y" ]]; then
            log "Snapshot deletion cancelled."
            return 0
        fi
    fi
    
    # Delete configuration snapshot
    rm -f "${snapshot_conf}"
    log "Configuration snapshot deleted: ${snapshot_conf}"
    
    # Delete disk snapshots
    local snapshot_disk_pattern="${snapshot_dir}/${snapshot_name}-*.qcow2"
    for snapshot_disk in ${snapshot_disk_pattern}; do
        [[ -f "${snapshot_disk}" ]] || continue
        rm -f "${snapshot_disk}"
        log "Disk snapshot deleted: ${snapshot_disk}"
    done
    
    log "✅ Snapshot '${snapshot_name}' deleted for VM '${vm_name}'"
    return 0
}

# Snapshot management menu
snapshot_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "snapshot_menu function requires interactive mode"
        return 1
    fi
    
    heading "VM Snapshot Management"
    list_vms
    vm_num=$(ask "Select VM number for snapshot management" "")
    
    # Get all VM config files from vms/VM_NAME_PLATFORM/conf/
    local vm_confs=()
    while IFS= read -r -d '' vm_conf; do
        vm_confs+=("$vm_conf")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    local i=0
    local vm_name=""
    for vm_conf in "${vm_confs[@]}"; do
        [[ -f "${vm_conf}" ]] && {
            if [[ $i -eq $vm_num ]]; then
                vm_name=$(basename "${vm_conf}" .conf)
                break
            fi
            ((i++)) || true
        }
    done
    
    if [[ -z "$vm_name" ]]; then
        warn "Invalid VM selection"
        return 1
    fi
    
    # Snapshot submenu
    while true; do
        clear || echo ""
        heading "Snapshot Management for VM: ${vm_name}"
        echo ""
        echo "  [1] Create snapshot"
        echo "  [2] List snapshots"
        echo "  [3] Restore snapshot"
        echo "  [4] Delete snapshot"
        echo "  [B] Back to main menu"
        echo ""
        
        choice=$(ask "Select snapshot operation" "")
        
        case "${choice,,}" in
            1|create)
                snapshot_name=$(ask "Enter snapshot name (or press Enter for timestamp-based name)" "")
                create_vm_snapshot "${vm_name}" "${snapshot_name}"
                ;;
            2|list)
                list_vm_snapshots "${vm_name}"
                ;;
            3|restore)
                list_vm_snapshots "${vm_name}"
                snapshot_name=$(ask "Enter snapshot name to restore" "")
                if [[ -n "${snapshot_name}" ]]; then
                    restore_vm_snapshot "${vm_name}" "${snapshot_name}"
                else
                    warn "No snapshot name provided"
                fi
                ;;
            4|delete)
                list_vm_snapshots "${vm_name}"
                snapshot_name=$(ask "Enter snapshot name to delete" "")
                if [[ -n "${snapshot_name}" ]]; then
                    delete_vm_snapshot "${vm_name}" "${snapshot_name}"
                else
                    warn "No snapshot name provided"
                fi
                ;;
            b|back)
                return 0
                ;;
            *)
                warn "Invalid option. Please try again."
                ;;
        esac
        
        if is_interactive; then
            read -rp "Press Enter to continue..." _
        fi
    done
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

# ---------------------------------------------------------------------------
# VM Export/Import Functions (Various Formats)
# ---------------------------------------------------------------------------

# Export VM to QCOW2 format (native QEMU format)
export_vm_qcow2() {
    local vm_name="$1"
    local output_path="$2"
    
    heading "Exporting VM to QCOW2 format: ${vm_name}"
    
    # Find VM directory
    local vm_dir=""
    while IFS= read -r -d '' dir; do
        if [[ -f "${dir}/${vm_name}.conf" ]]; then
            vm_dir="${dir}"
            break
        fi
    done < <(find "${CONFIG_DIR}" -type d -print0 2>/dev/null)
    
    [[ -d "${vm_dir}" ]] || die "VM directory not found: ${vm_name}"
    
    # Default output path
    [[ -z "${output_path}" ]] && output_path="${vm_dir}/../${vm_name}.qcow2"
    
    # Find all disk images for this VM
    local disk_files=()
    while IFS= read -r -d '' disk_file; do
        [[ "${disk_file}" == *.qcow2 || "${disk_file}" == *.qcow || "${disk_file}" == *.img ]] && disk_files+=("${disk_file}")
    done < <(find "${vm_dir}/qcow2" -type f -print0 2>/dev/null)
    
    if [[ ${#disk_files[@]} -eq 0 ]]; then
        die "No disk images found in ${vm_dir}/qcow2"
    fi
    
    # For simplicity, export the first disk (can be enhanced to handle multiple)
    local source_disk="${disk_files[0]}"
    
    if [[ -f "${source_disk}" ]]; then
        log "Converting ${source_disk} to ${output_path}"
        qemu-img convert -f qcow2 -O qcow2 "${source_disk}" "${output_path}" || {
            die "Failed to convert disk image"
        }
        log "✅ VM exported to QCOW2: ${output_path}"
        return 0
    else
        die "Source disk not found: ${source_disk}"
    fi
}

# Export VM to VMDK format (VMware compatible)
export_vm_vmdk() {
    local vm_name="$1"
    local output_path="$2"
    
    heading "Exporting VM to VMDK format: ${vm_name}"
    
    # Find VM directory
    local vm_dir=""
    while IFS= read -r -d '' dir; do
        if [[ -f "${dir}/${vm_name}.conf" ]]; then
            vm_dir="${dir}"
            break
        fi
    done < <(find "${CONFIG_DIR}" -type d -print0 2>/dev/null)
    
    [[ -d "${vm_dir}" ]] || die "VM directory not found: ${vm_name}"
    
    # Default output path
    [[ -z "${output_path}" ]] && output_path="${vm_dir}/../${vm_name}.vmdk"
    
    # Find all disk images for this VM
    local disk_files=()
    while IFS= read -r -d '' disk_file; do
        [[ "${disk_file}" == *.qcow2 || "${disk_file}" == *.qcow || "${disk_file}" == *.img ]] && disk_files+=("${disk_file}")
    done < <(find "${vm_dir}/qcow2" -type f -print0 2>/dev/null)
    
    if [[ ${#disk_files[@]} -eq 0 ]]; then
        die "No disk images found in ${vm_dir}/qcow2"
    fi
    
    # For simplicity, export the first disk
    local source_disk="${disk_files[0]}"
    
    log "Converting ${source_disk} to VMDK: ${output_path}"
    qemu-img convert -O vmdk "${source_disk}" "${output_path}" || {
        die "Failed to convert to VMDK format"
    }
    log "✅ VM exported to VMDK: ${output_path}"
    log "Note: VMDK may need to be fixed with: vmware-vdiskmanager -r source.vmdk fixed.vmdk"
    return 0
}

# Export VM to VDI format (VirtualBox compatible)
export_vm_vdi() {
    local vm_name="$1"
    local output_path="$2"
    
    heading "Exporting VM to VDI format: ${vm_name}"
    
    # Find VM directory
    local vm_dir=""
    while IFS= read -r -d '' dir; do
        if [[ -f "${dir}/${vm_name}.conf" ]]; then
            vm_dir="${dir}"
            break
        fi
    done < <(find "${CONFIG_DIR}" -type d -print0 2>/dev/null)
    
    [[ -d "${vm_dir}" ]] || die "VM directory not found: ${vm_name}"
    
    # Default output path
    [[ -z "${output_path}" ]] && output_path="${vm_dir}/../${vm_name}.vdi"
    
    # Find all disk images for this VM
    local disk_files=()
    while IFS= read -r -d '' disk_file; do
        [[ "${disk_file}" == *.qcow2 || "${disk_file}" == *.qcow || "${disk_file}" == *.img ]] && disk_files+=("${disk_file}")
    done < <(find "${vm_dir}/qcow2" -type f -print0 2>/dev/null)
    
    if [[ ${#disk_files[@]} -eq 0 ]]; then
        die "No disk images found in ${vm_dir}/qcow2"
    fi
    
    # For simplicity, export the first disk
    local source_disk="${disk_files[0]}"
    
    log "Converting ${source_disk} to VDI: ${output_path}"
    qemu-img convert -O vdi "${source_disk}" "${output_path}" || {
        die "Failed to convert to VDI format"
    }
    log "✅ VM exported to VDI: ${output_path}"
    return 0
}

# Export VM to RAW format
export_vm_raw() {
    local vm_name="$1"
    local output_path="$2"
    
    heading "Exporting VM to RAW format: ${vm_name}"
    
    # Find VM directory
    local vm_dir=""
    while IFS= read -r -d '' dir; do
        if [[ -f "${dir}/${vm_name}.conf" ]]; then
            vm_dir="${dir}"
            break
        fi
    done < <(find "${CONFIG_DIR}" -type d -print0 2>/dev/null)
    
    [[ -d "${vm_dir}" ]] || die "VM directory not found: ${vm_name}"
    
    # Default output path
    [[ -z "${output_path}" ]] && output_path="${vm_dir}/../${vm_name}.raw"
    
    # Find all disk images for this VM
    local disk_files=()
    while IFS= read -r -d '' disk_file; do
        [[ "${disk_file}" == *.qcow2 || "${disk_file}" == *.qcow || "${disk_file}" == *.img ]] && disk_files+=("${disk_file}")
    done < <(find "${vm_dir}/qcow2" -type f -print0 2>/dev/null)
    
    if [[ ${#disk_files[@]} -eq 0 ]]; then
        die "No disk images found in ${vm_dir}/qcow2"
    fi
    
    # For simplicity, export the first disk
    local source_disk="${disk_files[0]}"
    
    log "Converting ${source_disk} to RAW: ${output_path}"
    qemu-img convert -O raw "${source_disk}" "${output_path}" || {
        die "Failed to convert to RAW format"
    }
    log "✅ VM exported to RAW: ${output_path}"
    log "Warning: RAW format can be very large and doesn't support snapshots"
    return 0
}

# Export VM menu (interactive)
export_vm_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "export_vm_menu function requires interactive mode"
        return 1
    fi
    
    list_vms || return 1
    local vm_num
    vm_num=$(ask "Select VM number to export" "")
    
    if [[ -n "$vm_num" && "$vm_num" =~ ^[0-9]+$ ]]; then
        local vm_confs=()
        while IFS= read -r -d '' vm_conf; do
            vm_confs+=("$vm_conf")
        done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
        
        if [[ $vm_num -ge 1 && $vm_num -le ${#vm_confs[@]} ]]; then
            local selected_vm=$(basename "${vm_confs[$((vm_num-1))]}" .conf)
            
            echo ""
            echo "Export Format Options:"
            echo "  [1] QCOW2 (QEMU native, recommended)"
            echo "  [2] VMDK (VMware compatible)"
            echo "  [3] VDI (VirtualBox compatible)"
            echo "  [4] RAW (Uncompressed, universal)"
            echo ""
            
            local format_choice
            format_choice=$(ask "Select export format" "1")
            
            case "${format_choice}" in
                1) export_vm_qcow2 "${selected_vm}" ;;
                2) export_vm_vmdk "${selected_vm}" ;;
                3) export_vm_vdi "${selected_vm}" ;;
                4) export_vm_raw "${selected_vm}" ;;
                *) warn "Invalid format selection" ;;
            esac
        fi
    fi
}

# Import VM from foreign format
import_vm() {
    local input_file="$1"
    local vm_name="$2"
    local format="$3"
    
    heading "Importing VM from: ${input_file}"
    
    [[ -f "${input_file}" ]] || die "Input file not found: ${input_file}"
    
    # Determine format if not specified
    if [[ -z "${format}" ]]; then
        case "${input_file}" in
            *.qcow2|*.qcow) format="qcow2" ;;
            *.vmdk) format="vmdk" ;;
            *.vdi) format="vdi" ;;
            *.raw) format="raw" ;;
            *.img) format="raw" ;;
            *) die "Unable to determine format from filename: ${input_file}" ;;
        esac
    fi
    
    # Default VM name from filename if not specified
    if [[ -z "${vm_name}" ]]; then
        vm_name=$(basename "${input_file}" | sed 's/\.[^.]*$//')
    fi
    
    # Create VM directory structure
    local vm_dir="${VM_DIR}/${vm_name}"
    local qcow2_dir="${vm_dir}/qcow2"
    local conf_dir="${vm_dir}/conf"
    
    ensure_dir "${qcow2_dir}"
    ensure_dir "${conf_dir}"
    
    # Convert to QCOW2 format (native for vm-manager.sh)
    local output_disk="${qcow2_dir}/${vm_name}-disk1.qcow2"
    
    log "Converting ${input_file} to QCOW2 format..."
    qemu-img convert -O qcow2 "${input_file}" "${output_disk}" || {
        die "Failed to convert disk image"
    }
    
    # Create basic configuration file
    local config_file="${conf_dir}/${vm_name}.conf"
    
    cat > "${config_file}" << EOF
# VM Configuration: ${vm_name}
# Imported from ${format} format on $(date)
VM_NAME="${vm_name}"
QEMU_ARCH="x86_64"  # Set appropriate architecture
MACHINE="pc"        # Set appropriate machine type
CPU="host"          # Set appropriate CPU
RAM_MB="2048"       # Set appropriate RAM
HDD_IMAGE="${output_disk}"
# Add other configuration options as needed
EOF
    
    log "✅ VM imported successfully: ${vm_name}"
    log "Configuration: ${config_file}"
    log "Disk image: ${output_disk}"
    log ""
    log "Note: You may need to edit the configuration file to set appropriate settings"
    return 0
}

# Import VM menu (interactive)
import_vm_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "import_vm_menu function requires interactive mode"
        return 1
    fi
    
    local input_file
    input_file=$(ask "Enter path to disk image file to import" "")
    
    [[ -f "${input_file}" ]] || die "File not found: ${input_file}"
    
    local vm_name
    vm_name=$(ask "Enter VM name (leave empty to use filename)" "")
    
    import_vm "${input_file}" "${vm_name}"
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

# ---------------------------------------------------------------------------
# Multi-VM Orchestration Functions
# ---------------------------------------------------------------------------

# Get list of all running VMs
get_running_vms() {
    local running_vms=()
    
    # Look for QEMU processes and extract VM names from pid files
    for vm_dir in "${VM_DIR}"/*/; do
        [[ -d "${vm_dir}" ]] || continue
        local vm_name=$(basename "${vm_dir}")
        local pid_file="${vm_dir}/pid"
        
        if [[ -f "${pid_file}" ]]; then
            local pid=$(cat "${pid_file}")
            if ps -p "${pid}" > /dev/null 2>&1; then
                running_vms+=("${vm_name}")
            fi
        fi
    done
    
    echo "${running_vms[@]}"
}

# Start all VMs
start_all_vms() {
    heading "Starting All VMs"
    
    local vm_confs=()
    local started_count=0
    local failed_count=0
    
    # Find all VM configuration files
    while IFS= read -r -d '' vm_conf; do
        vm_confs+=("${vm_conf}")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    if [[ ${#vm_confs[@]} -eq 0 ]]; then
        log "No VMs found to start"
        return 1
    fi
    
    log "Found ${#vm_confs[@]} VM(s) to start"
    
    # Start VMs sequentially with small delay between them
    for vm_conf in "${vm_confs[@]}"; do
        [[ -f "${vm_conf}" ]] || continue
        local vm_name=$(basename "${vm_conf}" .conf)
        
        log "Starting VM: ${vm_name}"
        if launch_vm "${vm_name}"; then
            started_count=$((started_count + 1))
            log "✓ Successfully started: ${vm_name}"
            sleep 2  # Small delay between VM starts
        else
            failed_count=$((failed_count + 1))
            warn "✗ Failed to start: ${vm_name}"
        fi
    done
    
    log "Started ${started_count} VMs, ${failed_count} failed"
    return $((failed_count > 0 ? 1 : 0))
}

# Stop all running VMs
stop_all_vms() {
    heading "Stopping All Running VMs"
    
    local running_vms=($(get_running_vms))
    local stopped_count=0
    local failed_count=0
    
    if [[ ${#running_vms[@]} -eq 0 ]]; then
        log "No running VMs found"
        return 0
    fi
    
    log "Found ${#running_vms[@]} running VM(s) to stop"
    
    # Stop VMs in reverse order (often more graceful)
    for ((i=${#running_vms[@]}-1; i>=0; i--)); do
        local vm_name="${running_vms[i]}"
        
        log "Stopping VM: ${vm_name}"
        if stop_vm "${vm_name}"; then
            stopped_count=$((stopped_count + 1))
            log "✓ Successfully stopped: ${vm_name}"
        else
            failed_count=$((failed_count + 1))
            warn "✗ Failed to stop: ${vm_name}"
        fi
    done
    
    log "Stopped ${stopped_count} VMs, ${failed_count} failed"
    return $((failed_count > 0 ? 1 : 0))
}

# Show status of all VMs
status_all_vms() {
    heading "Status of All VMs"
    
    local vm_confs=()
    
    # Find all VM configuration files
    while IFS= read -r -d '' vm_conf; do
        vm_confs+=("${vm_conf}")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    if [[ ${#vm_confs[@]} -eq 0 ]]; then
        log "No VMs found"
        return 1
    fi
    
    printf "%-20s %-15s %-10s\n" "VM Name" "Status" "PID"
    echo "------------------------------------------------"
    
    for vm_conf in "${vm_confs[@]}"; do
        [[ -f "${vm_conf}" ]] || continue
        local vm_name=$(basename "${vm_conf}" .conf)
        local vm_dir=$(dirname "$(dirname "${vm_conf}")")
        local pid_file="${vm_dir}/pid"
        
        if [[ -f "${pid_file}" ]]; then
            local pid=$(cat "${pid_file}")
            if ps -p "${pid}" > /dev/null 2>&1; then
                printf "%-20s %-15s %-10s\n" "${vm_name}" "RUNNING" "${pid}"
                continue
            fi
        fi
        
        printf "%-20s %-15s %-10s\n" "${vm_name}" "STOPPED" "-"
    done
    
    return 0
}

# Suspend all running VMs (save state)
suspend_all_vms() {
    heading "Suspending All Running VMs"
    
    local running_vms=($(get_running_vms))
    local suspended_count=0
    local failed_count=0
    
    if [[ ${#running_vms[@]} -eq 0 ]]; then
        log "No running VMs found"
        return 0
    fi
    
    log "Found ${#running_vms[@]} running VM(s) to suspend"
    
    # Suspend VMs sequentially
    for vm_name in "${running_vms[@]}"; do
        log "Suspending VM: ${vm_name}"
        
        # Find the QEMU process for this VM
        local vm_dir=""
        while IFS= read -r -d '' dir; do
            if [[ -f "${dir}/${vm_name}.conf" ]]; then
                vm_dir="${dir}"
                break
            fi
        done < <(find "${CONFIG_DIR}" -type d -print0 2>/dev/null)
        
        local pid_file="${vm_dir}/pid"
        if [[ -f "${pid_file}" ]]; then
            local pid=$(cat "${pid_file}")
            if ps -p "${pid}" > /dev/null 2>&1; then
                # Use QEMU monitor to save VM state
                if command -v qemu-guest-agent &>/dev/null; then
                    # Try guest-agent first
                    if qemu-guest-agent --save-state "${pid}" >/dev/null 2>&1; then
                        suspended_count=$((suspended_count + 1))
                        log "✓ Successfully suspended: ${vm_name}"
                        continue
                    fi
                fi
                
                # Fall back to sending SIGSTOP (less graceful)
                if kill -SIGSTOP "${pid}" 2>/dev/null; then
                    suspended_count=$((suspended_count + 1))
                    log "✓ Successfully suspended: ${vm_name}"
                else
                    failed_count=$((failed_count + 1))
                    warn "✗ Failed to suspend: ${vm_name}"
                fi
            fi
        fi
    done
    
    log "Suspended ${suspended_count} VMs, ${failed_count} failed"
    return $((failed_count > 0 ? 1 : 0))
}

# Multi-VM orchestration menu
orchestration_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "orchestration_menu function requires interactive mode"
        return 1
    fi
    
    while true; do
        clear || echo ""
        heading "Multi-VM Orchestration Menu"
        echo ""
        echo "  [1] Start all VMs"
        echo "  [2] Stop all running VMs"
        echo "  [3] Show status of all VMs"
        echo "  [4] Suspend all running VMs"
        echo ""
        echo "  [B] Back to main menu"
        echo ""
        
        choice=$(ask "Select option" "")
        
        case "${choice}" in
            1) start_all_vms ;;
            2) stop_all_vms ;;
            3) status_all_vms ;;
            4) suspend_all_vms ;;
            b|B|back|Back) return 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
        
        if is_interactive; then
            read -rp "Press Enter to continue..." _
        fi
    done
}

# ---------------------------------------------------------------------------
# VM Resource Monitoring Functions
# ---------------------------------------------------------------------------

# Get resource usage for a specific VM
monitor_vm() {
    local vm_name="$1"
    
    heading "Resource Monitoring: ${vm_name}"
    
    # Find VM directory
    local vm_dir=""
    while IFS= read -r -d '' dir; do
        if [[ -f "${dir}/${vm_name}.conf" ]]; then
            vm_dir="${dir}"
            break
        fi
    done < <(find "${CONFIG_DIR}" -type d -print0 2>/dev/null)
    
    [[ -d "${vm_dir}" ]] || die "VM directory not found: ${vm_name}"
    
    local pid_file="${vm_dir}/pid"
    if [[ -f "${pid_file}" ]]; then
        local pid=$(cat "${pid_file}")
        if ps -p "${pid}" > /dev/null 2>&1; then
            log "VM Process: PID ${pid}"
            
            # Get process info
            local process_info=$(ps -p "${pid}" -o pid,ppid,cmd,%cpu,%mem,etime,start_time --no-headers 2>/dev/null)
            if [[ -n "${process_info}" ]]; then
                echo "Process Info: ${process_info}"
            fi
            
            # Get memory usage
            local mem_info=$(ps -p "${pid}" -o rss,vsz --no-headers 2>/dev/null)
            if [[ -n "${mem_info}" ]]; then
                local rss=$(echo "${mem_info}" | awk '{print $1}')
                local vsz=$(echo "${mem_info}" | awk '{print $2}')
                log "Memory: RSS=${rss}KB, VSZ=${vsz}KB"
            fi
            
            # Get CPU usage
            local cpu_usage=$(ps -p "${pid}" -o %cpu --no-headers 2>/dev/null)
            if [[ -n "${cpu_usage}" ]]; then
                log "CPU Usage: ${cpu_usage}%"
            fi
            
            # Get disk usage for VM directory
            local disk_usage=$(du -sh "${vm_dir}" 2>/dev/null | awk '{print $1}')
            log "Disk Usage: ${disk_usage}"
            
            # Check for disk images
            local disk_images=()
            while IFS= read -r -d '' disk_file; do
                [[ "${disk_file}" == *.qcow2 || "${disk_file}" == *.qcow || "${disk_file}" == *.raw ]] && disk_images+=("${disk_file}")
            done < <(find "${vm_dir}/qcow2" -type f -print0 2>/dev/null)
            
            if [[ ${#disk_images[@]} -gt 0 ]]; then
                log "Disk Images:"
                for disk in "${disk_images[@]}"; do
                    local disk_size=$(du -sh "${disk}" 2>/dev/null | awk '{print $1}')
                    log "  - $(basename "${disk}"): ${disk_size}"
                done
            fi
            
            return 0
        else
            log "VM process ${pid} is not running"
            return 1
        fi
    else
        log "No PID file found - VM not running"
        return 1
    fi
}

# Monitor all VMs
monitor_all_vms() {
    heading "Resource Monitoring: All VMs"
    
    local vm_confs=()
    local running_count=0
    local stopped_count=0
    local total_cpu=0
    local total_mem=0
    
    # Find all VM configuration files
    while IFS= read -r -d '' vm_conf; do
        vm_confs+=("${vm_conf}")
    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
    
    if [[ ${#vm_confs[@]} -eq 0 ]]; then
        log "No VMs found"
        return 1
    fi
    
    printf "%-20s %-12s %-10s %-10s %-15s\n" "VM Name" "Status" "CPU %" "Memory" "Disk Usage"
    echo "--------------------------------------------------------------------------------"
    
    for vm_conf in "${vm_confs[@]}"; do
        [[ -f "${vm_conf}" ]] || continue
        local vm_name=$(basename "${vm_conf}" .conf)
        local vm_dir=$(dirname "$(dirname "${vm_conf}")")
        local pid_file="${vm_dir}/pid"
        
        local status="STOPPED"
        local cpu_percent="-"
        local memory_kb="-"
        local disk_usage="-"
        
        if [[ -f "${pid_file}" ]]; then
            local pid=$(cat "${pid_file}")
            if ps -p "${pid}" > /dev/null 2>&1; then
                status="RUNNING"
                running_count=$((running_count + 1))
                
                # Get CPU usage
                cpu_percent=$(ps -p "${pid}" -o %cpu --no-headers 2>/dev/null | tr -d ' ')
                [[ -z "${cpu_percent}" ]] && cpu_percent="0"
                
                # Get memory usage
                memory_kb=$(ps -p "${pid}" -o rss --no-headers 2>/dev/null | tr -d ' ')
                [[ -z "${memory_kb}" ]] && memory_kb="0"
                
                total_cpu=$((total_cpu + ${cpu_percent%.*} ))
                total_mem=$((total_mem + memory_kb))
            else
                stopped_count=$((stopped_count + 1))
            fi
        else
            stopped_count=$((stopped_count + 1))
        fi
        
        # Get disk usage
        disk_usage=$(du -sh "${vm_dir}" 2>/dev/null | awk '{print $1}')
        [[ -z "${disk_usage}" ]] && disk_usage="-"
        
        printf "%-20s %-12s %-10s %-10s %-15s\n" "${vm_name}" "${status}" "${cpu_percent}" "${memory_kb}KB" "${disk_usage}"
    done
    
    echo ""
    log "Summary: ${running_count} running, ${stopped_count} stopped"
    log "Total CPU: ${total_cpu}%, Total Memory: ${total_mem}KB"
    return 0
}

# Show VM statistics
stats_vm() {
    local vm_name="$1"
    monitor_vm "${vm_name}"
}

# Real-time monitoring dashboard
monitor_dashboard() {
    heading "Real-time VM Monitoring Dashboard"
    
    log "Starting real-time monitoring (Ctrl+C to stop)..."
    log "Press any key to refresh immediately"
    
    # Check if watch command is available
    if command -v watch &>/dev/null; then
        watch -n 2 "${SCRIPT_NAME} monitor-all"
    else
        # Fallback: manual refresh loop
        while true; do
            clear
            monitor_all_vms
            echo ""
            log "Refreshing in 2 seconds... (Ctrl+C to stop)"
            sleep 2
        done
    fi
}

# Monitoring menu
monitor_menu() {
    # This function requires interactive mode
    if ! is_interactive; then
        warn "monitor_menu function requires interactive mode"
        return 1
    fi
    
    while true; do
        clear || echo ""
        heading "VM Resource Monitoring Menu"
        echo ""
        echo "  [1] Monitor specific VM"
        echo "  [2] Monitor all VMs"
        echo "  [3] Show VM statistics"
        echo "  [4] Real-time dashboard"
        echo ""
        echo "  [B] Back to main menu"
        echo ""
        
        choice=$(ask "Select option" "")
        
        case "${choice}" in
            1) 
                list_vms || return 1
                vm_num=$(ask "Select VM number to monitor" "")
                if [[ -n "$vm_num" && "$vm_num" =~ ^[0-9]+$ ]]; then
                    local vm_confs=()
                    while IFS= read -r -d '' vm_conf; do
                        vm_confs+=("$vm_conf")
                    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
                    
                    if [[ $vm_num -ge 1 && $vm_num -le ${#vm_confs[@]} ]]; then
                        local selected_vm=$(basename "${vm_confs[$((vm_num-1))]}" .conf)
                        monitor_vm "${selected_vm}"
                    fi
                fi
                ;;
            2) monitor_all_vms ;;
            3) 
                list_vms || return 1
                vm_num=$(ask "Select VM number for statistics" "")
                if [[ -n "$vm_num" && "$vm_num" =~ ^[0-9]+$ ]]; then
                    local vm_confs=()
                    while IFS= read -r -d '' vm_conf; do
                        vm_confs+=("$vm_conf")
                    done < <(find "${VM_DIR}" -path "*/conf/*.conf" -print0 2>/dev/null | sort -z)
                    
                    if [[ $vm_num -ge 1 && $vm_num -le ${#vm_confs[@]} ]]; then
                        local selected_vm=$(basename "${vm_confs[$((vm_num-1))]}" .conf)
                        stats_vm "${selected_vm}"
                    fi
                fi
                ;;
            4) monitor_dashboard ;;
            b|B|back|Back) return 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
        
        if is_interactive; then
            read -rp "Press Enter to continue..." _
        fi
    done
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

# Edit existing VM
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

# Create a new environment configuration file (.env template)
create_env_config() {
    local config_name=""
    local config_file=""
    
    # This function requires interactive mode
    if ! is_interactive; then
        warn "create_env_config function requires interactive mode"
        return 1
    fi
    
    heading "Create Environment Configuration"
    
    config_name=$(ask "Configuration name (e.g., my-custom-env)" "")
    [[ -z "${config_name}" ]] && { warn "Configuration name cannot be empty"; return 1; }
    
    # Remove .env extension if provided
    config_name="${config_name%.env}"
    config_file="${VM_CONFIG_DIR}/${config_name}.env"
    
    # Check if config already exists
    if [[ -f "${config_file}" ]]; then
        local overwrite
        overwrite=$(ask "Configuration file already exists. Overwrite? (y/n)" "n")
        if [[ "${overwrite}" != "y" ]]; then
            warn "Configuration creation cancelled"
            return 1
        fi
    fi
    
    ensure_dir "${VM_CONFIG_DIR}"
    
    log "Creating environment configuration: ${config_file}"
    
    # Platform selection
    echo "Select platform:"
    echo "  [1] 68k (Motorola 68000)"
    echo "  [2] PPC (PowerPC 32-bit)"
    echo "  [3] PPC64 (PowerPC 64-bit)"
    echo "  [4] x86 (32-bit)"
    echo "  [5] x86_64 (64-bit)"
    echo "  [6] ARM"
    echo "  [7] ARM64"
    echo "  [8] SPARC"
    echo "  [9] SPARC64"
    echo "  [10] Custom"
    echo ""
    
    local platform_choice
    platform_choice=$(ask "Platform" "1")
    
    local qemu_bin=""
    local machine=""
    local cpu=""
    local default_ram=""
    local network_model=""
    local display_backend=""
    local boot_order="c"
    local arch_desc=""
    
    case "${platform_choice}" in
        1) # 68k
            qemu_bin="qemu-system-m68k"
            machine="q800"
            cpu="m68040"
            default_ram="64"
            network_model="dp83932"
            display_backend="gtk"
            arch_desc="68k (Motorola 68000)"
            ;;
        2) # PPC
            qemu_bin="qemu-system-ppc"
            machine="mac99,via=pmu"
            cpu="7455"
            default_ram="256"
            network_model="sungem"
            display_backend="sdl"
            arch_desc="PPC (PowerPC 32-bit)"
            ;;
        3) # PPC64
            qemu_bin="qemu-system-ppc64"
            machine="mac99,via=pmu"
            cpu="970fx"
            default_ram="1024"
            network_model="sungem"
            display_backend="sdl"
            arch_desc="PPC64 (PowerPC 64-bit)"
            boot_order="d"  # Boot from CDROM for Mac OS X install
            ;;
        4) # x86
            qemu_bin="qemu-system-i386"
            machine="pc"
            cpu="pentium3"
            default_ram="512"
            network_model="e1000"
            display_backend="gtk"
            arch_desc="x86 (32-bit)"
            ;;
        5) # x86_64
            qemu_bin="qemu-system-x86_64"
            machine="q35"
            cpu="host"
            default_ram="2048"
            network_model="e1000"
            display_backend="cocoa"
            arch_desc="x86_64 (64-bit)"
            ;;
        6) # ARM
            qemu_bin="qemu-system-arm"
            machine="virt"
            cpu="cortex-a15"
            default_ram="512"
            network_model="virtio-net-pci"
            display_backend="gtk"
            arch_desc="ARM"
            ;;
        7) # ARM64
            qemu_bin="qemu-system-aarch64"
            machine="virt"
            cpu="cortex-a72"
            default_ram="2048"
            network_model="virtio-net-pci"
            display_backend="gtk"
            arch_desc="ARM64"
            ;;
        8) # SPARC
            qemu_bin="qemu-system-sparc"
            machine="sun4m"
            cpu="TI-UltraSparc-IIi"
            default_ram="512"
            network_model="lance"
            display_backend="gtk"
            arch_desc="SPARC"
            ;;
        9) # SPARC64
            qemu_bin="qemu-system-sparc64"
            machine="sun4u"
            cpu="TI-UltraSparc-IIIi"
            default_ram="1024"
            network_model="sungem"
            display_backend="gtk"
            arch_desc="SPARC64"
            ;;
        10) # Custom
            qemu_bin=$(ask "QEMU binary (e.g., qemu-system-x86_64)" "qemu-system-x86_64")
            machine=$(ask "Machine type" "pc")
            cpu=$(ask "CPU model" "host")
            default_ram=$(ask "Default RAM (MB)" "1024")
            network_model=$(ask "Network model" "e1000")
            display_backend=$(ask "Display backend" "cocoa")
            arch_desc="Custom"
            ;;
        *)
            warn "Invalid platform selection"
            return 1
            ;;
    esac
    
    # Additional configuration options
    local ram_mb
    ram_mb=$(ask "RAM size (MB)" "${default_ram}")
    
    local smp_sockets=1
    local smp_cores=1
    local smp_threads=1
    
    if [[ "${platform_choice}" =~ ^[23]$ ]]; then  # PPC platforms support SMP
        smp_sockets=$(ask "SMP sockets (for multi-processor)" "1")
        smp_cores=$(ask "SMP cores per socket" "1")
    fi
    
    # Disk configuration
    local hdd_image=""
    hdd_image=$(ask "Default HDD image path" "${VM_IMAGE_DIR}/${config_name}.qcow2")
    
    local cdrom_image=""
    cdrom_image=$(ask "Default CDROM/ISO path (leave empty if none)" "")
    
    # Network configuration
    local network_type="user"
    network_type=$(ask "Network type (user/none/tap)" "${network_type}")
    
    # Audio configuration
    local audio_backend=""
    audio_backend=$(ask "Audio backend (sdl/coreaudio/none)" "sdl")
    
    # Display configuration
    local dual_display="no"
    dual_display=$(ask "Enable dual display? (y/n)" "n")
    [[ "${dual_display}" == "y" ]] && dual_display="yes" || dual_display="no"
    
    # Shared directory
    local shared_dir="${VM_SHARED_DIR}"
    shared_dir=$(ask "Shared directory path" "${shared_dir}")
    
    # Create the configuration file
    cat > "${config_file}" << EOF
# =============================================================================
# ${config_name}.env - ${arch_desc} Environment Configuration
# Created: $(date)
# =============================================================================

# --- QEMU binary ---
QEMU_BIN=${qemu_bin}

# --- Machine / CPU ---
MACHINE=${machine}
CPU=${cpu}
RAM_MB=${ram_mb}

# --- SMP / Multi-processor ---
SMP_SOCKETS=${smp_sockets}
SMP_CORES=${smp_cores}
SMP_THREADS=${smp_threads}

# --- Disk images ---
HDD_IMAGE=${hdd_image}
CDROM_IMAGE=${cdrom_image}

# --- Display ---
DISPLAY_BACKEND=${display_backend}
DUAL_DISPLAY=${dual_display}

# --- Network ---
NETWORK_MODEL=${network_model}
NETWORK_TYPE=${network_type}

# --- Host integration ---
VM_SHARED_DIR=${shared_dir}

# --- Audio ---
AUDIO_BACKEND=${audio_backend}

# --- Boot order ---
BOOT_ORDER=${boot_order}

# --- Additional QEMU arguments ---
QEMU_ARGS=

# =============================================================================
# Example launch command:
# ${SCRIPT_NAME} launch ${config_name}
# =============================================================================
EOF
    
    log "✅ Environment configuration created: ${config_file}"
    log "You can now create VMs using this configuration with: ${SCRIPT_NAME} create"
    
    # Ask if user wants to edit the file manually
    local edit_now
    edit_now=$(ask "Edit configuration file now? (y/n)" "n")
    if [[ "${edit_now}" == "y" ]]; then
        ${EDITOR:-nano} "${config_file}"
    fi
    
    return 0
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
        echo "💾 Disk & Image Management:"
        echo "  [10] Create disk image"
        echo "  [11] Convert disk image"
        echo "  [12] Resize disk image"
        echo "  [13] List available Images"
        echo "  [14] Download Image from URL"
        echo "  [15] Detect Images in all directories"
        echo "  [16] Detect ROMs in all directories"
        echo "  [17] Insert Image into VM"
        echo "  [18] Eject Image from VM"
        echo ""
        echo "🍎 UTM.app Integration:"
        echo "  [19] Create UTM VM configuration"
        echo "  [20] Export VM to UTM format"
        echo ""
        echo "📥 Export/Import VMs:"
        echo "  [81] Export VM to other format"
        echo "  [82] Import VM from disk image"
        echo ""
        echo "🔧 Advanced VM Management:"}
        echo "  [21] Stop a running VM"
        echo "  [22] Edit existing VM"
        echo "  [23] Clone VM"
        echo "  [24] Create environment configuration"
        echo "  [25] List ROM files"
        echo "  [26] List disk images"
        echo "  [80] Multi-VM orchestration"
        echo "  [83] VM Resource Monitoring"
        echo ""
        echo "🐛 Debugging:"
        echo "  [84] Debug session management"
        echo "  [85] Start VM in debug mode"
        echo "  [86] Connect GDB to running VM"
        echo "  [87] Attach GDB to specific port"
        echo "  [88] Test GDB connection"
        echo ""
        echo "💾 Backup & Restore:"
        echo "  [27] Create configuration backup"
        echo "  [28] List available backups"
        echo "  [29] Restore from backup"
        echo "  [30] Cleanup old snapshots"
        echo "  [31] Find unused disk images"
        echo ""
        echo "🚀 Quick Launch (Platform Presets):"
        echo "  [32] MacOS 68k (System 7-8.1)"
        echo "  [33] MacOS PPC (7.5.2-9.2.2, G3/G4)"
        echo "  [34] MacOS PPC64 (Mac OS X, G5)"
        echo "  [35] MacOS 10.6 PPC (Snow Leopard with dual display)"
        echo "  [36] Create MacOS 10.6 PPC VM with all options"
        echo "  [37] Debug MacOS 10.6 PPC VM"
        echo "  [38] HaikuOS"
        echo "  [39] Linux (generic)"
        echo "  [40] Atari ST/TT/Falcon (68k)"
        echo "  [41] Commodore Amiga (68k/AROS)"
        echo "  [42] Solaris x86"
        echo "  [43] Solaris SPARC"
        echo "  [44] Windows XP"
        echo "  [45] OpenStep x86"
        echo "  [46] Custom QEMU (any architecture)"
        echo ""
        echo "🛠️ 68k Development Tools (Retro68):"
        echo "  [69] Check Retro68 installation"
        echo "  [70] Install Retro68 toolchain"
        echo "  [71] Setup Retro68 environment"
        echo "  [72] Compile with Retro68"
        echo "  [73] Compile MacOS71_GDB_ICMP_Test"
        echo "  [74] Retro68 debug workflow"
        echo "  [75] Launch MacOS 68k debug VM"
        echo ""
        echo "📖 Information:"
        echo "  [47] Show QEMU version"
        echo "  [48] Show available architectures"
        echo "  [49] Show VM configurations"
        echo ""
        echo "🔍 Diagnostics:"
        echo "  [50] Test sharing services (Samba/Netatalk)"
        echo "  [51] Configure Netatalk (AFP) file sharing"
        echo "  [52] Configure Samba file sharing"
        echo "  [53] Verify all dependencies"
        echo "  [54] Configure XQuartz for X11 display"
        echo "  [55] Configure XDialog for GUI"
        echo "  [56] Configure RAMDISK for sharing"
        echo "  [57] Test Samba connection"
        echo "  [58] Test Netatalk connection"
        echo "  [59] Test SSH connection"
        echo "  [60] Test GDB connection"
        echo "  [61] Show QEMU command (debugging)"
        echo "  [62] VM Snapshot Management"
        echo "  [63] Check MacPorts installation"
        echo "  [64] Check Homebrew installation"
        echo "  [65] Update package manager"
        echo "  [66] Install VM dependencies"
        echo "  [67] Test local share directory"
        echo "  [68] List all shares and directories"
        echo "  [69] Cleanup menu"
        echo ""
        echo "🔧 Toolchain Management:"
        echo "  [70] Detect cross-compilation toolchains"
        echo "  [71] List detected toolchains"
        echo "  [72] Configure toolchain environment"
        echo ""
        echo "🔨 Build Automation:"
        echo "  [73] Build project"
        echo "  [74] Create development project"
        echo "  [75] List development projects"
        echo "  [76] Build-Deploy-Debug workflow"
        echo ""
        echo "📁 Source Code Mounting:"
        echo "  [77] Mount source code to VM"
        echo "  [78] Unmount source code from VM"
        echo "  [79] List source code mounts"
        echo ""
        echo "🎨 GUI Application Management:"
        echo "  [90] Launch GUI application from VM"
        echo "  [91] Configure XQuartz optimization"
        echo ""
        echo "🧪 Testing Framework:"
        echo "  [92] Run tests in VM"
        echo "  [93] Create test configuration"
        echo "  [94] List test configurations"
        echo "  [95] Run test configuration"
        echo ""
        echo "🎨 XDialog UI:"
        echo "  [96] Start GUI mode"
        echo "  [97] Create VM (GUI)"
        echo "  [98] Manage VMs (GUI)"
        echo "  [99] Debug VM (GUI)"
        echo ""
        echo "🚀 Enhanced Deployment:"
        echo "  [100] Incremental deployment"
        echo "  [101] Validate environment"
        echo "  [102] Rollback deployment"
        echo "  [103] List deployment history"
        echo "  [104] Cleanup deployments"
        echo ""
        echo "💾 Development Project Management - Snapshots:"
        echo "  [105] Create project snapshot"
        echo "  [106] Restore project snapshot"
        echo "  [107] List project snapshots"
        echo "  [108] Delete project snapshot"
        echo ""
        echo "🐛 Debug Session Recording:"
        echo "  [109] Start debug session recording"
        echo "  [110] Stop debug session recording"
        echo "  [111] Replay debug session"
        echo "  [112] List debug sessions"
        echo "  [113] Delete debug session"
        echo ""
        echo "🎯 Breakpoint Presets:"
        echo "  [114] Create breakpoint preset"
        echo "  [115] Apply breakpoint preset"
        echo "  [116] List breakpoint presets"
        echo "  [117] Delete breakpoint preset"
        echo ""
        echo "🔗 Multi-VM Debugging:"
        echo "  [118] Start multi-VM debug session"
        echo "  [119] Stop multi-VM debug session"
        echo "  [120] List multi-VM debug sessions"
        echo "  [121] Delete multi-VM debug session"
        echo ""
        echo "🔍 Debug Symbol Management:"
        echo "  [122] Download debug symbols"
        echo "  [123] Generate debug information"
        echo "  [124] List debug symbols"
        echo "  [125] Delete debug symbols"
        echo ""
        echo "⚙️  Automatic GDB Configuration:"
        echo "  [126] Generate GDB configuration"
        echo "  [127] List GDB configurations"
        echo "  [128] Delete GDB configuration"
        echo ""
        echo "📝 Configuration Versioning:"
        echo "  [129] Backup VM configuration"
        echo "  [130] Restore VM configuration"
        echo "  [131] Show configuration history"
        echo "  [132] Show configuration diff"
        echo "  [133] Commit configuration"
        echo "  [134] List all config backups"
        echo ""
        echo "🔗 SPICE Advanced Features:"
        echo "  [135] Start VM with SPICE"
        echo "  [136] Connect to SPICE console"
        echo "  [137] Configure SPICE options"
        echo "  [138] Create TLS certificates for SPICE"
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
            13) list_images ;;
            14) download_iso ;;
            15) detect_available_images ;;
            16) detect_available_roms ;;
            17) insert_iso_menu ;;
            18) eject_iso_menu ;;
            19) create_utm_vm ;;
            20) export_utm_menu ;;
            21) stop_vm_menu ;;
            22) edit_vm_menu ;;
            23) clone_vm_menu ;;
            24) create_env_config ;;
            25) list_roms ;;
            26) list_disks ;;
            27) backup_configurations ;;
            28) list_backups ;;
            29) backup_restore_menu ;;
            30) cleanup_all_snapshots ;;
            31) cleanup_unused_disks ;;
            32) launch_macos_68k ;;
            33) launch_macos_ppc ;;
            34) launch_macos_ppc64 ;;
            35) launch_macos_10_6_ppc ;;
            36) create_and_launch_macos_10_6_ppc ;;
            37) debug_macos_10_6_ppc ;;
            38) launch_haiku ;;
            39) launch_linux ;;
            40) launch_atari ;;
            41) launch_amiga ;;
            42) launch_solaris_x86 ;;
            43) launch_solaris_sparc ;;
            44) launch_windows_xp ;;
            45) launch_openstep ;;
            46) launch_custom ;;
            69) check_retro68 ;;
            70) install_retro68 ;;
            71) setup_retro68_environment ;;
            72) compile_with_retro68 ;;
            73) compile_macos71_test ;;
            74) retro68_debug_workflow ;;
            75) launch_macos_68k_debug ;;
            47) show_qemu_version ;;
            48) show_architectures ;;
            49) show_vm_configs ;;
            50) test_sharing_services ;;
            51) configure_netatalk ;;
            52) configure_samba ;;
            53) verify_dependencies ;;
            54) configure_xquartz ;;
            55) configure_xdialog ;;
            56) configure_ramdisk ;;
            57) test_samba_connection localhost VM_Shares ;;
            58) test_netatalk_connection localhost VM_Shares ;;
            59) test_ssh_connection localhost 22 ;;
            60) test_gdb_connection ;;
            61) show_qemu_command_menu ;;
            62) snapshot_menu ;;
            63) check_macports ;;
            64) check_homebrew ;;
            65) update_package_manager ;;
            66) install_vm_dependencies ;;
            67) test_local_share ;;
            68) list_shares ;;
            69) cleanup_menu ;;
            70) detect_cross_compilation_toolchains ;;
            71) list_detected_toolchains ;;
            72) configure_toolchain ;;
            73) build_project_menu ;;
            74) create_dev_project_interactive ;;
            75) list_projects ;;
            76) build_deploy_debug_interactive ;;
            77) mount_source_code_interactive ;;
            78) 
                local vm_name
                vm_name=$(ask "Enter VM name" "")
                [[ -n "$vm_name" ]] && unmount_source_code "$vm_name" || echo "VM name required"
                ;;
            79) 
                local vm_name
                vm_name=$(ask "Enter VM name" "")
                [[ -n "$vm_name" ]] && list_source_mounts "$vm_name" || echo "VM name required"
                ;;
            80) orchestration_menu ;;
            81) export_vm_menu ;;
            82) import_vm_menu ;;
            83) monitor_menu ;;
            84) debug_session_menu ;;
            85) 
                local vm_name binary_path port
                vm_name=$(ask "Enter VM name to start in debug mode" "")
                [[ -n "$vm_name" ]] && debug_vm "$vm_name" "$binary_path" "$port" || echo "VM name required"
                ;;
            86) 
                local vm_name binary_path port
                vm_name=$(ask "Enter VM name to connect GDB" "")
                [[ -n "$vm_name" ]] && debug_connect "$vm_name" "$binary_path" "$port" || echo "VM name required"
                ;;
            87) 
                local vm_name port
                vm_name=$(ask "Enter VM name" "")
                port=$(ask "Enter debug port" "1234")
                [[ -n "$vm_name" ]] && debug_attach "$vm_name" "$port" || echo "VM name and port required"
                ;;
            88) 
                local vm_name port
                vm_name=$(ask "Enter VM name to test GDB connection" "")
                [[ -n "$vm_name" ]] && debug_test "$vm_name" "$port" || echo "VM name required"
                ;;
            90) launch_gui_application_interactive ;;
            91) configure_xquartz_optimization ;;
            92) 
                local vm_name
                vm_name=$(ask "Enter VM name" "")
                [[ -n "$vm_name" ]] && run_vm_tests "$vm_name" "" "" "" || echo "VM name required"
                ;;
            93) create_test_config_interactive ;;
            94) list_test_configs ;;
            95) run_test_config_interactive ;;
            96) gui_mode_start ;;
            97) gui_create_vm ;;
            98) gui_manage_vms ;;
            99) gui_debug_vm ;;
            100) 
                local vm_name source_dir target_dir backup_first exclude
                vm_name=$(ask "Enter VM name" "")
                [[ -n "$vm_name" ]] && incremental_deploy "$vm_name" "$source_dir" "$target_dir" "$backup_first" "$exclude" || echo "VM name required"
                ;;
            101) 
                local vm_name requirements_file
                vm_name=$(ask "Enter VM name" "")
                [[ -n "$vm_name" ]] && validate_environment "$vm_name" "$requirements_file" || echo "VM name required"
                ;;
            102) 
                local vm_name backup_id target_dir
                vm_name=$(ask "Enter VM name" "")
                [[ -n "$vm_name" ]] && rollback_deployment "$vm_name" "$backup_id" "$target_dir" || echo "VM name required"
                ;;
            103) 
                local vm_name
                vm_name=$(ask "Enter VM name" "")
                [[ -n "$vm_name" ]] && list_deployment_history "$vm_name" || echo "VM name required"
                ;;
            104) 
                local vm_name keep_backups target_dir
                vm_name=$(ask "Enter VM name" "")
                [[ -n "$vm_name" ]] && cleanup_deployment "$vm_name" "$keep_backups" "$target_dir" || echo "VM name required"
                ;;
            # Development Project Management - Snapshots
            105) create_project_snapshot_interactive ;;
            106) restore_project_snapshot_interactive ;;
            107) 
                local project_name
                project_name=$(ask "Enter project name (leave blank for all projects)" "")
                [[ -n "$project_name" ]] && list_project_snapshots "$project_name" || list_project_snapshots
                ;;
            108) delete_project_snapshot_interactive ;;
            
            # Debug Session Recording
            109) start_debug_recording_interactive ;;
            110) 
                local session_name
                session_name=$(ask "Enter session name to stop" "")
                [[ -n "$session_name" ]] && stop_debug_recording "$session_name" || echo "Session name required"
                ;;
            111) replay_debug_session_interactive ;;
            112) list_debug_sessions ;;
            113) 
                local session_name
                session_name=$(ask "Enter session name to delete" "")
                [[ -n "$session_name" ]] && delete_debug_session "$session_name" || echo "Session name required"
                ;;
            
            # Breakpoint Presets
            114) create_breakpoint_preset_interactive ;;
            115) 
                local preset_name vm_name gdb_port
                preset_name=$(ask "Enter preset name" "")
                vm_name=$(ask "Enter VM name" "")
                gdb_port=$(ask "Enter GDB port" "1234")
                [[ -n "$preset_name" && -n "$vm_name" ]] && apply_breakpoint_preset "$preset_name" "$vm_name" "$gdb_port" || echo "Preset name and VM name required"
                ;;
            116) list_breakpoint_presets ;;
            117) 
                local preset_name
                preset_name=$(ask "Enter preset name to delete" "")
                [[ -n "$preset_name" ]] && delete_breakpoint_preset "$preset_name" || echo "Preset name required"
                ;;
            
            # Multi-VM Debugging
            118) start_multi_debug_interactive ;;
            119) 
                local session_name
                session_name=$(ask "Enter multi-debug session name to stop" "")
                [[ -n "$session_name" ]] && stop_multi_debug "$session_name" || echo "Session name required"
                ;;
            120) list_multi_debug_sessions ;;
            121) 
                local session_name
                session_name=$(ask "Enter multi-debug session name to delete" "")
                [[ -n "$session_name" ]] && delete_multi_debug_session "$session_name" || echo "Session name required"
                ;;
            
            # Debug Symbol Management
            122) download_debug_symbols_interactive ;;
            123) 
                local binary_path
                binary_path=$(ask "Enter path to binary" "")
                [[ -n "$binary_path" ]] && generate_debug_info "$binary_path" || echo "Binary path required"
                ;;
            124) list_debug_symbols ;;
            125) 
                local binary_name
                binary_name=$(ask "Enter binary name to delete debug symbols" "")
                [[ -n "$binary_name" ]] && delete_debug_symbols "$binary_name" || echo "Binary name required"
                ;;
            
            # Automatic GDB Configuration
            126) generate_gdb_config_interactive ;;
            127) list_gdb_configs ;;
            128) 
                local config_name
                config_name=$(ask "Enter GDB config name to delete" "")
                [[ -n "$config_name" ]] && delete_gdb_config "$config_name" || echo "Config name required"
                ;;
            
            # Configuration Versioning
            129) config_backup_interactive ;;
            130) config_restore_interactive ;;
            131) config_history_interactive ;;
            132) config_diff_interactive ;;
            133) config_commit_interactive ;;
            134) list_config_backups ;;
            
            # SPICE Advanced Features
            135) spice_start_interactive ;;
            136) spice_connect_interactive ;;
            137) spice_config_interactive ;;
            138) 
                local cert_path key_path days
                cert_path=$(ask "Enter path for TLS certificate" "${SPICE_CONFIG_DIR}/spice-server.crt")
                key_path=$(ask "Enter path for TLS key" "${SPICE_CONFIG_DIR}/spice-server.key")
                days=$(ask "Enter certificate validity in days" "365")
                [[ -n "$cert_path" && -n "$key_path" ]] && spice_create_tls "$cert_path" "$key_path" "$days" || echo "Certificate and key paths required"
                ;;
            
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
    warn "Invalid VM selection"
    return 1
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
    warn "Invalid VM selection"
    return 1
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
    warn "Invalid VM selection"
    return 1
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
    warn "Invalid VM selection"
    return 1
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
    warn "Invalid VM selection"
    return 1
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
    warn "Invalid VM selection"
    return 1
}

# Menu for editing existing VM
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
    warn "Invalid VM selection"
    return 1
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
  clone <src> <dest> Clone an existing VM
  list              List all VMs
  launch <name>    Launch a VM
  delete <name>    Delete a VM

Multi-VM Orchestration:
  start-all         Start all VMs
  stop-all          Stop all running VMs
  status-all        Show status of all VMs
  suspend-all       Suspend all running VMs
  orchestration     Interactive orchestration menu

VM Resource Monitoring:
  monitor           Monitor all VMs
  monitor-vm <name> Monitor specific VM
  monitor-dashboard Start real-time monitoring dashboard
  monitor-menu      Interactive monitoring menu
  stats-vm <name>   Show VM resource statistics

Debugging:
  debug <name>       Start debug session for a VM
  debug-connect      Connect GDB to running VM
  debug-list        List active debug sessions
  debug-detach      Detach from debug session
  deploy <name>     Deploy binary to a VM
  debug-menu       Interactive debug session menu

VM Export/Import:
  export <name> <out>        Export VM to QCOW2 format
  export-qcow2 <name> <out> Export VM to QCOW2 format
  export-vmdk <name> <out>  Export VM to VMDK (VMware) format
  export-vdi <name> <out>   Export VM to VDI (VirtualBox) format
  export-raw <name> <out>   Export VM to RAW format
  import <file> <name>      Import VM from disk image file
  export-menu              Interactive export menu
  import-menu              Interactive import menu

Platform Presets:
  macos-68k        Launch MacOS 68k VM
  macos-ppc        Launch MacOS PPC VM (G3/G4)
  macos-ppc64      Launch MacOS PPC VM (G5)
  macos-106        Launch MacOS 10.6 PPC VM with dual display and debugging
  create-macos-106 Create MacOS 10.6 PPC VM with all options
  debug-macos-106  Debug MacOS 10.6 PPC VM with enhanced debugging
  haiku            Launch HaikuOS VM
  linux            Launch Linux VM
  atari            Launch Atari ST/TT/Falcon VM
  amiga            Launch Commodore Amiga/AROS VM
  solaris-x86      Launch Solaris x86 VM
  solaris-sparc    Launch Solaris SPARC VM
  windows-xp       Launch Windows XP VM
  openstep         Launch OpenStep x86 VM
  custom           Launch custom QEMU with any architecture

Image Management:
  image-list       List available Images
  image-download   Download Image from URL
  image-detect    Detect Images in all directories
  rom-detect      Detect ROMs in all directories
  image-insert <vm>  Insert Image into VM
  image-eject <vm>  Eject Image from VM

Architecture Detection:
  arch-detect      Detect available QEMU architectures

UTM Integration:
  utm-create       Create UTM VM configuration
  utm-export <vm>  Export VM to UTM format

Retro68 Development Tools:
  retro68-check    Check Retro68 installation
  retro68-install  Install Retro68 toolchain
  retro68-setup    Setup Retro68 environment
  retro68-compile  Compile with Retro68
  retro68-compile-test Compile MacOS71_GDB_ICMP_Test project
  retro68-debug    Full Retro68 debug workflow
  retro68-debug-vm Launch MacOS 68k debug VM

Advanced VM Management:
  stop             Stop a running VM
  edit             Edit existing VM
  create-env-config Create environment configuration (.env file)
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
  configure-xdialog Configure XDialog for GUI
  configure-ramdisk Configure RAMDISK for sharing
  test-samba        Test Samba connection with mounting
  test-netatalk    Test Netatalk connection with mounting
  test-ssh         Test SSH connection
  test-gdb         Test GDB debug connection
  backup-config     Create backup of configurations
  list-backups      List available backups
  restore-config    Restore from backup
  show-command      Show QEMU command for a VM (debugging)
  snapshot          VM Snapshot Management
  check-macports    Check if MacPorts is installed
  check-homebrew    Check if Homebrew is installed
  update-packages   Update MacPorts or Homebrew
  install-deps      Install VM dependencies using package manager
  test-local-share  Test local share directory functionality
  list-shares      List all configured shares and directories
  cleanup          Cleanup old snapshots and unused files (interactive menu)

Toolchain Management:
  detect-toolchains  Detect available cross-compilation toolchains
  list-toolchains    List detected cross-compilation toolchains
  configure-toolchain Configure toolchain environment

Build Automation:
  build-project    Build a development project
  create-project   Create a new development project
  list-projects    List all development projects
  build-deploy-debug Run full build-deploy-debug workflow

Source Code Mounting:
  mount-source    Mount source code directory to VM
  unmount-source  Unmount source code directory from VM
  list-mounts     List mounted source code directories

GUI Application Management:
  launch-gui     Launch GUI application from VM
  xquartz-opt    Configure XQuartz optimization

Testing Framework:
  run-tests      Run tests in VM
  create-test    Create test configuration
  list-tests     List test configurations
  run-test       Run test configuration

XDialog UI:
  gui-mode       Start XDialog GUI mode
  gui-create-vm  Create VM with GUI
  gui-manage     Manage VMs with GUI
  gui-debug     Debug VM with GUI

Enhanced Deployment:
  incremental-deploy  Incremental deployment to VM
  validate-env       Validate VM environment before deployment
  rollback           Rollback to previous deployment
  deployment-history List deployment history
  cleanup-deploy    Cleanup old deployments and backups
  cleanup-snapshots Cleanup old VM snapshots
  cleanup-disks    Find and remove unused disk images
  menu             Interactive menu (default)
  help             Show this help

SPICE Advanced Features:
  spice-start <vm> [port] [tls_port] [options]  Start VM with SPICE display
  spice-connect <vm> [port]                   Connect to SPICE console
  spice-config <vm> [port] [tls_port] [cert] [key]  Configure SPICE options
  spice-create-tls <cert> <key> [days]       Create TLS certificates for SPICE

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
    local platform="$2"
    
    # Enhanced bundled directory structure: look for config in VM_NAME_PLATFORM/conf/
    if [[ -n "${platform}" ]]; then
        local config_file="${VM_DIR}/${vm_name}_${platform}/conf/${vm_name}.conf"
    else
        # Try to find the config file by searching for VM directories
        local config_file=""
        local found=0
        while IFS= read -r -d '' possible_config; do
            local possible_vm_name=$(basename "$(dirname "$(dirname "${possible_config}")")" | sed 's/_.*//')
            if [[ "${possible_vm_name}" == "${vm_name}" ]]; then
                config_file="${possible_config}"
                found=1
                break
            fi
        done < <(find "${VM_DIR}" -path "*/conf/${vm_name}.conf" -print0 2>/dev/null)
        
        if [[ ${found} -eq 0 ]]; then
            die "VM configuration not found for: ${vm_name}"
        fi
    fi
    
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
    ensure_dir "${IMAGES_DIR}"
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
    
    # Check if XQuartz is running and no command provided, offer GUI mode
    if [[ -z "${1:-}" ]] && is_interactive; then
        if pgrep -x "Xquartz" &>/dev/null; then
            local use_gui
            use_gui=$(ask "XQuartz is running. Use GUI mode? (yes/no)" "yes")
            if [[ "$use_gui" == "yes" ]]; then
                gui_mode_start
                return 0
            fi
        fi
    fi
    
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
        clone) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && clone_vm "$2" "$3" || 
            [[ -n "${2:-}" ]] && clone_vm "$2" "" || clone_vm_menu
            ;;
        list|list-vms) list_vms ;;
        launch) 
            [[ -n "${2:-}" ]] && launch_vm "$2" || launch_vm_menu
            ;;
        delete|del) 
            [[ -n "${2:-}" ]] && delete_vm "$2" || delete_vm_menu
            ;;
        
        # Multi-VM orchestration
        start-all) start_all_vms ;;
        stop-all) stop_all_vms ;;
        status-all) status_all_vms ;;
        suspend-all) suspend_all_vms ;;
        orchestration|orchestrate) orchestration_menu ;;
        
        # VM Resource Monitoring
        monitor) monitor_all_vms ;;
        monitor-vm) 
            [[ -n "${2:-}" ]] && monitor_vm "$2" || die "Please specify VM name" ;;
        monitor-dashboard) monitor_dashboard ;;
        monitor-menu) monitor_menu ;;
        stats-vm|vm-stats) 
            [[ -n "${2:-}" ]] && stats_vm "$2" || die "Please specify VM name" ;;
        
        # Debugging
        debug|debug-vm) 
            [[ -n "${2:-}" ]] && debug_start "$2" "$3" "$4" || debug_session_menu ;;
        debug|start-debug) 
            [[ -n "${2:-}" ]] && debug_vm "$2" "$3" "$4" || die "Usage: debug VM_NAME [BINARY_PATH] [PORT]"
            ;;
        debug-connect) debug_connect "$2" "$3" "$4" ;;
        debug-attach) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && debug_attach "$2" "$3" || die "Usage: debug-attach VM_NAME PORT"
            ;;
        debug-test) 
            [[ -n "${2:-}" ]] && debug_test "$2" "$3" || die "Usage: debug-test VM_NAME [PORT]"
            ;;
        debug-list) debug_list ;;
        debug-detach) debug_detach "$2" ;;
        deploy|deploy-binary) deploy_binary "$2" "$3" "$4" ;;
        debug-menu) debug_session_menu ;;
        
        # VM Export/Import
        export|export-vm) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && export_vm_qcow2 "$2" "$3" || export_vm_menu ;;
        export-qcow2) 
            [[ -n "${2:-}" ]] && export_vm_qcow2 "$2" "$3" || die "Please specify VM name" ;;
        export-vmdk) 
            [[ -n "${2:-}" ]] && export_vm_vmdk "$2" "$3" || die "Please specify VM name" ;;
        export-vdi) 
            [[ -n "${2:-}" ]] && export_vm_vdi "$2" "$3" || die "Please specify VM name" ;;
        export-raw) 
            [[ -n "${2:-}" ]] && export_vm_raw "$2" "$3" || die "Please specify VM name" ;;
        import|import-vm) 
            [[ -n "${2:-}" ]] && import_vm "$2" "$3" "$4" || import_vm_menu ;;
        
        # Platform presets
        macos-68k) launch_macos_68k ;;
        macos-ppc) launch_macos_ppc ;;
        macos-ppc64) launch_macos_ppc64 ;;
        macos-106|macos-10.6|snow-leopard) launch_macos_10_6_ppc ;;
        create-macos-106|create-snow-leopard) create_and_launch_macos_10_6_ppc ;;
        debug-macos-106|debug-snow-leopard) debug_macos_10_6_ppc ;;
        haiku) launch_haiku ;;
        linux) launch_linux ;;
        atari) launch_atari ;;
        amiga) launch_amiga ;;
        solaris-x86) launch_solaris_x86 ;;
        solaris-sparc) launch_solaris_sparc ;;
        windows-xp) launch_windows_xp ;;
        openstep) launch_openstep ;;
        custom) launch_custom ;;
        
        # Retro68 Development Tools
        retro68-check|check-retro68) check_retro68 ;;
        retro68-install|install-retro68) install_retro68 ;;
        retro68-setup|setup-retro68) setup_retro68_environment ;;
        retro68-compile|compile-retro68) 
            [[ -n "${2:-}" ]] && compile_with_retro68 "$2" || compile_with_retro68 ;;
        retro68-compile-test|compile-macos71-test) compile_macos71_test ;;
        retro68-debug|debug-retro68) retro68_debug_workflow ;;
        retro68-debug-vm|launch-68k-debug) launch_macos_68k_debug ;;
        
        # Advanced VM management
        stop|stop-vm) 
            [[ -n "${2:-}" ]] && stop_vm "$2" || stop_vm_menu ;;
        edit|edit-vm) 
            [[ -n "${2:-}" ]] && edit_vm "$2" || edit_vm_menu ;;
        create-env-config|env-config) create_env_config ;;
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
        configure-xdialog|setup-xdialog) configure_xdialog ;;
        configure-ramdisk|setup-ramdisk) configure_ramdisk ;;
        test-samba|test-samba-connection) test_samba_connection ;;
        test-netatalk|test-netatalk-connection) test_netatalk_connection ;;
        test-ssh|test-ssh-connection) test_ssh_connection ;;
        test-gdb|test-gdb-connection) test_gdb_connection ;;
        backup-config|backup) backup_configurations ;;
        list-backups) list_backups ;;
        restore-config|restore) 
            [[ -n "${2:-}" ]] && restore_configuration "$2" || backup_restore_menu ;;
        show-command|show-qemu-command) 
            [[ -n "${2:-}" ]] && show_qemu_command "$2" || die "Please specify VM name"
            ;;
        check-macports) check_macports ;;
        check-homebrew) check_homebrew ;;
        update-packages|update-pkg) update_package_manager ;;
        install-deps|install-dependencies) install_vm_dependencies ;;
        test-local-share) test_local_share ;;
        list-shares) list_shares ;;
        cleanup|cleanup-all) cleanup_menu ;;
        cleanup-snapshots) 
            [[ -n "${2:-}" ]] && cleanup_vm_snapshots "$2" "${3:-30}" || cleanup_all_snapshots ;;
        cleanup-disks) cleanup_unused_disks "${2:-true}" ;;
        
        # Toolchain management
        detect-toolchains|toolchains-detect) detect_cross_compilation_toolchains ;;
        list-toolchains|toolchains-list) list_detected_toolchains ;;
        configure-toolchain|toolchain-configure) 
            [[ -n "${2:-}" ]] && setup_toolchain_environment "$2" || configure_toolchain ;;
        
        # Build automation
        build-project|project-build) 
            [[ -n "${2:-}" ]] && build_project "$2" "$3" "$4" "$5" || die "Usage: build-project <project_name> [path] [arch] [toolchain] [output_dir]"
            ;;
        create-project|project-create) 
            [[ -n "${2:-}" ]] && create_dev_project "$2" "$3" "$4" || die "Usage: create-project <name> [template_type] [arch]"
            ;;
        list-projects|projects-list) list_projects ;;
        build-deploy-debug|workflow) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && build_deploy_debug_workflow "$2" "$3" "$4" "$5" "$6" "$7" || die "Usage: build-deploy-debug <project> <vm> [toolchain] [arch] [skip_build] [skip_deploy]"
            ;;
        
        # Source code mounting
        mount-source|source-mount) 
            [[ -n "${2:-}" ]] && mount_source_code "$2" "$3" "$4" "$5" || die "Usage: mount-source <vm_name> [source_dir] [mount_point] [readonly]"
            ;;
        unmount-source|source-unmount) 
            [[ -n "${2:-}" ]] && unmount_source_code "$2" "$3" || die "Usage: unmount-source <vm_name> [mount_point]"
            ;;
        list-mounts|mounts-list) 
            [[ -n "${2:-}" ]] && list_source_mounts "$2" || die "Usage: list-mounts <vm_name>"
            ;;
        
        # GUI Application Management
        launch-gui|gui-launch) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && launch_gui_application "$2" "$3" "$4" "$5" || die "Usage: launch-gui <vm_name> <app_path> [display] [use_xquartz]"
            ;;
        xquartz-opt|xquartz-optimize) configure_xquartz_optimization ;;
        
        # Testing Framework
        run-tests|tests-run) 
            [[ -n "${2:-}" ]] && run_vm_tests "$2" "$3" "$4" "$5" || die "Usage: run-tests <vm_name> [test_script] [test_type] [output_dir]"
            ;;
        create-test|test-create) create_test_config_interactive ;;
        list-tests|tests-list) list_test_configs ;;
        run-test|test-run) 
            [[ -n "${2:-}" ]] && run_test_config "$2" "$3" || die "Usage: run-test <config_file> [vm_name]"
            ;;
        
        # XDialog UI
        gui-mode) gui_mode_start ;;
        gui-create-vm) gui_create_vm ;;
        gui-manage) gui_manage_vms ;;
        gui-debug) gui_debug_vm ;;
        
        # Enhanced Deployment
        incremental-deploy|deploy-incremental) 
            [[ -n "${2:-}" ]] && incremental_deploy "$2" "$3" "$4" "$5" "$6" || die "Usage: incremental-deploy <vm_name> [source_dir] [target_dir] [backup_first] [exclude_patterns]"
            ;;
        validate-env|env-validate) 
            [[ -n "${2:-}" ]] && validate_environment "$2" "$3" || die "Usage: validate-env <vm_name> [requirements_file]"
            ;;
        rollback|deploy-rollback) 
            [[ -n "${2:-}" ]] && rollback_deployment "$2" "$3" "$4" || die "Usage: rollback <vm_name> [backup_id] [target_dir]"
            ;;
        deployment-history|history-deploy) 
            [[ -n "${2:-}" ]] && list_deployment_history "$2" || die "Usage: deployment-history <vm_name>"
            ;;
        cleanup-deploy|deploy-cleanup) 
            [[ -n "${2:-}" ]] && cleanup_deployment "$2" "$3" "$4" || die "Usage: cleanup-deploy <vm_name> [keep_backups] [target_dir]"
            ;;
        
        # Development Project Management - Snapshots
        project-snapshot|snapshot-project) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && create_project_snapshot "$2" "$3" "$4" || die "Usage: project-snapshot <project_name> [snapshot_name] [description]"
            ;;
        restore-snapshot|snapshot-restore) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && restore_project_snapshot "$2" "$3" "$4" || die "Usage: restore-snapshot <project_name> <snapshot_name> [restore_to]"
            ;;
        list-snapshots|snapshots-list) 
            [[ -n "${2:-}" ]] && list_project_snapshots "$2" || list_project_snapshots
            ;;
        delete-snapshot|snapshot-delete) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && delete_project_snapshot "$2" "$3" || die "Usage: delete-snapshot <project_name> <snapshot_name>"
            ;;
        
        # Debug Session Recording
        debug-record|record-debug) 
            [[ -n "${2:-}" ]] && start_debug_recording "$2" "$3" "$4" "$5" || die "Usage: debug-record <session_name> [vm_name] [gdb_port] [description]"
            ;;
        debug-stop|stop-debug) 
            [[ -n "${2:-}" ]] && stop_debug_recording "$2" || die "Usage: debug-stop <session_name>"
            ;;
        debug-replay|replay-debug) 
            [[ -n "${2:-}" ]] && replay_debug_session "$2" || die "Usage: debug-replay <session_name>"
            ;;
        list-sessions|sessions-list) list_debug_sessions ;;
        delete-session|session-delete) 
            [[ -n "${2:-}" ]] && delete_debug_session "$2" || die "Usage: delete-session <session_name>"
            ;;
        
        # Breakpoint Presets
        breakpoint-preset|preset-breakpoint) 
            [[ -n "${2:-}" ]] && create_breakpoint_preset "$2" "$3" "$4" || die "Usage: breakpoint-preset <preset_name> [description] [breakpoints_file]"
            ;;
        apply-preset|preset-apply) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && apply_breakpoint_preset "$2" "$3" "$4" || die "Usage: apply-preset <preset_name> <vm_name> [gdb_port]"
            ;;
        list-presets|presets-list) list_breakpoint_presets ;;
        delete-preset|preset-delete) 
            [[ -n "${2:-}" ]] && delete_breakpoint_preset "$2" || die "Usage: delete-preset <preset_name>"
            ;;
        
        # Multi-VM Debugging
        multi-debug|debug-multi) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && start_multi_debug "$2" "$3" "$4" "$5" "$6" "$7" || die "Usage: multi-debug <session_name> <vm1> <port1> [vm2 port2 ...]"
            ;;
        stop-multi-debug|multi-debug-stop) 
            [[ -n "${2:-}" ]] && stop_multi_debug "$2" || die "Usage: stop-multi-debug <session_name>"
            ;;
        list-multi-debug|multi-debug-list) list_multi_debug_sessions ;;
        delete-multi-debug|multi-debug-delete) 
            [[ -n "${2:-}" ]] && delete_multi_debug_session "$2" || die "Usage: delete-multi-debug <session_name>"
            ;;
        
        # Debug Symbol Management
        debug-symbols|symbols-debug) 
            [[ -n "${2:-}" ]] && download_debug_symbols "$2" "$3" "$4" || die "Usage: debug-symbols <binary_path> [output_dir] [url]"
            ;;
        debug-info|info-debug) 
            [[ -n "${2:-}" ]] && generate_debug_info "$2" "$3" || die "Usage: debug-info <binary_path> [output_dir]"
            ;;
        list-symbols|symbols-list) list_debug_symbols ;;
        delete-symbols|symbols-delete) 
            [[ -n "${2:-}" ]] && delete_debug_symbols "$2" || die "Usage: delete-symbols <binary_name>"
            ;;
        
        # Automatic GDB Configuration
        generate-gdb|gdb-generate) 
            [[ -n "${2:-}" ]] && generate_gdb_config "$2" "$3" "$4" "$5" || die "Usage: generate-gdb <arch> [output_file] [vm_name] [port]"
            ;;
        list-gdb-configs|gdb-configs-list) list_gdb_configs ;;
        delete-gdb-config|gdb-config-delete) 
            [[ -n "${2:-}" ]] && delete_gdb_config "$2" || die "Usage: delete-gdb-config <config_name>"
            ;;
        
        # Configuration Versioning & Backup
        config-backup|backup-config) 
            [[ -n "${2:-}" ]] && config_backup "$2" "$3" || die "Usage: config-backup <vm_name> [message]"
            ;;
        config-restore|restore-config) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && config_restore "$2" "$3" || die "Usage: config-restore <vm_name> <version_id>"
            ;;
        config-history|history-config) 
            [[ -n "${2:-}" ]] && config_history "$2" || die "Usage: config-history <vm_name>"
            ;;
        config-diff|diff-config) 
            [[ -n "${2:-}" ]] && config_diff "$2" "$3" "$4" || die "Usage: config-diff <vm_name> [version1] [version2]"
            ;;
        config-commit|commit-config) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && config_commit "$2" "$3" || die "Usage: config-commit <vm_name> <message>"
            ;;
        list-backups|backups-list) list_config_backups ;;
        
        # SPICE Advanced Features
        spice-start) 
            [[ -n "${2:-}" ]] && spice_start "$2" "${3:-}" "${4:-}" "${5:-}" || die "Usage: spice-start <vm_name> [port] [tls_port] [options]"
            ;;
        spice-connect) 
            [[ -n "${2:-}" ]] && spice_connect "$2" "${3:-}" || die "Usage: spice-connect <vm_name> [port]"
            ;;
        spice-config) 
            [[ -n "${2:-}" ]] && spice_config "$2" "${3:-}" "${4:-}" "${5:-}" "${6:-}" || die "Usage: spice-config <vm_name> [port] [tls_port] [tls_cert] [tls_key]"
            ;;
        spice-create-tls) 
            [[ -n "${2:-}" && -n "${3:-}" ]] && spice_create_tls "$2" "$3" "${4:-}" || die "Usage: spice-create-tls <cert_path> <key_path> [days]"
            ;;
        
        # Disk/ISO management
        disk-create|create-disk) create_disk_image ;;
        disk-convert|convert-disk) convert_disk_image ;;
        disk-resize|resize-disk) resize_disk_image ;;
        image-list|list-images) list_images ;;
        image-download|download-image) download_iso ;;
        image-detect|detect-images) detect_available_images ;;
        rom-detect|detect-roms) detect_available_roms ;;
        arch-detect|detect-architectures) detect_available_architectures ;;
        image-insert|insert-image) 
            [[ -n "${2:-}" ]] && insert_iso "$2" || insert_iso_menu ;;
        image-eject|eject-image) 
            [[ -n "${2:-}" ]] && eject_iso "$2" || eject_iso_menu ;;
        
        # UTM integration
        utm-export|export-utm) 
            [[ -n "${2:-}" ]] && export_utm "$2" || export_utm_menu ;;
        utm-create|create-utm) create_utm_vm ;;
        
        # Information
        qemu-version|version) show_qemu_version ;;
        architectures|archs) show_architectures ;;
        vm-configs|configs) show_vm_configs ;;
        snapshot|snapshot-menu) snapshot_menu ;;
        
        # Help
        help|--help|-h) show_usage ;;
        
        # Interactive / Default
        menu|*) show_main_menu ;;
    esac
}

main "$@"
