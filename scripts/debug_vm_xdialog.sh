#!/bin/bash
# Debug - Debug VM with XDialog GUI
# Group: debug, Action: vm_xdialog
# This script provides an XDialog-based GUI for debugging VMs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/../vm-manager.sh"

# Check for XDialog and DISPLAY
if ! command -v xdialog &>/dev/null || [[ -z "${DISPLAY:-}" ]]; then
    echo "XDialog not available or DISPLAY not set, falling back to CLI"
    exec "${SCRIPT_DIR}/debug_start.sh" "$@"
fi

# XDialog-based debug session setup
debug_vm_with_xdialog() {
    local vm_name=""
    local gdb_port=""
    local binary_path=""
    local debug_type=""
    
    # Step 1: Select VM
    vm_name=$(xdialog \
        --backtitle "Debug VM" \
        --title "Select VM" \
        --inputbox "Enter VM name to debug:" \
        8 50 \
        "" \
        3>&1 1>&2 2>&3)
    
    if [[ -z "$vm_name" ]]; then
        echo "Debug session cancelled"
        return 1
    fi
    
    # Step 2: GDB Port
    gdb_port=$(xdialog \
        --backtitle "Debug VM" \
        --title "GDB Port" \
        --inputbox "Enter GDB port:" \
        8 50 \
        "1234" \
        3>&1 1>&2 2>&3)
    
    if [[ -z "$gdb_port" ]]; then
        echo "Debug session cancelled"
        return 1
    fi
    
    # Step 3: Binary Path (optional)
    binary_path=$(xdialog \
        --backtitle "Debug VM" \
        --title "Binary Path" \
        --inputbox "Enter path to binary (optional):" \
        8 50 \
        "" \
        3>&1 1>&2 2>&3)
    
    # Step 4: Debug Type
    debug_type=$(xdialog \
        --backtitle "Debug VM" \
        --title "Debug Type" \
        --menu "Select debug operation:" \
        12 50 5 \
        1 "Start debug session" \
        2 "Connect GDB to running VM" \
        3 "Attach to existing session" \
        3>&1 1>&2 2>&3)
    
    if [[ -z "$debug_type" ]]; then
        echo "Debug session cancelled"
        return 1
    fi
    
    # Show configuration summary
    config_summary="Debug Configuration:\n\n"
    config_summary+="VM Name: $vm_name\n"
    config_summary+="GDB Port: $gdb_port\n"
    if [[ -n "$binary_path" ]]; then
        config_summary+="Binary: $binary_path\n"
    fi
    
    case "$debug_type" in
        1) config_summary+="Operation: Start debug session\n" ;;
        2) config_summary+="Operation: Connect GDB to running VM\n" ;;
        3) config_summary+="Operation: Attach to existing session\n" ;;
    esac
    
    # Confirm debug session
    xdialog \
        --backtitle "Debug VM" \
        --title "Confirm Debug Configuration" \
        --yesno "$config_summary\n\nStart debug operation?" \
        15 60
    
    local response=$?
    if [[ $response -eq 0 ]]; then
        case "$debug_type" in
            1) # Start debug session
                if [[ -n "$binary_path" ]]; then
                    exec "${MAIN_SCRIPT}" debug "$vm_name" "$binary_path" "$gdb_port"
                else
                    exec "${MAIN_SCRIPT}" debug "$vm_name" "$gdb_port"
                fi
                ;;
            2) # Connect GDB
                if [[ -n "$binary_path" ]]; then
                    exec "${MAIN_SCRIPT}" debug-connect "$vm_name" "$gdb_port" "$binary_path"
                else
                    exec "${MAIN_SCRIPT}" debug-connect "$vm_name" "$gdb_port"
                fi
                ;;
            3) # Attach
                exec "${MAIN_SCRIPT}" debug-attach "$vm_name" "$gdb_port"
                ;;
        esac
    else
        echo "Debug session cancelled"
        return 0
    fi
}

# Main execution
debug_vm_with_xdialog "$@"