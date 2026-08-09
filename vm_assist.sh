#!/usr/bin/env bash
# shellcheck disable=SC2054  # QEMU CLI arguments commonly embed comma-separated suboptions
# =============================================================================
# vm_assist.sh — Interactive VM-assist launcher for retro QEMU environments
#
# Supported platforms:
#   • Apple MacOS 7.1 – 9.2.2  (m68k + PPC Old World / New World)
#   • Atari ST / STE / TT / Falcon  (m68k)
#   • Commodore Amiga  (m68k)
#   • HaikuOS  (i386 / x86_64)
#   • Solaris family  (x86 + SPARC)
#   • Windows XP  (i386)
#   • OpenStep  (i386)
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
VM_LOG_DIR="${VM_LOG_DIR:-${HOME}/vm-logs}"
DEFAULT_RAM_MB="${DEFAULT_RAM_MB:-256}"
DEFAULT_DISPLAY="${DEFAULT_DISPLAY:-sdl}"
VNC_PORT="${VNC_PORT:-5900}"
DEFAULT_GDB_BRIDGE_PORT="${DEFAULT_GDB_BRIDGE_PORT:-2346}"
DEFAULT_GDB_GUEST_PORT="${DEFAULT_GDB_GUEST_PORT:-2345}"
DEFAULT_QEMU_GDB_PORT="${DEFAULT_QEMU_GDB_PORT:-1234}"
DEFAULT_TLS_PROXY_HOST="${DEFAULT_TLS_PROXY_HOST:-10.0.2.2}"
DEFAULT_TLS_PROXY_PORT="${DEFAULT_TLS_PROXY_PORT:-8443}"
DEFAULT_AFP_HOST="${DEFAULT_AFP_HOST:-10.0.2.2}"
DEFAULT_AFP_PORT="${DEFAULT_AFP_PORT:-548}"
DEFAULT_MACOS_SHARE_DIR="${DEFAULT_MACOS_SHARE_DIR:-/tmp/volatile_hd}"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'

log()     { printf "${C_GREEN}[vm_assist]${C_RESET} %s\n" "$*"; }
warn()    { printf "${C_YELLOW}[vm_assist] WARN:${C_RESET} %s\n" "$*" >&2; }
die()     { printf "${C_RED}[vm_assist] ERROR:${C_RESET} %s\n" "$*" >&2; exit 1; }
heading() { printf "\n${C_CYAN}${C_BOLD}=== %s ===${C_RESET}\n\n" "$*"; }

# ---------------------------------------------------------------------------
# Resolve QEMU binary (system-wide fallback)
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

# Resolve qemu-img (checks QEMU_BIN_DIR first, then PATH)
qemu_img_bin() {
    qemu_bin "qemu-img"
}

# ---------------------------------------------------------------------------
# Utility: ask for a value with a default
# ---------------------------------------------------------------------------
ask() {
    local prompt="$1" default="$2" answer
    read -rp "$(printf '%b%s%b [%s]: ' "${C_BOLD}" "${prompt}" "${C_RESET}" "${default}")" answer
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

is_yes() {
    case "${1,,}" in
        y|yes|true|1|on) return 0 ;;
        *) return 1 ;;
    esac
}

trim_spaces() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    echo "${value}"
}

file_size_bytes() {
    local path="$1"
    if stat -c '%s' "${path}" >/dev/null 2>&1; then
        stat -c '%s' "${path}"
    elif stat -f '%z' "${path}" >/dev/null 2>&1; then
        stat -f '%z' "${path}"
    else
        echo 0
    fi
}

merge_csv_values() {
    local first
    first=$(trim_spaces "${1:-}")
    local second
    second=$(trim_spaces "${2:-}")

    if [[ -n "${first}" && -n "${second}" ]]; then
        echo "${first},${second}"
    elif [[ -n "${first}" ]]; then
        echo "${first}"
    else
        echo "${second}"
    fi
}

config_path() {
    local name="$1"
    echo "${VM_CONFIG_DIR}/${name}.env"
}

append_extra_display_devices() {
    local -n _display_cmd="$1"
    local spec
    spec=$(trim_spaces "${2:-}")
    [[ -n "${spec}" ]] || return 0

    local IFS=';'
    local -a devices=()
    read -r -a devices <<< "${spec}"

    local device
    for device in "${devices[@]}"; do
        device=$(trim_spaces "${device}")
        [[ -n "${device}" ]] || continue
        _display_cmd+=(-device "${device}")
    done
}

