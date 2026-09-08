#!/bin/bash
# =============================================================================
# VM Manager - XDialog GUI Interface
# 
# This script provides a graphical user interface for VM management using XDialog.
# It wraps the vm-manager.sh functionality with a user-friendly GUI.
# 
# Features:
# - VM creation, launch, stop, delete
# - Configuration management with GUI
# - VM selection via dialog boxes
# - Progress display
# - Error handling with GUI messages
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/../vm-manager.sh"

# Check for XDialog and DISPLAY
if ! command -v Xdialog &>/dev/null || [[ -z "${DISPLAY:-}" ]]; then
    echo "XDialog not available or DISPLAY not set, falling back to CLI"
    exec "${MAIN_SCRIPT}" "$@"
fi

# Colors for terminal output (XDialog uses its own styling)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Show main menu
main_menu() {
    while true; do
        choice=$(Xdialog \
            --backtitle "genose.org VM Manager" \
            --title "Main Menu" \
            --menu "Select an action:" \
            20 70 15 \
            1 "VM Lifecycle" \
            2 "Configuration Management" \
            3 "Debugging" \
            4 "Build & Patching" \
            5 "Network & Sharing" \
            6 "System Information" \
            7 "Settings" \
            0 "Exit" \
            Q "Quit" \
            3>&1 1>&2 2>&3)
        
        case "${choice}" in
            1) vm_lifecycle_menu ;;
            2) config_management_menu ;;
            3) debug_menu ;;
            4) build_menu ;;
            5) network_menu ;;
            6) info_menu ;;
            7) settings_menu ;;
            0|Q) exit 0 ;;
            *) Xdialog --msgbox "Invalid selection" 5 30 ;;
        esac
    done
}

# VM Lifecycle Menu
vm_lifecycle_menu() {
    while true; do
        choice=$(Xdialog \
            --backtitle "genose.org VM Manager - VM Lifecycle" \
            --title "VM Lifecycle" \
            --menu "Select VM action:" \
            20 70 15 \
            1 "Create New VM" \
            2 "Launch VM" \
            3 "Stop VM" \
            4 "Delete VM" \
            5 "List VMs" \
            6 "Clone VM" \
            7 "Edit VM Configuration" \
            8 "Export VM" \
            9 "Import VM" \
            0 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "${choice}" in
            1) create_vm_gui ;;
            2) launch_vm_gui ;;
            3) stop_vm_gui ;;
            4) delete_vm_gui ;;
            5) list_vms_gui ;;
            6) clone_vm_gui ;;
            7) edit_vm_config_gui ;;
            8) export_vm_gui ;;
            9) import_vm_gui ;;
            0) return 0 ;;
            *) Xdialog --msgbox "Invalid selection" 5 30 ;;
        esac
    done
}

# Configuration Management Menu
config_management_menu() {
    while true; do
        choice=$(Xdialog \
            --backtitle "genose.org VM Manager - Configuration" \
            --title "Configuration Management" \
            --menu "Select configuration action:" \
            20 70 15 \
            1 "Create Configuration Backup" \
            2 "Restore from Backup" \
            3 "List All Backups" \
            4 "Show Configuration History" \
            5 "Compare Configuration Versions" \
            6 "Commit Configuration Changes" \
            7 "View Current Configuration" \
            0 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "${choice}" in
            1) create_backup_gui ;;
            2) restore_backup_gui ;;
            3) list_backups_gui ;;
            4) show_history_gui ;;
            5) diff_config_gui ;;
            6) commit_config_gui ;;
            7) view_config_gui ;;
            0) return 0 ;;
            *) Xdialog --msgbox "Invalid selection" 5 30 ;;
        esac
    done
}

# Debug Menu
debug_menu() {
    while true; do
        choice=$(Xdialog \
            --backtitle "genose.org VM Manager - Debugging" \
            --title "Debugging" \
            --menu "Select debug action:" \
            20 70 15 \
            1 "Start Debug Session" \
            2 "Connect GDB to Running VM" \
            3 "List Debuggable VMs" \
            4 "Deploy Binary to VM" \
            5 "Test GDB Connection" \
            0 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "${choice}" in
            1) debug_start_gui ;;
            2) debug_connect_gui ;;
            3) debug_list_gui ;;
            4) deploy_binary_gui ;;
            5) debug_test_gui ;;
            0) return 0 ;;
            *) Xdialog --msgbox "Invalid selection" 5 30 ;;
        esac
    done
}

