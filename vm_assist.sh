#!/usr/bin/env bash
# =============================================================================
# vm_assist.sh — Interactive VM-assist launcher for retro QEMU environments
#
# Supported platforms:
#   • Apple MacOS 7.1 – 9.2.2  (m68k + PPC Old World / New World)
#   • Atari ST / STE / TT / Falcon  (m68k)
#   • Commodore Amiga  (m68k)
#   • HaikuOS  (i386 / x86_64)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — override with environment variables
# ---------------------------------------------------------------------------
QEMU_PREFIX="${QEMU_PREFIX:-${HOME}/.local/qemu-retro}"
QEMU_BIN_DIR="${QEMU_BIN_DIR:-${QEMU_PREFIX}/bin}"
VM_IMAGE_DIR="${VM_IMAGE_DIR:-${HOME}/vm-images}"
VM_SHARED_DIR="${VM_SHARED_DIR:-${HOME}/vm-shared}"
VM_LOG_DIR="${VM_LOG_DIR:-${HOME}/vm-logs}"
DEFAULT_RAM_MB="${DEFAULT_RAM_MB:-256}"
DEFAULT_DISPLAY="${DEFAULT_DISPLAY:-sdl}"
VNC_PORT="${VNC_PORT:-5900}"

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

# ---------------------------------------------------------------------------
# Utility: ask for a value with a default
# ---------------------------------------------------------------------------
ask() {
    local prompt="$1" default="$2" answer
    read -rp "$(printf "${C_BOLD}${prompt}${C_RESET} [${default}]: ")" answer
    echo "${answer:-${default}}"
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
        if [[ "${create}" == "yes" ]]; then
            local imgname
            imgname=$(ask "Image filename" "${platform}-disk.qcow2")
            local size
            size=$(ask "Image size (e.g. 512M, 2G)" "2G")
            qemu-img create -f qcow2 "${dir}/${imgname}" "${size}"
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
    echo "${images[$((choice - 1))]}"
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
        ask "Enter full path to ISO (or leave blank to skip)" ""
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
    else
        echo "${isos[$((choice - 1))]}"
    fi
}

# ---------------------------------------------------------------------------
# Utility: create a shared 9P virtfs directory
# ---------------------------------------------------------------------------
ensure_shared_dir() {
    mkdir -p "${VM_SHARED_DIR}"
    echo "${VM_SHARED_DIR}"
}

# ---------------------------------------------------------------------------
# Utility: build common display/audio flags
# ---------------------------------------------------------------------------
display_flags() {
    local display="${1:-${DEFAULT_DISPLAY}}"
    case "${display}" in
        sdl)    echo "-display sdl -audiodev sdl,id=snd0" ;;
        gtk)    echo "-display gtk -audiodev pa,id=snd0" ;;
        vnc)    echo "-display vnc=:0 -audiodev none,id=snd0" ;;
        curses) echo "-display curses -audiodev none,id=snd0" ;;
        none)   echo "-display none -audiodev none,id=snd0" ;;
        *)      echo "-display ${display} -audiodev none,id=snd0" ;;
    esac
}

