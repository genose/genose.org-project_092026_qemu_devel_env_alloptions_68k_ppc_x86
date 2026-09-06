#!/bin/bash
# Setup - MacOS 10.6 Snow Leopard PPC VM
# Group: setup, Action: macos106_ppc
# Comprehensive setup script for MacOS 10.6 Snow Leopard PPC VM
# Fetches ISO (with user approval), creates VM, and configures for dual display + debugging

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/vm-manager.sh"

# Configuration
VM_NAME="macos-106-ppc"
PLATFORM="ppc64"
ISO_FILENAME="Mac_OS_X_10.6_Snow_Leopard_Retail.iso"
VM_DIR="${HOME}/vm_assistant/vms/${VM_NAME}_${PLATFORM}"
ISO_DIR="${HOME}/vm_assistant/images"
CONFIG_FILE="${VM_DIR}/${VM_NAME}.conf"
DISK_FILE="${VM_DIR}/${VM_NAME}-hdd.qcow2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

header() {
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}MacOS 10.6 Snow Leopard PPC VM Setup${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo ""
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Function to check and create directories
setup_directories() {
    info "Setting up directory structure..."
    
    mkdir -p "${ISO_DIR}" && pass "Created ISO directory: ${ISO_DIR}"
    mkdir -p "${VM_DIR}" && pass "Created VM directory: ${VM_DIR}"
    echo ""
}

# Function to check if ISO already exists
check_iso_exists() {
    if [[ -f "${ISO_DIR}/${ISO_FILENAME}" ]]; then
        pass "ISO already exists at: ${ISO_DIR}/${ISO_FILENAME}"
        return 0
    fi
    return 1
}

# Function to find ISO in common locations
find_existing_iso() {
    info "Searching for existing MacOS 10.6 ISO..."
    
    local search_paths=(
        "${HOME}/vm_assistant/isos/${ISO_FILENAME}"
        "${HOME}/vm_assistant/images/${ISO_FILENAME}"
        "${HOME}/Downloads/${ISO_FILENAME}"
        "${HOME}/Downloads/MacOSX/${ISO_FILENAME}"
        "/Volumes/${ISO_FILENAME}"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -f "$path" ]]; then
            info "Found ISO at: $path"
            local answer
            read -rp "Copy to ${ISO_DIR}/? (y/n) [y]: " answer
            answer="${answer:-y}"
            if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
                cp "$path" "${ISO_DIR}/${ISO_FILENAME}"
                pass "ISO copied to: ${ISO_DIR}/${ISO_FILENAME}"
                return 0
            else
                ISO_DIR=$(dirname "$path")
                ISO_FILENAME=$(basename "$path")
                pass "Using existing ISO at: ${ISO_DIR}/${ISO_FILENAME}"
                return 0
            fi
        fi
    done
    
    return 1
}

# Function to prompt user for ISO location
prompt_for_iso() {
    echo ""
    info "MacOS 10.6 Snow Leopard ISO required"
    info "Filename: ${ISO_FILENAME}"
    info "Expected location: ${ISO_DIR}/${ISO_FILENAME}"
    echo ""
    info "Options:"
    info "  1. I have the ISO file (provide path)"
    info "  2. Download from internet (may violate license)"
    info "  3. Use existing VM (skip ISO setup)"
    info "  4. Exit"
    echo ""
    
    local choice
    read -rp "Select option (1-4) [1]: " choice
    choice="${choice:-1}"
    
    case "$choice" in
        1)
            local iso_path
            read -rp "Enter full path to ISO file: " iso_path
            if [[ -f "$iso_path" ]]; then
                cp "$iso_path" "${ISO_DIR}/${ISO_FILENAME}"
                pass "ISO copied to: ${ISO_DIR}/${ISO_FILENAME}"
            else
                fail "ISO file not found at: $iso_path"
                return 1
            fi
            ;;
        2)
            warn "Downloading MacOS ISO may violate Apple's license agreement"
            warn "You must legally own MacOS 10.6 to download and use it"
            local confirm
            read -rp "Do you have legal rights to MacOS 10.6? (y/n) [n]: " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                warn "ISO download cancelled. Please provide your own ISO file."
                return 1
            fi
            
            info "Please manually download MacOS 10.6 Snow Leopard from your legal source"
            info "and place it at: ${ISO_DIR}/${ISO_FILENAME}"
            info "Then run this script again."
            return 1
            ;;
        3)
            info "Skipping ISO setup, using existing VM configuration"
            return 0
            ;;
        4)
            info "Setup cancelled by user"
            exit 0
            ;;
        *)
            warn "Invalid option, using default (1)"
            prompt_for_iso
            ;;
    esac
}

# Function to verify QEMU PPC support
verify_qemu() {
    info "Verifying QEMU PPC support..."
    
    if ! command -v qemu-system-ppc &>/dev/null && ! command -v qemu-system-ppc64 &>/dev/null; then
        fail "QEMU PPC not found!"
        info "Install QEMU with PPC support:"
        info "  Homebrew: brew install qemu"
        info "  MacPorts: sudo port install qemu"
        info "  Ensure PPC architecture is included"
        return 1
    fi
    
    pass "QEMU PPC support detected"
    return 0
}

# Function to create the VM
create_vm() {
    info "Creating MacOS 10.6 PPC VM..."
    
    if ! verify_qemu; then
        return 1
    fi
    
    # Check if VM already exists
    if [[ -f "$CONFIG_FILE" ]]; then
        local overwrite
        read -rp "VM already exists. Overwrite? (y/n) [n]: " overwrite
        overwrite="${overwrite:-n}"
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            info "Using existing VM configuration"
            return 0
        fi
    fi
    
    info "Creating new VM configuration..."
    exec "${MAIN_SCRIPT}" create-macos-106 "$@"
}

# Function to launch the VM
launch_vm() {
    info "Launching MacOS 10.6 PPC VM..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warn "VM configuration not found. Run create first."
        local answer
        read -rp "Create VM now? (y/n) [y]: " answer
        answer="${answer:-y}"
        if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
            create_vm
        fi
        return 0
    fi
    
    exec "${MAIN_SCRIPT}" macos-106
}

# Main setup flow
main() {
    header
    
    # Step 1: Setup directories
    setup_directories
    
    # Step 2: Check QEMU
    if ! verify_qemu; then
        exit 1
    fi
    echo ""
    
    # Step 3: Handle ISO
    if ! check_iso_exists; then
        if ! find_existing_iso; then
            if ! prompt_for_iso; then
                exit 1
            fi
        fi
    fi
    echo ""
    
    # Step 4: Create and launch VM
    if [[ "${1:-}" == "launch" ]]; then
        launch_vm
    elif [[ "${1:-}" == "create" ]]; then
        create_vm "$@"
    else
        create_vm "$@"
        # Don't auto-launch, let user decide
        info "VM created. To launch: ./scripts/setup_macos106_ppc.sh launch"
    fi
}

main "$@"