# Build Menu
build_menu() {
    while true; do
        choice=$(Xdialog \
            --backtitle "genose.org VM Manager - Build & Patching" \
            --title "Build & Patching" \
            --menu "Select build action:" \
            20 70 15 \
            1 "Build QEMU" \
            2 "Build with All Patches" \
            3 "List Available Patches" \
            4 "Apply Specific Patch" \
            5 "Clean Build Directory" \
            0 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "${choice}" in
            1) build_qemu_gui ;;
            2) build_all_patches_gui ;;
            3) list_patches_gui ;;
            4) apply_patch_gui ;;
            5) clean_build_gui ;;
            0) return 0 ;;
            *) Xdialog --msgbox "Invalid selection" 5 30 ;;
        esac
    done
}

# Network Menu
network_menu() {
    while true; do
        choice=$(Xdialog \
            --backtitle "genose.org VM Manager - Network & Sharing" \
            --title "Network & Sharing" \
            --menu "Select network action:" \
            20 70 15 \
            1 "Start Netatalk (AppleShare)" \
            2 "Start Samba" \
            3 "Start 9P Filesystem" \
            4 "Setup Port Forwarding" \
            5 "Configure Network Bridge" \
            0 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "${choice}" in
            1) start_netatalk_gui ;;
            2) start_samba_gui ;;
            3) start_9p_gui ;;
            4) setup_port_forwarding_gui ;;
            5) configure_bridge_gui ;;
            0) return 0 ;;
            *) Xdialog --msgbox "Invalid selection" 5 30 ;;
        esac
    done
}

# Information Menu
info_menu() {
    while true; do
        choice=$(Xdialog \
            --backtitle "genose.org VM Manager - System Information" \
            --title "System Information" \
            --menu "Select information to display:" \
            20 70 15 \
            1 "QEMU Version" \
            2 "System Architecture" \
            3 "Available Architectures" \
            4 "List VMs" \
            5 "System Resources" \
            6 "Project Statistics" \
            0 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "${choice}" in
            1) show_qemu_version_gui ;;
            2) show_system_arch_gui ;;
            3) show_architectures_gui ;;
            4) list_vms_gui ;;
            5) show_system_resources_gui ;;
            6) show_project_stats_gui ;;
            0) return 0 ;;
            *) Xdialog --msgbox "Invalid selection" 5 30 ;;
        esac
    done
}

# Settings Menu
settings_menu() {
    while true; do
        choice=$(Xdialog \
            --backtitle "genose.org VM Manager - Settings" \
            --title "Settings" \
            --menu "Select settings action:" \
            20 70 15 \
            1 "Configure Defaults" \
            2 "Configure Paths" \
            3 "Configure Display" \
            4 "Configure Network" \
            5 "Edit Configuration File" \
            0 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "${choice}" in
            1) configure_defaults_gui ;;
            2) configure_paths_gui ;;
            3) configure_display_gui ;;
            4) configure_network_gui ;;
            5) edit_config_file_gui ;;
            0) return 0 ;;
            *) Xdialog --msgbox "Invalid selection" 5 30 ;;
        esac
    done
}