# ---------------------------------------------------------------------------
# PLATFORM: MacOS 68k (System 7.1 – 7.6, Mac OS 8.0 – 8.1)
# Machine: q800 (Quadra 800 — m68040)
# ---------------------------------------------------------------------------
launch_macos_68k() {
    heading "MacOS 68k (System 7.x / Mac OS 8.x)"
    log "Machine: QEMU q800 (Motorola 68040, up to 256 MB RAM)"

    local qemu
    qemu=$(qemu_bin "qemu-system-m68k")

    local ram
    ram=$(ask "RAM in MiB" "128")
    local disk
    disk=$(pick_image "macos-68k")
    local cdrom
    cdrom=$(pick_cdrom "macos-68k")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")

    local cmd=(
        "${qemu}"
        -machine q800
        -m "${ram}"
        -cpu m68040
        $(display_flags "${display}")
        -device nubus-macfb
        -nic user,model=dp83932
        -rtc base=localtime
    )

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
# PLATFORM: MacOS PPC Old World (Mac OS 7.5.2 – 9.2.2, iMac G3 era)
# Machine: mac99 (G3/G4) — requires OpenBIOS or proprietary ROM
# ---------------------------------------------------------------------------
launch_macos_ppc() {
    heading "MacOS PPC (Mac OS 7.5.2 – 9.2.2)"
    log "Machine: QEMU mac99 (PowerPC G3/G4)"
    log "Note: You need a Mac ROM image (Old World: 'mac.rom') or Apple firmware."
    log "Place it in: ${VM_IMAGE_DIR}/macos-ppc/"

    local qemu
    qemu=$(qemu_bin "qemu-system-ppc")

    local ram
    ram=$(ask "RAM in MiB" "${DEFAULT_RAM_MB}")
    local disk
    disk=$(pick_image "macos-ppc")
    local cdrom
    cdrom=$(pick_cdrom "macos-ppc")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")

    local rom_dir="${VM_IMAGE_DIR}/macos-ppc"
    local prom_file
    prom_file=$(ask "Path to ROM/BIOS file (leave blank for OpenBIOS)" "")

    local cmd=(
        "${qemu}"
        -machine mac99,via=pmu
        -m "${ram}"
        -cpu G4
        $(display_flags "${display}")
        -device VGA,vgamem_mb=16
        -device usb-kbd
        -device usb-mouse
        -nic user,model=sungem
        -rtc base=localtime
    )

    if [[ -n "${prom_file}" && -f "${prom_file}" ]]; then
        cmd+=(-bios "${prom_file}")
    fi
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
        local tos_img
        tos_img=$(ask "Path to TOS ROM image" "${VM_IMAGE_DIR}/atari/tos.img")
        hatari --tos "${tos_img}" --harddrive "$(dirname "${disk}")" &
        return
    fi

    local ram
    ram=$(ask "RAM in MiB (max 14 for ST, 128 for TT/Falcon)" "14")
    local disk
    disk=$(pick_image "atari")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")

    local cmd=(
        "${qemu}"
        -machine virt
        -m "${ram}"
        -cpu m68040
        $(display_flags "${display}")
        -nic user
        -rtc base=localtime
    )
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
    ram=$(ask "RAM in MiB" "128")
    local disk
    disk=$(pick_image "amiga-aros")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses)" "${DEFAULT_DISPLAY}")

    local cmd=(
        "${qemu}"
        -machine virt
        -m "${ram}"
        -cpu m68040
        $(display_flags "${display}")
        -nic user
        -rtc base=localtime
    )
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

    local arch
    arch=$(ask "Architecture (i386/x86_64)" "x86_64")
    local qemu
    if [[ "${arch}" == "i386" ]]; then
        qemu=$(qemu_bin "qemu-system-i386")
    else
        qemu=$(qemu_bin "qemu-system-x86_64")
    fi

    local ram
    ram=$(ask "RAM in MiB" "512")
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
    shared_dir=$(ensure_shared_dir)

    local cmd=(
        "${qemu}"
        -machine q35
        -m "${ram}"
        -smp "${cores}"
        $(display_flags "${display}")
        -device VGA,vgamem_mb=32
        -device usb-ehci
        -device usb-kbd
        -device usb-mouse
        -nic user,model=e1000
        -rtc base=localtime
        -virtfs local,path="${shared_dir}",mount_tag=shared,security_model=mapped-xattr
    )

    if [[ "${kvm}" == "yes" ]] && [[ -e /dev/kvm ]]; then
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
# PLATFORM: Generic / Custom
# ---------------------------------------------------------------------------
launch_custom() {
    heading "Custom QEMU invocation"

    local arch
    arch=$(ask "QEMU system emulator (e.g. x86_64, i386, m68k, ppc, ppc64)" "x86_64")
    local qemu
    qemu=$(qemu_bin "qemu-system-${arch}")

    local machine
    machine=$(ask "Machine type (leave blank for default)" "")
    local cpu
    cpu=$(ask "CPU model (leave blank for default)" "")
    local ram
    ram=$(ask "RAM in MiB" "${DEFAULT_RAM_MB}")
    local disk
    disk=$(pick_image "custom-${arch}")
    local cdrom
    cdrom=$(pick_cdrom "custom-${arch}")
    local display
    display=$(ask "Display (sdl/gtk/vnc/curses/none)" "${DEFAULT_DISPLAY}")
    local extra
    extra=$(ask "Extra QEMU flags (optional)" "")

    local cmd=("${qemu}" -m "${ram}" $(display_flags "${display}"))
    [[ -n "${machine}" ]] && cmd+=(-machine "${machine}")
    [[ -n "${cpu}" ]]     && cmd+=(-cpu "${cpu}")
    [[ -n "${disk}" ]]    && cmd+=(-hda "${disk}")
    [[ -n "${cdrom}" ]]   && cmd+=(-cdrom "${cdrom}" -boot d)
    [[ -n "${extra}" ]]   && cmd+=(${extra})

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
            qemu-img create -f qcow2 "${dest}/${name}" "${size}"
            log "Created ${dest}/${name}"
            ;;
        2)
            local src dst fmt
            src=$(ask "Source image path" "")
            dst=$(ask "Destination path" "")
            fmt=$(ask "Target format (qcow2/raw/vmdk/vdi)" "qcow2")
            qemu-img convert -p -O "${fmt}" "${src}" "${dst}"
            log "Converted to ${dst}"
            ;;
        3)
            local img newsize
            img=$(ask "Image path" "")
            newsize=$(ask "New size (e.g. +2G or absolute 10G)" "")
            qemu-img resize "${img}" "${newsize}"
            log "Resized ${img} to ${newsize}"
            ;;
        4)
            local img
            img=$(ask "Image path" "")
            qemu-img info "${img}"
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
        printf "${C_CYAN}${C_BOLD}"
        cat <<'BANNER'
  ██████  ███████ ████████ ██████   ██████      ██████  ███████ ████████ ██████   ██████
 ██    ██ ██         ██    ██   ██ ██    ██     ██    ██ ██         ██    ██   ██ ██    ██
 ██    ██ █████      ██    ██████  ██    ██     ██████  █████      ██    ██████  ██    ██
 ██    ██ ██         ██    ██   ██ ██    ██     ██   ██ ██         ██    ██   ██ ██    ██
  ██████  ███████    ██    ██   ██  ██████      ██   ██ ███████    ██    ██   ██  ██████
