#!/bin/bash
# Platform - Select and Launch Platform with XDialog GUI
# Group: platform, Action: select_xdialog
# This script provides an XDialog-based GUI for selecting and launching platform presets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/../vm-manager.sh"

# Check for XDialog and DISPLAY
if ! command -v xdialog &>/dev/null || [[ -z "${DISPLAY:-}" ]]; then
    echo "XDialog not available or DISPLAY not set, falling back to CLI"
    exec "${MAIN_SCRIPT}" help
fi

# XDialog-based platform selection
select_platform_with_xdialog() {
    local platform_choice=""
    local platforms=(
        "macos-68k:Launch MacOS 68k VM"
        "macos-ppc:Launch MacOS PPC VM (G3/G4)"
        "macos-ppc64:Launch MacOS PPC VM (G5)"
        "macos-106:Launch MacOS 10.6 PPC VM with dual display and debugging"
        "haiku:Launch HaikuOS VM"
        "linux:Launch Linux VM"
        "atari:Launch Atari ST/TT/Falcon VM"
        "amiga:Launch Commodore Amiga/AROS VM"
        "solaris-x86:Launch Solaris x86 VM"
        "solaris-sparc:Launch Solaris SPARC VM"
        "windows-xp:Launch Windows XP VM"
        "openstep:Launch OpenStep x86 VM"
        "custom:Launch custom QEMU with any architecture"
    )
    
    local menu_items=()
    local platform_commands=()
    local i=1
    
    for platform in "${platforms[@]}"; do
        local IFS=':'
        read -r cmd desc <<< "$platform"
        menu_items+=("$i" "$desc")
        platform_commands+=("$cmd")
        ((i++)) || true
    done
    
    # Add back/quit options
    menu_items+=("0" "Back to Main Menu")
    menu_items+=("Q" "Quit")
    
    # Show platform selection menu
    platform_choice=$(xdialog \
        --backtitle "Launch Platform VM" \
        --title "Platform Selection" \
        --menu "Select a platform to launch:" \
        20 70 15 \
        "${menu_items[@]}" \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$platform_choice" ]]; then
        case "$platform_choice" in
            "0"|"Back to Main Menu")
                if [[ -f "$MAIN_SCRIPT" ]]; then
                    exec "$MAIN_SCRIPT" menu
                else
                    exit 0
                fi
                ;;
            "Q"|"Quit") exit 0 ;;
            *)
                if [[ "$platform_choice" =~ ^[0-9]+$ ]]; then
                    local index=$((platform_choice - 1))
                    if [[ $index -ge 0 && $index -lt ${#platform_commands[@]} ]]; then
                        local selected_platform="${platform_commands[$index]}"
                        exec "$MAIN_SCRIPT" "$selected_platform"
                    fi
                fi
                ;;
        esac
    fi
    
    # If user cancelled, return to main menu
    if [[ -z "$platform_choice" ]]; then
        exec "$MAIN_SCRIPT" menu
    fi
}

# Main execution
select_platform_with_xdialog "$@"