append_firmware_attachment() {
    local -n _firmware_cmd="$1"
    local firmware_path="$2"
    local firmware_mode="${3:-auto}"
    local firmware_label="${4:-firmware/ROM}"
    firmware_path=$(trim_spaces "${firmware_path}")
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

# ---------------------------------------------------------------------------
# Utility: pick a disk image from VM_IMAGE_DIR
# ---------------------------------------------------------------------------
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
            "$(qemu_img_bin)" create -f qcow2 "${dir}/${imgname}" "${size}"
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

# ---------------------------------------------------------------------------
# Utility: pick an ISO / CD-ROM image
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Utility: create a shared 9P virtfs directory
# ---------------------------------------------------------------------------
ensure_shared_dir() {
    local path="${1:-${VM_SHARED_DIR}}"
    mkdir -p "${path}"
    echo "${path}"
}

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
            pair=$(trim_spaces "${pair}")
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

ask_port_forwards() {
    local default_value="${1:-}"
    ask "TCP forwards host:guest (comma-separated, blank to skip)" "${default_value}"
}

ask_gdb_bridge_forward() {
    local default_port="${1:-${DEFAULT_GDB_BRIDGE_PORT}}"
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

ask_m68k_cpu() {
    local default_cpu="${1:-m68040}"
    ask "68k CPU (m68000/m68010/m68020/m68030/m68040)" "${default_cpu}"
}

ask_ppc_cpu() {
    local default_cpu="${1:-7455}"
    ask "PowerPC CPU (601/604/7455)" "${default_cpu}"
}

# Ask for SMP topology (sockets × cores).  Returns a -smp flag string like
# "2,sockets=2,cores=1" ready for use as:  -smp <result>
ask_ppc_smp() {
    local default_sockets="${1:-1}" default_cores="${2:-1}"
    local sockets cores
    sockets=$(ask "CPU sockets (1 = single, 2 = dual like G4 MDD / G5 Dual)" "${default_sockets}")
    cores=$(ask "Cores per socket" "${default_cores}")
    local total=$(( sockets * cores ))
    printf '%d,sockets=%d,cores=%d' "${total}" "${sockets}" "${cores}"
}

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

# ---------------------------------------------------------------------------
# Utility: populate an array with display/audio flags
# Usage:  local -a dflags; display_flags dflags "${display}"
# ---------------------------------------------------------------------------
display_flags() {
    local -n _df_array="$1"
    local display="${2:-${DEFAULT_DISPLAY}}"
    case "${display}" in
        sdl)    _df_array=(-display sdl    -audiodev sdl,id=snd0)  ;;
        gtk)    _df_array=(-display gtk    -audiodev pa,id=snd0)   ;;
        vnc)    _df_array=(-display vnc=:0 -audiodev none,id=snd0) ;;
        curses) _df_array=(-display curses -audiodev none,id=snd0) ;;
        none)   _df_array=(-display none   -audiodev none,id=snd0) ;;
        *)      _df_array=(-display "${display}" -audiodev none,id=snd0) ;;
    esac
}

# ---------------------------------------------------------------------------
# PLATFORM: MacOS 68k (System 7.1 – 7.6, Mac OS 8.0 – 8.1)
# Machine: q800 (Quadra 800 — m68040)
# ---------------------------------------------------------------------------
launch_macos_68k() {
    heading "MacOS 68k (System 7.x / Mac OS 8.x)"
    log "Machine: QEMU q800 (Motorola 68040, up to 256 MB RAM)"
    log "Reference config: $(config_path "macos-68k")"

    local qemu
    qemu=$(qemu_bin "qemu-system-m68k")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 512M / 4G)" "128")
    local cpu
    cpu=$(ask_m68k_cpu "m68040")
    local disk
    disk=$(pick_image "macos-68k")
    local cdrom
    cdrom=$(pick_cdrom "macos-68k")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
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

    local -a dflags; display_flags dflags "${display}"
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