# VM Creation GUI
create_vm_gui() {
    # Get VM name
    vm_name=$(Xdialog \
        --backtitle "genose.org VM Manager - Create VM" \
        --title "VM Name" \
        --inputbox "Enter VM name:" \
        10 40 \
        "macos-106-ppc" \
        3>&1 1>&2 2>&3)
    
    if [[ -z "${vm_name}" ]]; then
        return
    fi
    
    # Get platform
    platform=$(Xdialog \
        --backtitle "genose.org VM Manager - Create VM" \
        --title "Platform" \
        --menu "Select platform:" \
        20 50 10 \
        1 "ppc64" \
        2 "ppc" \
        3 "m68k" \
        4 "x86_64" \
        5 "i386" \
        6 "arm" \
        7 "aarch64" \
        0 "Back" \
        3>&1 1>&2 2>&3)
    
    case "${platform}" in
        1) platform="ppc64" ;;
        2) platform="ppc" ;;
        3) platform="m68k" ;;
        4) platform="x86_64" ;;
        5) platform="i386" ;;
        6) platform="arm" ;;
        7) platform="aarch64" ;;
        *) return ;;
    esac
    
    # Get machine type
    machine=$(Xdialog \
        --backtitle "genose.org VM Manager - Create VM" \
        --title "Machine Type" \
        --menu "Select machine type:" \
        20 50 10 \
        1 "mac99" \
        2 "g3beige" \
        3 "mac99,via=pmu" \
        4 "q800" \
        5 "prep" \
        6 "pc" \
        0 "Back" \
        3>&1 1>&2 2>&3)
    
    case "${machine}" in
        1) machine="mac99" ;;
        2) machine="g3beige" ;;
        3) machine="mac99,via=pmu" ;;
        4) machine="q800" ;;
        5) machine="prep" ;;
        6) machine="pc" ;;
        *) return ;;
    esac
    
    # Get CPU
    cpu=$(Xdialog \
        --backtitle "genose.org VM Manager - Create VM" \
        --title "CPU Type" \
        --menu "Select CPU:" \
        20 50 10 \
        1 "970fx" \
        2 "970" \
        3 "7400" \
        4 "750" \
        5 "604e" \
        0 "Back" \
        3>&1 1>&2 2>&3)
    
    case "${cpu}" in
        1) cpu="970fx" ;;
        2) cpu="970" ;;
        3) cpu="7400" ;;
        4) cpu="750" ;;
        5) cpu="604e" ;;
        *) return ;;
    esac
    
    # Get RAM
    ram=$(Xdialog \
        --backtitle "genose.org VM Manager - Create VM" \
        --title "RAM Size" \
        --menu "Select RAM size (MB):" \
        20 50 10 \
        1 "1024" \
        2 "2048" \
        3 "4096" \
        4 "8192" \
        0 "Back" \
        3>&1 1>&2 2>&3)
    
    case "${ram}" in
        1) ram="1024" ;;
        2) ram="2048" ;;
        3) ram="4096" ;;
        4) ram="8192" ;;
        *) return ;;
    esac
    
    # Get number of CPUs
    smp=$(Xdialog \
        --backtitle "genose.org VM Manager - Create VM" \
        --title "Number of CPUs" \
        --menu "Select number of CPUs:" \
        20 50 10 \
        1 "1" \
        2 "2" \
        3 "4" \
        4 "8" \
        0 "Back" \
        3>&1 1>&2 2>&3)
    
    case "${smp}" in
        1) smp="1" ;;
        2) smp="2" ;;
        3) smp="4" ;;
        4) smp="8" ;;
        *) return ;;
    esac
    
    # Confirm
    Xdialog \
        --yesno "Create VM with the following configuration:\n\nName: ${vm_name}\nPlatform: ${platform}\nMachine: ${machine}\nCPU: ${cpu}\nRAM: ${ram} MB\nCPUs: ${smp}" \
        15 60
    
    if [[ $? -eq 0 ]]; then
        # Execute VM creation
        Xdialog --title "Creating VM" --infobox "Creating VM '${vm_name}'..." 5 40 &
        INFBOX_PID=$!
        
        # Build full VM name with platform
        full_name="${vm_name}_${platform}"
        
        # Call the create function from vm-manager.sh
        if source "${MAIN_SCRIPT}" 2>/dev/null; then
            # Try to use the create_macos_106 function or generic create
            if command -v create_and_launch_macos_10_6_ppc &>/dev/null; then
                create_and_launch_macos_10_6_ppc
            else
                "${MAIN_SCRIPT}" create "${full_name}" "${machine}" "${cpu}" "${ram}" "${smp}"
            fi
        else
            "${MAIN_SCRIPT}" create "${full_name}" "${machine}" "${cpu}" "${ram}" "${smp}"
        fi
        
        kill ${INFBOX_PID} 2>/dev/null || true
        
        Xdialog --msgbox "VM '${full_name}' created successfully!" 5 40
    fi
}