BANNER
        printf "${C_RESET}"
        printf "\n${C_BOLD}  VM-Assist — Retro QEMU Launcher${C_RESET}\n"
        printf "  QEMU prefix : %s\n"  "${QEMU_PREFIX}"
        printf "  Images dir  : %s\n"  "${VM_IMAGE_DIR}"
        printf "  Shared dir  : %s\n\n" "${VM_SHARED_DIR}"

        printf '%s\n' \
            "  ─── Retro Platforms ─────────────────────────" \
            "  1) MacOS 68k   (System 7.x / Mac OS 8.x, Quadra 800)" \
            "  2) MacOS PPC   (Mac OS 7.5.2 – 9.2.2, G3/G4)" \
            "  3) Atari ST/STE/TT/Falcon  (68k)" \
            "  4) Amiga       (68k, AROS or FS-UAE)" \
            "  5) HaikuOS     (i386 / x86_64)" \
            "  ─── Tools ───────────────────────────────────" \
            "  6) Custom / Generic QEMU launch" \
            "  7) Disk image management" \
            "  q) Quit"
        printf '\n'

        local choice
        choice=$(ask "Select" "q")
        case "${choice}" in
            1) launch_macos_68k ;;
            2) launch_macos_ppc ;;
            3) launch_atari ;;
            4) launch_amiga ;;
            5) launch_haiku ;;
            6) launch_custom ;;
            7) manage_images ;;
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
  macos-ppc    Launch MacOS PPC VM
  atari        Launch Atari ST/STE/TT/Falcon VM
  amiga        Launch Amiga / AROS VM
  haiku        Launch HaikuOS VM
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
        atari)      launch_atari ;;
        amiga)      launch_amiga ;;
        haiku)      launch_haiku ;;
        custom)     launch_custom ;;
        images)     manage_images ;;
        menu)       main_menu ;;
        help|--help|-h) show_help ;;
        *) die "Unknown platform '${1}'. Run '$(basename "$0") help' for usage." ;;
    esac
}

main "$@"