# ---------------------------------------------------------------------------
# PLATFORM: MacOS PPC (Mac OS 7.5.2 – 9.2.2, G3/G4)
# Machine: mac99 (G3/G4) — requires OpenBIOS or proprietary ROM
# SMP note: mac99 with cpu 7455 supports up to 2 sockets (G4 MDD dual-processor).
# ---------------------------------------------------------------------------
launch_macos_ppc() {
    heading "MacOS PPC (Mac OS 7.5.2 – 9.2.2)"
    log "Machine: QEMU mac99 (PowerPC G3/G4)"
    log "Note: You need a Mac ROM image (Old World: 'mac.rom') or Apple firmware."
    log "Place it in: ${VM_IMAGE_DIR}/macos-ppc/"
    log "Dual-processor tip: choose 2 sockets to emulate a G4 MDD (7455×2)."
    log "Reference config: $(config_path "macos-ppc")"

    local qemu
    qemu=$(qemu_bin "qemu-system-ppc")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 512M / 4G)" "${DEFAULT_RAM_MB}")
    local cpu
    cpu=$(ask_ppc_cpu "7455")
    local smp_flags
    smp_flags=$(ask_ppc_smp "1" "1")
    local disk
    disk=$(pick_image "macos-ppc")
    local cdrom
    cdrom=$(pick_cdrom "macos-ppc")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
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

    local -a dflags; display_flags dflags "${display}"
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

# ---------------------------------------------------------------------------
# PLATFORM: MacOS PPC G5 / Mac OS X (ppc64)
# Machine: mac99 via qemu-system-ppc64 — emulates G5 single or dual-processor
# CPU: 970 (G5), 970fx, 970mp (dual-core die, used in late G5 towers)
# SMP: use 2 sockets to emulate Power Mac G5 Dual (2005) or G5 Dual Core
# Note: Mac OS X 10.2.7+ supports the G5; use a Panther/Tiger/Leopard image.
# ---------------------------------------------------------------------------
launch_macos_ppc64() {
    heading "MacOS PPC G5 (Mac OS X — ppc64)"
    log "Machine: QEMU mac99 via qemu-system-ppc64 (PowerPC G5 / 970)"
    log "Dual-processor tip: choose 2 sockets to emulate a Power Mac G5 Dual."
    log "  970    — single G5 processor"
    log "  970fx  — revised G5 (lower power)"
    log "  970mp  — dual-core G5 die (2 cores per socket)"
    log "Reference config: $(config_path "macos-ppc64")"

    local qemu
    qemu=$(qemu_bin "qemu-system-ppc64")

    local ram
    ram=$(ask_ram_size "RAM size (MiB or suffix such as 512M / 4G)" "512")
    local cpu
    cpu=$(ask "PowerPC 64-bit CPU (970/970fx/970mp)" "970")
    local smp_flags
    smp_flags=$(ask_ppc_smp "1" "1")
    local disk
    disk=$(pick_image "macos-ppc64")
    local cdrom
    cdrom=$(pick_cdrom "macos-ppc64")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")
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

    local -a dflags; display_flags dflags "${display}"
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
    "${cmd[@]}" 2>&1 | tee "${VM_LOG_DIR}/macos-ppc64-$(date +%Y%m%d-%H%M%S).log"
}