# Launch VM GUI
launch_vm_gui() {
    # List available VMs
    vm_list=$("${MAIN_SCRIPT}" list 2>/dev/null | grep -E "^\s*[0-9]+\." | sed 's/^[[:space:]]*//' || echo "No VMs found")
    
    if [[ "${vm_list}" == "No VMs found" ]]; then
        Xdialog --msgbox "No VMs found. Create a VM first." 5 40
        return
    fi
    
    # Format for XDialog menu
    menu_items=""
    IFS=$'\n' read -rd '' -a lines <<< "${vm_list}"
    for line in "${lines[@]}"; do
        if [[ -n "${line}" ]]; then
            # Extract VM number and name
            vm_num=$(echo "${line}" | awk '{print $1}' | tr -d '.')
            vm_info=$(echo "${line}" | sed 's/^[[:space:]]*[0-9]*[.]//')
            menu_items+="${vm_num} "\"${vm_info}\" "
        fi
    done
    
    vm_choice=$(Xdialog \
        --backtitle "genose.org VM Manager - Launch VM" \
        --title "Select VM to Launch" \
        --menu "Choose a VM:" \
        20 70 15 \
        ${menu_items} \
        0 "Back" \
        3>&1 1>&2 2>&3)
    
    if [[ "${vm_choice}" == "0" ]]; then
        return
    fi
    
    # Get the VM name from the list
    vm_name=$(echo "${vm_list}" | grep "^\s*${vm_choice}\." | sed 's/^[[:space:]]*[0-9]*[.]//' | xargs)
    
    # Launch options
    launch_option=$(Xdialog \
        --backtitle "genose.org VM Manager - Launch VM" \
        --title "Launch Options" \
        --menu "Select launch mode:" \
        20 50 10 \
        1 "Normal Launch" \
        2 "Launch with GUI" \
        3 "Launch with Debug" \
        4 "Launch with GDB" \
        0 "Back" \
        3>&1 1>&2 2>&3)
    
    case "${launch_option}" in
        1) "${MAIN_SCRIPT}" "${vm_name}" ;;
        2) "${MAIN_SCRIPT}" "${vm_name}" gui ;;
        3) "${MAIN_SCRIPT}" debug "${vm_name}" ;;
        4) "${MAIN_SCRIPT}" debug-connect "${vm_name}" ;;
        *) return ;;
    esac
}

# List VMs GUI
list_vms_gui() {
    vm_list=$("${MAIN_SCRIPT}" list 2>/dev/null || echo "No VMs found")
    
    if [[ "${vm_list}" == "No VMs found" ]]; then
        Xdialog --msgbox "No VMs found." 5 40
        return
    fi
    
    Xdialog \
        --backtitle "genose.org VM Manager - VM List" \
        --title "Available VMs" \
        --textbox "${vm_list}" \
        20 80
}

# Show QEMU Version GUI
show_qemu_version_gui() {
    version=$("${MAIN_SCRIPT}" qemu-version 2>/dev/null || ${HOME}/.local/qemu-genose/bin/qemu-system-ppc64 -version 2>&1)
    
    Xdialog \
        --backtitle "genose.org VM Manager - QEMU Version" \
        --title "QEMU Version" \
        --textbox "${version}" \
        10 60
}

# Show System Architecture GUI
show_system_arch_gui() {
    arch_info=$("${MAIN_SCRIPT}" info-architectures 2>/dev/null || uname -a)
    
    Xdialog \
        --backtitle "genose.org VM Manager - System Architecture" \
        --title "System Architecture" \
        --textbox "${arch_info}" \
        10 60
}

# Show Project Statistics GUI
show_project_stats_gui() {
    stats=$(cat "${SCRIPT_DIR}/../COMPLETION_SUMMARY.md" 2>/dev/null | head -50 || echo "Statistics not available")
    
    Xdialog \
        --backtitle "genose.org VM Manager - Project Statistics" \
        --title "Project Statistics" \
        --textbox "${stats}" \
        20 80
}

# Main entry point
main() {
    # Check if called as a module
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        # Sourced as a module, export functions
        export -f main_menu
        export -f vm_lifecycle_menu
        export -f config_management_menu
        export -f debug_menu
        export -f build_menu
        export -f network_menu
        export -f info_menu
        export -f settings_menu
        export -f create_vm_gui
        export -f launch_vm_gui
        export -f list_vms_gui
        export -f show_qemu_version_gui
        export -f show_system_arch_gui
        export -f show_project_stats_gui
        return 0
    fi
    
    # Run main menu
    main_menu
}

main "$@"
