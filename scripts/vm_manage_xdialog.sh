#!/bin/bash
# VM Management - XDialog GUI for VM operations
# Group: vm, Action: manage_xdialog
# XDialog-based GUI for comprehensive VM management including list, create, launch, stop, edit, delete

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/../vm-manager.sh"

# Check for XDialog and DISPLAY
if ! command -v xdialog &>/dev/null || [[ -z "${DISPLAY:-}" ]]; then
    echo "XDialog not available or DISPLAY not set, falling back to CLI"
    exec "${SCRIPT_DIR}/vm_create.sh" "$@"
fi

# Function to show main VM management menu
vm_management_menu() {
    local choice
    
    choice=$(xdialog \
        --backtitle "VM Manager - VM Management" \
        --title "VM Management Menu" \
        --menu "Select VM operation:" \
        20 70 15 \
        1 "List all VMs" \
        2 "Create new VM" \
        3 "Launch VM" \
        4 "Stop running VM" \
        5 "Edit VM configuration" \
        6 "Delete VM" \
        7 "Clone existing VM" \
        8 "Export VM to QCOW2" \
        9 "Import VM from QCOW2" \
        0 "Back to Main Menu" \
        Q "Quit" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1) list_vms_with_xdialog ;;
        2) xdialog --msgbox "Use VM Create GUI for creating new VMs" 10 50 ;;
        3) launch_vm_with_xdialog ;;
        4) stop_vm_with_xdialog ;;
        5) edit_vm_with_xdialog ;;
        6) delete_vm_with_xdialog ;;
        7) clone_vm_with_xdialog ;;
        8) export_vm_with_xdialog ;;
        9) import_vm_with_xdialog ;;
        0|Q) return 0 ;;
        *) xdialog --msgbox "Invalid selection" 5 30 ;;
    esac
}

# List VMs with XDialog
list_vms_with_xdialog() {
    local vm_list
    vm_list=$(${SCRIPT_DIR}/vm_list.sh 2>/dev/null || echo "No VMs found")
    
    xdialog \
        --backtitle "VM Manager - VM List" \
        --title "Available VMs" \
        --textbox "$vm_list" \
        20 80
}

# Launch VM with XDialog selection
launch_vm_with_xdialog() {
    local vm_name
    
    vm_name=$(xdialog \
        --backtitle "VM Manager - Launch VM" \
        --title "Select VM to Launch" \
        --fselect "${HOME}/vm_assistant/vms/" \
        20 70 \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$vm_name" ]]; then
        local vm_dir=$(dirname "$vm_name")
        local vm_config="${vm_dir}/$(basename "$vm_name").conf"
        
        if [[ -f "$vm_config" ]]; then
            xdialog --msgbox "Launching VM from config: ${vm_config}" 5 40
            exec "${MAIN_SCRIPT}" launch "$vm_config"
        else
            xdialog --msgbox "No valid VM configuration found at: ${vm_config}" 5 40
        fi
    fi
}

# Stop VM with XDialog selection
stop_vm_with_xdialog() {
    local vm_name
    
    vm_name=$(xdialog \
        --backtitle "VM Manager - Stop VM" \
        --title "Select VM to Stop" \
        --inputbox "Enter VM name:" \
        10 40 \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$vm_name" ]]; then
        exec "${MAIN_SCRIPT}" stop "$vm_name"
    fi
}

# Edit VM configuration with XDialog
edit_vm_with_xdialog() {
    local vm_name
    
    vm_name=$(xdialog \
        --backtitle "VM Manager - Edit VM" \
        --title "Select VM to Edit" \
        --fselect "${HOME}/vm_assistant/vms/" \
        20 70 \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$vm_name" ]]; then
        local vm_dir=$(dirname "$vm_name")
        local vm_config="${vm_dir}/$(basename "$vm_name").conf"
        
        if [[ -f "$vm_config" ]]; then
            xdialog --msgbox "Opening VM configuration for editing: ${vm_config}" 5 40
            exec "${MAIN_SCRIPT}" config-edit "$vm_config"
        else
            xdialog --msgbox "No valid VM configuration found at: ${vm_config}" 5 40
        fi
    fi
}

# Delete VM with XDialog confirmation
delete_vm_with_xdialog() {
    local vm_name
    
    vm_name=$(xdialog \
        --backtitle "VM Manager - Delete VM" \
        --title "Select VM to Delete" \
        --fselect "${HOME}/vm_assistant/vms/" \
        20 70 \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$vm_name" ]]; then
        local vm_dir=$(dirname "$vm_name")
        local vm_config="${vm_dir}/$(basename "$vm_name").conf"
        
        if [[ -f "$vm_config" ]]; then
            # Confirm deletion
            xdialog \
                --yesno "Are you sure you want to delete VM: ${vm_config}? This cannot be undone." \
                10 60
            
            if [[ $? -eq 0 ]]; then
                exec "${MAIN_SCRIPT}" delete "$vm_config"
            fi
        else
            xdialog --msgbox "No valid VM configuration found at: ${vm_config}" 5 40
        fi
    fi
}

# Clone VM with XDialog
clone_vm_with_xdialog() {
    local source_vm target_vm
    
    source_vm=$(xdialog \
        --backtitle "VM Manager - Clone VM" \
        --title "Select Source VM" \
        --fselect "${HOME}/vm_assistant/vms/" \
        20 70 \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$source_vm" ]]; then
        target_vm=$(xdialog \
            --backtitle "VM Manager - Clone VM" \
            --title "Enter Target VM Name" \
            --inputbox "Enter name for cloned VM:" \
            10 40 \
            3>&1 1>&2 2>&3)
        
        if [[ -n "$target_vm" ]]; then
            exec "${MAIN_SCRIPT}" clone "$source_vm" "$target_vm"
        fi
    fi
}

# Export VM with XDialog
export_vm_with_xdialog() {
    local vm_name export_file
    
    vm_name=$(xdialog \
        --backtitle "VM Manager - Export VM" \
        --title "Select VM to Export" \
        --fselect "${HOME}/vm_assistant/vms/" \
        20 70 \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$vm_name" ]]; then
        export_file=$(xdialog \
            --backtitle "VM Manager - Export VM" \
            --title "Save as QCOW2 file" \
            --fselect "${HOME}/vm_assistant/images/" \
            20 70 \
            3>&1 1>&2 2>&3)
        
        if [[ -n "$export_file" ]]; then
            exec "${MAIN_SCRIPT}" export "$vm_name" "$export_file"
        fi
    fi
}

# Import VM with XDialog
import_vm_with_xdialog() {
    local import_file vm_name
    
    import_file=$(xdialog \
        --backtitle "VM Manager - Import VM" \
        --title "Select QCOW2 file to Import" \
        --fselect "${HOME}/vm_assistant/images/" \
        20 70 \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$import_file" ]]; then
        vm_name=$(xdialog \
            --backtitle "VM Manager - Import VM" \
            --title "Enter VM Name" \
            --inputbox "Enter name for imported VM:" \
            10 40 \
            3>&1 1>&2 2>&3)
        
        if [[ -n "$vm_name" ]]; then
            exec "${MAIN_SCRIPT}" import "$import_file" "$vm_name"
        fi
    fi
}

# Main entry point
main() {
    vm_management_menu
}

main "$@"