# ---------------------------------------------------------------------------
# PLATFORM: Atari ST / STE / TT / Falcon (m68k)
# Machine: QEMU m68k-virt — Hatari is more accurate for Atari; kept as fallback
# ---------------------------------------------------------------------------
launch_atari() {
    heading "Atari ST / STE / TT / Falcon (68k)"
    log "Best experience: use Hatari emulator for cycle-accurate Atari emulation."
    log "This script provides a basic QEMU m68k launch."

    local qemu
    qemu=$(qemu_bin "qemu-system-m68k")

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

    local -a dflags; display_flags dflags "${display}"

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
    qemu=$(qemu_bin "qemu-system-m68k")

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

    local -a dflags; display_flags dflags "${display}"

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
# PLATFORM: HaikuOS (i386 / x86_64)
# ---------------------------------------------------------------------------
launch_haiku() {
    heading "HaikuOS (x86 / x86_64)"
    log "Download Haiku nightlies or releases from https://www.haiku-os.org/get-haiku"
    log "Reference config: $(config_path "haiku")"

    local arch
    arch=$(ask "Architecture (i386/x86_64)" "x86_64")
    local qemu
    if [[ "${arch}" == "i386" ]]; then
        qemu=$(qemu_bin "qemu-system-i386")
    else
        qemu=$(qemu_bin "qemu-system-x86_64")
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

    local -a dflags; display_flags dflags "${display}"
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
    append_extra_display_devices cmd "${extra_displays}"
    append_firmware_attachment cmd "${firmware_path}" "${firmware_mode}" "ROM / firmware"

    if is_yes "${kvm}" && [[ -e /dev/kvm ]]; then
        cmd+=(-enable-kvm -cpu host)
    else
        cmd+=(-cpu qemu64)
    fi

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

# ---------------------------------------------------------------------------
# PLATFORM: Solaris x86 / x86_64
# ---------------------------------------------------------------------------
launch_solaris_x86() {
    heading "Solaris x86"
    log "Suitable for Solaris 8/9/10 x86 install media and related illumos-family experiments."
    log "Reference config: $(config_path "solaris-x86")"

    local qemu
    qemu=$(qemu_bin "qemu-system-i386")

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

    local -a dflags; display_flags dflags "${display}"
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
    qemu=$(qemu_bin "qemu-system-sparc64")

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

    local -a dflags; display_flags dflags "${display}"
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
    qemu=$(qemu_bin "qemu-system-i386")

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

    local -a dflags; display_flags dflags "${display}"
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
    qemu=$(qemu_bin "qemu-system-i386")

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

    local -a dflags; display_flags dflags "${display}"
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
# PLATFORM: Generic / Custom
# ---------------------------------------------------------------------------
launch_custom() {
    heading "Custom QEMU invocation"

    local arch
    arch=$(ask "QEMU system emulator (e.g. x86_64, i386, m68k, ppc, ppc64)" "x86_64")
    arch="${arch#qemu-system-}"
    [[ "${arch}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Invalid QEMU emulator suffix '${arch}'. Use values like x86_64, i386, m68k, ppc, or ppc64."
    local qemu
    qemu=$(qemu_bin "qemu-system-${arch}")

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
    network_model=$(ask "Network model (leave blank for user networking default)" "e1000")
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

    local -a dflags; display_flags dflags "${display}"
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
# Disk image management menu
# ---------------------------------------------------------------------------
manage_images() {
    heading "Disk Image Management"
    printf '%s\n' \
        "  1) Create new blank qcow2 image" \
        "  2) Convert image format (raw ↔ qcow2)" \
        "  3) Resize existing image" \
        "  4) Show image info" \
        "  5) Back to main menu"
    local choice
    choice=$(ask "Select" "1")
    case "${choice}" in
        1)
            local name size dest
            dest=$(ask "Destination directory" "${VM_IMAGE_DIR}/custom")
            mkdir -p "${dest}"
            name=$(ask "Filename" "disk.qcow2")
            size=$(ask "Size (e.g. 512M, 2G, 8G)" "2G")
            "$(qemu_img_bin)" create -f qcow2 "${dest}/${name}" "${size}"
            log "Created ${dest}/${name}"
            ;;
        2)
            local src dst fmt
            src=$(ask "Source image path" "")
            dst=$(ask "Destination path" "")
            fmt=$(ask "Target format (qcow2/raw/vmdk/vdi)" "qcow2")
            "$(qemu_img_bin)" convert -p -O "${fmt}" "${src}" "${dst}"
            log "Converted to ${dst}"
            ;;
        3)
            local img newsize
            img=$(ask "Image path" "")
            newsize=$(ask "New size (e.g. +2G or absolute 10G)" "")
            "$(qemu_img_bin)" resize "${img}" "${newsize}"
            log "Resized ${img} to ${newsize}"
            ;;
        4)
            local img
            img=$(ask "Image path" "")
            "$(qemu_img_bin)" info "${img}"
            ;;
        5) return ;;
    esac
}

# ---------------------------------------------------------------------------
# Main interactive menu
# ---------------------------------------------------------------------------
main_menu() {
    while true; do
        clear
        printf '%b%b' "${C_CYAN}" "${C_BOLD}"
        cat <<'BANNER'
  ██████  ███████ ████████ ██████   ██████      ██████  ███████ ████████ ██████   ██████
 ██    ██ ██         ██    ██   ██ ██    ██     ██    ██ ██         ██    ██   ██ ██    ██
 ██    ██ █████      ██    ██████  ██    ██     ██████  █████      ██    ██████  ██    ██
 ██    ██ ██         ██    ██   ██ ██    ██     ██   ██ ██         ██    ██   ██ ██    ██
  ██████  ███████    ██    ██   ██  ██████      ██   ██ ███████    ██    ██   ██  ██████
BANNER
        printf '%b' "${C_RESET}"
        printf '\n%b  VM-Assist — Retro QEMU Launcher%b\n' "${C_BOLD}" "${C_RESET}"
        printf "  QEMU prefix : %s\n"  "${QEMU_PREFIX}"
        printf "  Images dir  : %s\n"  "${VM_IMAGE_DIR}"
        printf "  Shared dir  : %s\n\n" "${VM_SHARED_DIR}"

        printf '%s\n' \
            "  ─── Retro Platforms ─────────────────────────" \
            "  1) MacOS 68k   (System 7.x / Mac OS 8.x, Quadra 800)" \
            "  2) MacOS PPC   (Mac OS 7.5.2 – 9.2.2, G3/G4, SMP)" \
            "  3) MacOS PPC G5 (Mac OS X, ppc64 970/970fx/970mp, SMP)" \
            "  4) Atari ST/STE/TT/Falcon  (68k)" \
            "  5) Amiga       (68k, AROS or FS-UAE)" \
            "  6) HaikuOS     (i386 / x86_64)" \
            "  7) Solaris x86 (Solaris / illumos)" \
            "  8) Solaris SPARC (sun4u)" \
            "  9) Windows XP  (i386)" \
            " 10) OpenStep    (i386)" \
            "  ─── Tools ───────────────────────────────────" \
            " 11) Custom / Generic QEMU launch" \
            " 12) Disk image management" \
            "  q) Quit"
        printf '\n'

        local choice
        choice=$(ask "Select" "q")
        case "${choice}" in
            1) launch_macos_68k ;;
            2) launch_macos_ppc ;;
            3) launch_macos_ppc64 ;;
            4) launch_atari ;;
            5) launch_amiga ;;
            6) launch_haiku ;;
            7) launch_solaris_x86 ;;
            8) launch_solaris_sparc ;;
            9) launch_windows_xp ;;
            10) launch_openstep ;;
            11) launch_custom ;;
            12) manage_images ;;
            q|Q|quit|exit) log "Goodbye!"; exit 0 ;;
            *) warn "Unknown option '${choice}'" ;;
        esac
        printf '\n'
        read -rp "Press ENTER to return to the menu …" _
    done
}

