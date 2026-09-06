#!/bin/bash
# Test - Create and test MacOS 10.6 PPC VM
# Group: test, Action: macos106_ppc
# Dedicated test script for MacOS 10.6 Snow Leopard PPC VM creation and testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/vm-manager.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print header
header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}MacOS 10.6 PPC VM Test Suite${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# Function to print test result
pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to check if QEMU PPC is available
check_qemu_ppc() {
    info "Checking for QEMU PPC binaries..."
    
    local has_ppc=false
    local has_ppc64=false
    
    if command -v qemu-system-ppc &>/dev/null; then
        pass "qemu-system-ppc found"
        has_ppc=true
    else
        warn "qemu-system-ppc not found"
    fi
    
    if command -v qemu-system-ppc64 &>/dev/null; then
        pass "qemu-system-ppc64 found"
        has_ppc64=true
    else
        warn "qemu-system-ppc64 not found"
    fi
    
    if [[ $has_ppc == false && $has_ppc64 == false ]]; then
        fail "No QEMU PPC binaries found. Install QEMU with PPC support."
        return 1
    fi
    
    return 0
}

# Function to check for MacOS 10.6 ISO
check_macos_iso() {
    info "Checking for MacOS 10.6 Snow Leopard ISO..."
    
    local default_iso="${HOME}/vm_assistant/images/Mac_OS_X_10.6_Snow_Leopard_Retail.iso"
    local iso_paths=(
        "${HOME}/vm_assistant/isos/Mac_OS_X_10.6_Snow_Leopard_Retail.iso"
        "${HOME}/vm_assistant/images/Mac_OS_X_10.6_Snow_Leopard_Retail.iso"
        "${HOME}/Downloads/Mac_OS_X_10.6_Snow_Leopard_Retail.iso"
    )
    
    local found=false
    for iso in "${iso_paths[@]}"; do
        if [[ -f "$iso" ]]; then
            pass "MacOS 10.6 ISO found at: $iso"
            found=true
            break
        fi
    done
    
    if [[ $found == false ]]; then
        warn "MacOS 10.6 ISO not found in standard locations"
        warn "Expected paths:"
        for iso in "${iso_paths[@]}"; do
            warn "  - $iso"
        done
        info "You can place your ISO at: ${default_iso}"
        return 1
    fi
    
    return 0
}

# Function to check VM configuration
check_vm_config() {
    local vm_name="${1:-macos-106-ppc}"
    info "Checking for existing VM configuration: ${vm_name}..."
    
    local vm_dir="${HOME}/vm_assistant/vms/${vm_name}_ppc64"
    local config_file="${vm_dir}/${vm_name}.conf"
    local disk_file="${vm_dir}/${vm_name}-hdd.qcow2"
    
    if [[ -f "$config_file" ]]; then
        pass "VM configuration found: $config_file"
        if [[ -f "$disk_file" ]]; then
            pass "VM disk found: $disk_file"
        else
            warn "VM disk not found: $disk_file"
        fi
        return 0
    else
        warn "No existing VM configuration found"
        return 1
    fi
}

# Function to show QEMU command that would be used
show_qemu_command() {
    info "Sample QEMU command for MacOS 10.6 PPC:"
    echo ""
    echo "qemu-system-ppc64 \\"
    echo "  -machine mac99,via=pmu \\"
    echo "  -cpu 970 \\"
    echo "  -smp 2,sockets=2,cores=1 \\"
    echo "  -m 2048 \\"
    echo "  -display cocoa \\"
    echo "  -audiodev coreaudio,id=snd0 \\"
    echo "  -device VGA,vgamem_mb=64 \\"
    echo "  -device usb-kbd \\"
    echo "  -device usb-mouse \\"
    echo "  -nic user,model=sungem \\"
    echo "  -rtc base=localtime \\"
    echo "  -hda ~/vm_assistant/vms/macos-106-ppc/macos-106-ppc-hdd.qcow2 \\"
    echo "  -cdrom ~/vm_assistant/images/Mac_OS_X_10.6_Snow_Leopard_Retail.iso \\"
    echo "  -boot d"
    echo ""
}

# Function to test VM creation (dry run)
test_vm_creation() {
    info "Testing MacOS 10.6 PPC VM creation..."
    
    # Test with dry run - just show what would happen
    exec "${MAIN_SCRIPT}" create-macos-106 --dry-run
}

# Function to run full test suite
run_all_tests() {
    header
    
    local passed=0
    local failed=0
    
    # Test 1: QEMU PPC availability
    if check_qemu_ppc; then
        ((passed++))
    else
        ((failed++))
    fi
    echo ""
    
    # Test 2: MacOS ISO availability
    if check_macos_iso; then
        ((passed++))
    else
        ((failed++))
    fi
    echo ""
    
    # Test 3: Existing VM configuration
    if check_vm_config; then
        ((passed++))
    else
        ((failed++))
    fi
    echo ""
    
    # Test 4: Show sample command
    show_qemu_command
    echo ""
    
    # Summary
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Results${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Passed: ${GREEN}${passed}${NC}"
    echo -e "Failed: ${RED}${failed}${NC}"
    echo -e "Total:  ${passed}"
    echo ""
    
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}All checks passed! Ready to create MacOS 10.6 PPC VM.${NC}"
        echo ""
        echo "To create and launch the VM:"
        echo "  ./vm-manager.sh create-macos-106"
        echo ""
        echo "To just launch an existing VM:"
        echo "  ./vm-manager.sh macos-106"
        echo ""
        echo "To debug the VM:"
        echo "  ./vm-manager.sh debug-macos-106"
        return 0
    else
        echo -e "${YELLOW}Some checks failed. Please fix the issues above.${NC}"
        return 1
    fi
}

# Function to show command only (for debugging)
show_command() {
    header
    info "Showing QEMU command without executing..."
    show_qemu_command
}

# Main function
main() {
    local action="${1:-test}"
    
    case "$action" in
        test|check) run_all_tests ;;
        create) test_vm_creation ;;
        launch) 
            exec "${MAIN_SCRIPT}" macos-106
            ;;
        debug) 
            exec "${MAIN_SCRIPT}" debug-macos-106
            ;;
        create-full) 
            exec "${MAIN_SCRIPT}" create-macos-106
            ;;
        show_cmd|show-command) 
            show_command
            ;;
        help|--help|-h) 
            header
            echo "Usage: $0 [ACTION]"
            echo ""
            echo "Actions:"
            echo "  test       Run full test suite (default)"
            echo "  check      Same as test"
            echo "  create     Test VM creation (dry run)"
            echo "  create-full Create and launch MacOS 10.6 PPC VM"
            echo "  launch     Launch existing MacOS 10.6 PPC VM"
            echo "  debug      Debug MacOS 10.6 PPC VM"
            echo "  show_cmd   Show QEMU command without executing"
            echo "  help       Show this help"
            ;;
        *) 
            run_all_tests
            ;;
    esac
}

main "$@"
