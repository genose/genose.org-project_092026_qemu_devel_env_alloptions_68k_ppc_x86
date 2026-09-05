#!/bin/bash
# VM Management - Create VM with XDialog GUI
# Group: vm, Action: create_xdialog
# This script provides a comprehensive XDialog-based GUI for creating VMs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/../vm-manager.sh"

# Check for XDialog and DISPLAY
if ! command -v xdialog &>/dev/null || [[ -z "${DISPLAY:-}" ]]; then
    echo "XDialog not available or DISPLAY not set, falling back to CLI"
    exec "${SCRIPT_DIR}/vm_create.sh" "$@"
fi

# XDialog-based VM creation form
create_vm_with_xdialog() {
    local vm_name=""
    local platform=""
    local ram=""
    local disk_size=""
    local cpu=""
    local display=""
    local network=""
    local iso_path=""
    
    # Step 1: VM Name
    vm_name=$(xdialog \
        --backtitle "Create New VM" \
        --title "VM Name" \
        --inputbox "Enter VM name:" \
        8 50 \
        "my-vm" \
        3>&1 1>&2 2>&3)
    
    if [[ -z "$vm_name" ]]; then
        echo "VM creation cancelled"
        return 1
    fi
    
    # Step 2: Platform Selection
    platform=$(xdialog \
        --backtitle "Create New VM" \
        --title "Platform Selection" \
        --menu "Select platform:" \
        15 50 8 \
        1 "68k (Motorola 68000)" \
        2 "PPC (PowerPC)" \
        3 "PPC64 (PowerPC 64-bit)" \
        4 "x86_64 (Intel/AMD 64-bit)" \
        5 "i386 (Intel 32-bit)" \
        6 "ARM" \
        7 "ARM64" \
        8 "SPARC" \
        3>&1 1>&2 2>&3)
    
    if [[ -z "$platform" ]]; then
        echo "VM creation cancelled"
        return 1
    fi
    
    # Map platform choice to actual platform
    case "$platform" in
        1) platform="m68k" ;;
        2) platform="ppc" ;;
        3) platform="ppc64" ;;
        4) platform="x86_64" ;;
        5) platform="i386" ;;
        6) platform="arm" ;;
        7) platform="arm64" ;;
        8) platform="sparc" ;;
        *) platform="x86_64" ;;
    esac
    
    # Step 3: RAM Size
    ram=$(xdialog \
        --backtitle "Create New VM" \
        --title "RAM Size" \
        --inputbox "Enter RAM size in MB:" \
        8 50 \
        "2048" \
        3>&1 1>&2 2>&3)
    
    if [[ -z "$ram" ]]; then
        echo "VM creation cancelled"
        return 1
    fi
    
    # Step 4: Disk Size
    disk_size=$(xdialog \
        --backtitle "Create New VM" \
        --title "Disk Size" \
        --inputbox "Enter disk size in GB:" \
        8 50 \
        "10" \
        3>&1 1>&2 2>&3)
    
    if [[ -z "$disk_size" ]]; then
        echo "VM creation cancelled"
        return 1
    fi
    
    # Step 5: Display Backend
    display=$(xdialog \
        --backtitle "Create New VM" \
        --title "Display Backend" \
        --menu "Select display backend:" \
        15 50 8 \
        1 "Cocoa (macOS native)" \
        2 "GTK" \
        3 "SDL" \
        4 "VNC" \
        5 "SPICE" \
        6 "None (headless)" \
        3>&1 1>&2 2>&3)
    
    if [[ -z "$display" ]]; then
        echo "VM creation cancelled"
        return 1
    fi
    
    # Map display choice
    case "$display" in
        1) display="cocoa" ;;
        2) display="gtk" ;;
        3) display="sdl" ;;
        4) display="vnc" ;;
        5) display="spice" ;;
        6) display="none" ;;
        *) display="cocoa" ;;
    esac
    
    # Step 6: Network
    network=$(xdialog \
        --backtitle "Create New VM" \
        --title "Network" \
        --menu "Select network type:" \
        12 50 4 \
        1 "User mode (NAT)" \
        2 "TAP (bridged)" \
        3 "None" \
        3>&1 1>&2 2>&3)
    
    if [[ -z "$network" ]]; then
        echo "VM creation cancelled"
        return 1
    fi
    
    # Map network choice
    case "$network" in
        1) network="user" ;;
        2) network="tap" ;;
        3) network="none" ;;
        *) network="user" ;;
    esac
    
    # Step 7: ISO Path (optional)
    iso_path=$(xdialog \
        --backtitle "Create New VM" \
        --title "Installation Media" \
        --inputbox "Enter path to ISO image (optional):" \
        8 50 \
        "" \
        3>&1 1>&2 2>&3)
    
    # Show configuration summary
    config_summary=$(cat << EOF
VM Configuration Summary:

Name: $vm_name
Platform: $platform
RAM: ${ram}MB
Disk Size: ${disk_size}GB
Display: $display
Network: $network
EOF
    )
    
    if [[ -n "$iso_path" ]]; then
        config_summary+="\nInstallation ISO: $iso_path"
    fi
    
    # Confirm creation
    xdialog \
        --backtitle "Create New VM" \
        --title "Confirm Configuration" \
        --yesno "$config_summary\n\nCreate this VM?" \
        15 60
    
    local response=$?
    if [[ $response -eq 0 ]]; then
        # Execute the create command with all parameters
        local cmd=(create "$vm_name" "$platform" "$ram" "$disk_size" "$display" "$network")
        if [[ -n "$iso_path" ]]; then
            cmd+=("$iso_path")
        fi
        
        echo "Creating VM with configuration: ${cmd[*]}"
        exec "${MAIN_SCRIPT}" "${cmd[@]}"
    else
        echo "VM creation cancelled"
        return 0
    fi
}

# Main execution
create_vm_with_xdialog "$@"