# ---------------------------------------------------------------------------
# CLI mode: allow non-interactive usage
# ---------------------------------------------------------------------------
show_help() {
    cat <<EOF
Usage: $(basename "$0") [PLATFORM]

Platforms (non-interactive):
  macos-68k    Launch MacOS 68k VM
  macos-ppc    Launch MacOS PPC VM (G3/G4, SMP)
  macos-ppc64  Launch MacOS PPC G5 VM (ppc64 970/970fx/970mp, SMP)
  atari        Launch Atari ST/STE/TT/Falcon VM
  amiga        Launch Amiga / AROS VM
  haiku        Launch HaikuOS VM
  solaris-x86  Launch Solaris x86 VM
  solaris-sparc Launch Solaris SPARC VM
  windows-xp   Launch Windows XP VM
  openstep     Launch OpenStep x86 VM
  custom       Launch custom QEMU instance
  images       Open disk image management
  (no args)    Interactive menu

Environment variables:
  QEMU_PREFIX       Path to custom QEMU installation  (default: ${QEMU_PREFIX})
  QEMU_BIN_DIR      Path to QEMU binaries             (default: ${QEMU_BIN_DIR})
  VM_IMAGE_DIR      Base directory for disk images    (default: ${VM_IMAGE_DIR})
  VM_SHARED_DIR     Host directory shared with VMs    (default: ${VM_SHARED_DIR})
  VM_LOG_DIR        VM session log directory          (default: ${VM_LOG_DIR})
  DEFAULT_RAM_MB    Default RAM for new VMs           (default: ${DEFAULT_RAM_MB})
  DEFAULT_DISPLAY   Default display backend           (default: ${DEFAULT_DISPLAY})
EOF
}

main() {
    case "${1:-menu}" in
        macos-68k)  launch_macos_68k ;;
        macos-ppc)  launch_macos_ppc ;;
        macos-ppc64) launch_macos_ppc64 ;;
        atari)      launch_atari ;;
        amiga)      launch_amiga ;;
        haiku)      launch_haiku ;;
        solaris-x86) launch_solaris_x86 ;;
        solaris-sparc) launch_solaris_sparc ;;
        windows-xp) launch_windows_xp ;;
        openstep)   launch_openstep ;;
        custom)     launch_custom ;;
        images)     manage_images ;;
        menu)       main_menu ;;
        help|--help|-h) show_help ;;
        *) die "Unknown platform '${1}'. Run '$(basename "$0") help' for usage." ;;
    esac
}

main "$@"
