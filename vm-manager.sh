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
CONFIG_DIR="${HOME}/.vm-assistant"
VM_CONFIG_DIR="${SCRIPT_DIR}/vm-configs"
PATCHES_DIR="${SCRIPT_DIR}/patches"
QEMU_PREFIX="${QEMU_PREFIX:-${HOME}/.local/qemu-retro}"
QEMU_BIN_DIR="${QEMU_BIN_DIR:-${QEMU_PREFIX}/bin}"
QEMU_SRC_DIR="${QEMU_SRC_DIR:-${SCRIPT_DIR}/qemu-9.2.0}"
QEMU_BUILD_DIR="${QEMU_BUILD_DIR:-${QEMU_SRC_DIR}/build}"

# VM storage
VM_DIR="${CONFIG_DIR}/vms"
DISK_DIR="${CONFIG_DIR}/disks"
ISO_DIR="${CONFIG_DIR}/isos"
SHARE_DIR="/tmp/volatile_hd"
ROM_DIR="/tmp/volatile_hd/MacROMan/TestImages"
VM_IMAGE_DIR="${VM_IMAGE_DIR:-${HOME}/vm-images}"
VM_SHARED_DIR="${VM_SHARED_DIR:-${HOME}/vm-shared}"
VM_LOG_DIR="${VM_LOG_DIR:-${HOME}/vm-logs}"

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
DEFAULT_MACOS_SHARE_DIR="/tmp/volatile_hd"

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
    local dir="${VM_IMAGE_DIR}/${platform}"
    mkdir -p "${dir}"

    local images=()
    while IFS= read -r -d $'\0' f; do
        images+=("$f")
    done < <(find "${dir}" -maxdepth 1 \( -name '*.img' -o -name '*.qcow2' -o -name '*.iso' -o -name '*.dsk' -o -name '*.hda' \) -print0 2>/dev/null | sort -z)

    if [[ ${#images[@]} -eq 0 ]]; then
        warn "No disk images found in ${dir}"
        local create
        create=$(ask "Create a new blank 2 GiB image? (yes/no)" "yes")
        if is_yes "${create}"; then
            local imgname
            imgname=$(ask "Image filename" "${platform}-disk.qcow2")
            local size
            size=$(ask "Image size (e.g. 512M, 2G)" "2G")
            "$(qemu_bin qemu-img 2>/dev/null || echo qemu-img)" create -f qcow2 "${dir}/${imgname}" "${size}"
            echo "${dir}/${imgname}"
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
}

# Pick a CDROM/ISO image
pick_cdrom() {
    local platform="$1"
    local dir="${VM_IMAGE_DIR}/${platform}"

    local isos=()
    while IFS= read -r -d $'\0' f; do
        isos+=("$f")
    done < <(find "${dir}" -maxdepth 2 \( -name '*.iso' -o -name '*.img' \) -print0 2>/dev/null | sort -z)

    if [[ ${#isos[@]} -eq 0 ]]; then
        warn "No ISO/CD images found in ${dir}"
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
    log "Checking system dependencies..."
    
    local deps=("qemu-system-x86_64" "qemu-img" "curl" "tar" "make")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" >/dev/null 2>&1; then
            missing_deps+=("${dep}")
            warn "  ✗ ${dep} not found"
        else
            log "  ✓ ${dep}"
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        warn "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# ---------------------------------------------------------------------------
# QEMU Build Functions (from build_qemu.sh)
# ---------------------------------------------------------------------------

list_all_softmmu_targets() {
    local targets_dir="${QEMU_SRC_DIR}/configs/targets"
    [[ -d "${targets_dir}" ]] || return 1
    find "${targets_dir}" -maxdepth 1 -type f -name '*-softmmu.mak' \
        -exec sh -c 'for file_path in "$@"; do basename "$file_path" .mak; done' sh {} + \
        | sort
}

resolve_qemu_targets() {
    local targets=()
    if [[ "$(uname -m)" =~ x86_64|amd64|i386|i486|i586|i686 ]]; then
        if mapfile -t targets < <(list_all_softmmu_targets) && [[ ${#targets[@]} -gt 0 ]]; then
            log "x86 host detected — enabling all qemu-system-* targets."
        else
            warn "Could not enumerate all softmmu targets; using retro defaults."
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
    local config_dir="${VM_DIR}/${vm_name}"
    
    ensure_dir "${config_dir}"
    
    local config_file="${config_dir}/${vm_name}.conf"
    
    # Copy template if available
    if [[ -f "${VM_CONFIG_DIR}/${platform}.env" ]]; then
        cp "${VM_CONFIG_DIR}/${platform}.env" "${config_file}"
        log "Created VM config from template: ${config_file}"
    else
        # Create basic config
        cat > "${config_file}" <<EOF
# VM Configuration: ${vm_name}
# Platform: ${platform}
QEMU_BIN=qemu-system-${platform}
MACHINE=pc
CPU=host
RAM_MB=2048
HDD_IMAGE=${DISK_DIR}/${vm_name}.qcow2
DISPLAY_BACKEND=${DEFAULT_DISPLAY}
NETWORK_MODEL=e1000

# Option C: Debug & Network Settings
ENABLE_GDB=n
GDB_PORT=${DEFAULT_GDB_PORT}
ENABLE_SSH=n
SSH_PORT=${DEFAULT_SSH_PORT}
ENABLE_NETATALK=n
NETATALK_SHARE_NAME=VM_${vm_name}
SHARED_DIR=${DEFAULT_MACOS_SHARE_DIR}
EOF
        log "Created basic VM config: ${config_file}"
    fi
    
    echo "${config_file}"
}

# Create a disk image
create_disk() {
    local vm_name="$1"
    local disk_size="${2:-40G}"
    local disk_format="${3:-qcow2}"
    local disk_path="${DISK_DIR}/${vm_name}.qcow2"
    
    ensure_dir "${DISK_DIR}"
    
    local qemu_img
    qemu_img=$(qemu_bin "qemu-img")
    
    if [[ -f "${disk_path}" ]]; then
        warn "Disk already exists: ${disk_path}"
        return 0
    fi
    
    log "Creating disk: ${disk_path} (${disk_size}, ${disk_format})"
    "${qemu_img}" create -f "${disk_format}" "${disk_path}" "${disk_size}"
    log "Disk created successfully."
}

# List available ISOs
list_isos() {
    heading "Available ISOs"
    
    local iso_dirs=("${ISO_DIR}" "${VM_IMAGE_DIR}")
    local found=0
    
    for dir in "${iso_dirs[@]}"; do
        [[ -d "${dir}" ]] || continue
        log "Directory: ${dir}"
        while IFS= read -r -d '' iso_file; do
            log "  ${found}) $(basename "${iso_file}") [${iso_file}]"
            ((found++)) || true
        done < <(find "${dir}" -maxdepth 1 -type f \( -name "*.iso" -o -name "*.ISO" \) -print0 2>/dev/null | sort -z)
    done
    
    [[ $found -eq 0 ]] && warn "No ISOs found. Place ISOs in ${ISO_DIR}/ or ${VM_IMAGE_DIR}/"
    return 0
}

# Select an ISO interactively
select_iso() {
    local selected=""
    list_isos
    
    read -rp "Select ISO number (or enter path): " choice
    
    if [[ "${choice}" =~ ^[0-9]+$ ]]; then
        # Select by number
        local i=0
        for dir in "${ISO_DIR}" "${VM_IMAGE_DIR}"; do
            [[ -d "${dir}" ]] || continue
            while IFS= read -r -d '' iso_file; do
                if [[ $i -eq $((choice)) ]]; then
                    echo "${iso_file}"
                    return 0
                fi
                ((i++)) || true
            done < <(find "${dir}" -maxdepth 1 -type f \( -name "*.iso" -o -name "*.ISO" \) -print0 2>/dev/null | sort -z)
        done
        die "Invalid ISO selection"
    elif [[ -f "${choice}" ]]; then
        # Direct path
        echo "${choice}"
        return 0
    else
        die "ISO not found: ${choice}"
    fi
}

# List VMs
list_vms() {
    heading "Available VMs"
    
    [[ -d "${VM_DIR}" ]] || { warn "No VMs found. VM directory: ${VM_DIR}"; return 1; }
    
    local i=0
    for vm_conf in "${VM_DIR}"/*.conf; do
        [[ -f "${vm_conf}" ]] && {
            log "  ${i}) $(basename "${vm_conf}" .conf)"
            ((i++)) || true
        }
    done
    
    [[ $i -eq 0 ]] && warn "No VM configurations found in ${VM_DIR}/"
}

# Launch a VM
launch_vm() {
    local vm_name="$1"
    local config_file="${VM_DIR}/${vm_name}.conf"
    
    [[ -f "${config_file}" ]] || die "VM config not found: ${config_file}"
    
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
    local config_file="${VM_DIR}/${vm_name}.conf"
    
    [[ -f "${config_file}" ]] || die "VM not found: ${vm_name}"
    
    # Load config to get disk path
    source "${config_file}"
    
    log "Deleting VM: ${vm_name}"
    
    # Remove config
    rm -f "${config_file}"
    
    # Remove disk if it exists
    [[ -n "${HDD_IMAGE:-}" && -f "${HDD_IMAGE}" ]] && {
        log "Removing disk: ${HDD_IMAGE}"
        rm -f "${HDD_IMAGE}"
    }
    
    log "VM deleted successfully."
}

# Create a new VM
create_vm() {
    local vm_name vm_type disk_size iso_path
    
    vm_name=$(ask "VM name" "")
    [[ -z "${vm_name}" ]] && die "VM name cannot be empty"
    
    vm_type=$(ask "VM type (ppc/ppc64/x86_64/m68k/sparc)" "ppc")
    
    disk_size=$(ask "Disk size (e.g., 40G)" "40G")
    
    log "Creating VM: ${vm_name} (${vm_type})"
    
    # Create config
    create_vm_config "${vm_name}" "${vm_type}"
    
    # Create disk
    create_disk "${vm_name}" "${disk_size}"
    
    log "VM created successfully."
    log "To launch: ${SCRIPT_NAME} launch ${vm_name}"
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

# Export VM to UTM format
export_utm() {
    local vm_name="$1"
    local vm_dir="${VM_DIR}/${vm_name}"
    local config_file="${vm_dir}/config.env"

    [[ -d "${vm_dir}" ]] || die "VM directory not found: ${vm_dir}"
    [[ -f "${config_file}" ]] || die "VM config not found: ${config_file}"

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
    local utm_config_file="${vm_dir}/utm-config.json"
    
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
    heading "Creating UTM VM"
    
    detect_utm || { warn "UTM.app not found. Please install UTM.app from https://mac.getutm.app/"; return 1; }

    local vm_name
    vm_name=$(ask "VM name" "")
    [[ -z "${vm_name}" ]] && { warn "VM name cannot be empty"; return 1; }

    # VM directory
    local vm_dir="${VM_DIR}/${vm_name}"
    mkdir -p "${vm_dir}"

    # OS Type
    echo "Select OS Type:"
    echo "  1) macOS 9"
    echo "  2) macOS 10.4 (Tiger)"
    echo "  3) macOS 10.5 (Leopard)"
    echo "  4) Linux"
    echo "  5) Windows"
    echo "  6) DOS"
    read -rp "OS Type [1]: " utm_os_type_choice
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

    # Architecture
    echo "Select Architecture:"
    echo "  1) PowerPC (ppc)"
    echo "  2) x86_64"
    echo "  3) ARM64"
    echo "  4) ARM"
    echo "  5) SPARC"
    echo "  6) SPARC64"
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

    # Display mode
    read -rp "Display Mode [1=GUI/2=Terminal]: " utm_display_choice
    utm_display_choice=${utm_display_choice:-1}
    local utm_display=""
    case ${utm_display_choice} in
        1) utm_display="gui" ;;
        2) utm_display="terminal" ;;
        *) utm_display="gui" ;;
    esac

    # File sharing
    read -rp "Enable file sharing [y/N]: " utm_sharing
    utm_sharing=${utm_sharing:-n}
    local utm_sharing_path=""
    if [[ "${utm_sharing}" == "y" ]]; then
        read -rp "Share path [${SHARE_DIR}]: " utm_sharing_path_input
        utm_sharing_path="${utm_sharing_path_input:-${SHARE_DIR}}"
    fi

    # Clipboard sharing
    read -rp "Enable clipboard sharing [y/N]: " utm_clipboard
    utm_clipboard=${utm_clipboard:-n}

    # Memory
    local utm_memory
    utm_memory=$(ask_ram_size "RAM size (MiB)" "512")

    # CPU cores
    local utm_cores
    utm_cores=$(ask "CPU cores" "1")

    # Network
    read -rp "Enable VNC [y/N]: " utm_vnc
    utm_vnc=${utm_vnc:-n}
    local utm_vnc_port=5900
    if [[ "${utm_vnc}" == "y" ]]; then
        read -rp "VNC port [${utm_vnc_port}]: " utm_vnc_port_input
        utm_vnc_port="${utm_vnc_port_input:-${utm_vnc_port}}"
    fi

    # Create UTM configuration file
    local utm_config_file="${vm_dir}/config.json"
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
    cat > "${vm_dir}/metadata.env" << EOF
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

    log "UTM VM configuration created at: ${vm_dir}"
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
    local vm_dir="${VM_DIR}"
    local config_file="${vm_dir}/${vm_name}.conf"
    
    [[ -f "${config_file}" ]] || die "VM config not found: ${config_file}"
    
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
    local vm_dir="${VM_DIR}"
    local config_file="${vm_dir}/${vm_name}.conf"
    
    [[ -f "${config_file}" ]] || die "VM config not found: ${config_file}"
    
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
    local vm_dir="${VM_DIR}/${vm_name}"

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
                read -rp "Kill all QEMU processes for ${vm_name}? (y/N): " confirm
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
    
    read -rp "Select template [1-9]: " template_choice
    template_choice=${template_choice:-1}
    
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
    heading "Available ROM Files"
    
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
            done < <(find "${rom_dir}" -type f \( -iname "*.rom" -o -iname "*.bin" \) -print0 2>/dev/null)
        fi
    done

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
        log "No ROM files found."
        echo ""
        return 1
    fi
}

# List available disk images
list_disks() {
    heading "Available Disk Images"
    
    [[ -d "${DISK_DIR}" ]] || { warn "No disk directory: ${DISK_DIR}"; return 1; }
    
    local disks=()
    while IFS= read -r -d '' file; do
        disks+=("$file")
    done < <(find "${DISK_DIR}" -type f \( -iname "*.qcow2" -o -iname "*.img" -o -iname "*.raw" -o -iname "*.hda" -o -iname "*.dsk" \) -print0 2>/dev/null | sort -z)
    
    if [[ ${#disks[@]} -eq 0 ]]; then
        warn "No disk images found in ${DISK_DIR}"
        return 1
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
    
    return 0
}

# Edit VM configuration
edit_vm() {
    local vm_name="$1"
    local vm_dir="${VM_DIR}"
    local config_file="${vm_dir}/${vm_name}.conf"
    
    [[ -f "${config_file}" ]] || die "VM config not found: ${config_file}"
    
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
        
        read -rp "Select option [8]: " choice
        choice=${choice:-8}
        
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
        
        read -rp "Press Enter to continue..." _
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
        echo "  [14] Insert ISO into VM"
        echo "  [15] Eject ISO from VM"
        echo ""
        echo "🍎 UTM.app Integration:"
        echo "  [16] Create UTM VM configuration"
        echo "  [17] Export VM to UTM format"
        echo ""
        echo "🔧 Advanced VM Management:"
        echo "  [18] Stop a running VM"
        echo "  [19] Edit VM configuration"
        echo "  [20] List ROM files"
        echo "  [21] List disk images"
        echo ""
        echo "🚀 Quick Launch (Platform Presets):"
        echo "  [22] MacOS 68k (System 7-8.1)"
        echo "  [23] MacOS PPC (7.5.2-9.2.2, G3/G4)"
        echo "  [24] MacOS PPC64 (Mac OS X, G5)"
        echo "  [25] HaikuOS"
        echo "  [26] Linux (generic)"
        echo "  [27] Atari ST/TT/Falcon (68k)"
        echo "  [28] Commodore Amiga (68k/AROS)"
        echo "  [29] Solaris x86"
        echo "  [30] Solaris SPARC"
        echo "  [31] Windows XP"
        echo "  [32] OpenStep x86"
        echo "  [33] Custom QEMU (any architecture)"
        echo ""
        echo "📖 Information:"
        echo "  [34] Show QEMU version"
        echo "  [35] Show available architectures"
        echo "  [36] Show VM configurations"
        echo ""
        echo "❌ Exit:"
        echo "  [Q]  Quit"
        echo ""
        
        read -rp "Select option: " choice
        
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
            14) insert_iso_menu ;;
            15) eject_iso_menu ;;
            16) create_utm_vm ;;
            17) export_utm_menu ;;
            18) stop_vm_menu ;;
            19) edit_vm_menu ;;
            20) list_roms ;;
            21) list_disks ;;
            22) launch_macos_68k ;;
            23) launch_macos_ppc ;;
            24) launch_macos_ppc64 ;;
            25) launch_haiku ;;
            26) launch_linux ;;
            27) launch_atari ;;
            28) launch_amiga ;;
            29) launch_solaris_x86 ;;
            30) launch_solaris_sparc ;;
            31) launch_windows_xp ;;
            32) launch_openstep ;;
            33) launch_custom ;;
            34) show_qemu_version ;;
            35) show_architectures ;;
            36) show_vm_configs ;;
            q|quit|exit) exit 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
        
        read -rp "Press Enter to continue..." _
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
    read -rp "Select step: " step
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
    read -rp "Press Enter to continue..." _
}

launch_vm_menu() {
    list_vms
    [[ $? -ne 0 ]] && return 1
    read -rp "Select VM number to launch: " vm_num
    
    local i=0
    for vm_conf in "${VM_DIR}"/*.conf; do
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
    list_vms
    [[ $? -ne 0 ]] && return 1
    read -rp "Select VM number to delete: " vm_num
    
    local i=0
    for vm_conf in "${VM_DIR}"/*.conf; do
        [[ -f "${vm_conf}" ]] && {
            if [[ $i -eq $vm_num ]]; then
                local vm_name=$(basename "${vm_conf}" .conf)
                read -rp "Delete VM '${vm_name}'? (y/N): " confirm
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
    list_vms || return 1
    read -rp "Select VM number to insert ISO into: " vm_num
    
    local i=0
    for vm_conf in "${VM_DIR}"/*.conf; do
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
    list_vms || return 1
    read -rp "Select VM number to eject ISO from: " vm_num
    
    local i=0
    for vm_conf in "${VM_DIR}"/*.conf; do
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
    list_vms || return 1
    read -rp "Select VM number to export to UTM format: " vm_num
    
    local i=0
    for vm_conf in "${VM_DIR}"/*.conf; do
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
    list_vms || return 1
    read -rp "Select VM number to stop: " vm_num
    
    local i=0
    for vm_conf in "${VM_DIR}"/*.conf; do
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
    list_vms || return 1
    read -rp "Select VM number to edit: " vm_num
    
    local i=0
    for vm_conf in "${VM_DIR}"/*.conf; do
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
  iso-insert <vm>  Insert ISO into VM
  iso-eject <vm>  Eject ISO from VM

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
  menu             Interactive menu (default)
  help             Show this help

Environment Variables:
  QEMU_VERSION              QEMU version to build       (default: 9.2.0)
  QEMU_INSTALL_PREFIX       Installation prefix          (default: ~/.local/qemu-retro)
  VM_IMAGE_DIR              VM images directory          (default: ~/vm-images)
  VM_SHARED_DIR             Shared directory             (default: ~/vm-shared)
  VM_LOG_DIR                Logs directory               (default: ~/vm-logs)
  CONFIG_DIR                Config directory             (default: ~/.vm-assistant)

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
        
        # Disk/ISO management
        disk-create|create-disk) create_disk_image ;;
        disk-convert|convert-disk) convert_disk_image ;;
        disk-resize|resize-disk) resize_disk_image ;;
        iso-list|list-isos) list_isos ;;
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
