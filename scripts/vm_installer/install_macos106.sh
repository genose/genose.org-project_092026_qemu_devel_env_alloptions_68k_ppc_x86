#!/bin/bash
# =============================================================================
# Install MacOS 10.6 PPC Automatically
# 
# This script uses QMP-based automation to install MacOS 10.6 in a VM
# with the genose.org custom QEMU that supports multi-CPU.
# =============================================================================

set -euo pipefail

# Configuration
QEMU_BIN="${HOME}/.local/qemu-genose/bin/qemu-system-ppc64"
VM_NAME="macos-106-ppc_ppc64"
VM_DIR="${HOME}/vm_assistant/vms/${VM_NAME}"
ISO_FILE="${HOME}/vm_assistant/images/Mac_OS_X_10.6_Snow_Leopard_Retail.iso"
DISK_FILE="${VM_DIR}/qcow2/${VM_NAME}.qcow2"
ROM_FILE="${VM_DIR}/rom/mac99.rom"
QMP_SOCKET="/tmp/qmp-${VM_NAME}.sock"
MONITOR_SOCKET="/tmp/monitor-${VM_NAME}.sock"
TIMEOUT=7200  # 2 hours

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    log_info "Cleaning up..."
    pkill -f "qemu-system-ppc64" 2>/dev/null || true
    sleep 1
    rm -f "${QMP_SOCKET}" "${MONITOR_SOCKET}" 2>/dev/null || true
    log_info "Cleanup complete"
}

trap cleanup EXIT

check_prerequisites() {
    echo -e "\n${PURPLE}=== Checking Prerequisites ===${NC}"
    
    # Check QEMU
    if [[ ! -x "${QEMU_BIN}" ]]; then
        log_error "Custom QEMU not found: ${QEMU_BIN}"
        exit 1
    fi
    log_success "Custom QEMU: ${QEMU_BIN}"
    
    # Check ROM
    if [[ ! -f "${ROM_FILE}" ]]; then
        log_error "ROM file not found: ${ROM_FILE}"
        exit 1
    fi
    log_success "ROM: ${ROM_FILE}"
    
    # Check disk
    if [[ ! -f "${DISK_FILE}" ]]; then
        log_warn "Disk file not found, will be created"
    else
        log_success "Disk: ${DISK_FILE}"
    fi
    
    # Check ISO
    if [[ ! -f "${ISO_FILE}" ]]; then
        log_error "ISO file not found: ${ISO_FILE}"
        exit 1
    fi
    log_success "ISO: ${ISO_FILE}"
    
    # Check Python
    if ! command -v python3 &>/dev/null; then
        log_error "Python 3 not found"
        exit 1
    fi
    log_success "Python 3: $(python3 --version)"
    
    echo ""
}

create_disk_if_needed() {
    if [[ ! -f "${DISK_FILE}" ]]; then
        log_info "Creating disk image..."
        qemu-img create -f qcow2 "${DISK_FILE}" 40G || {
            log_error "Failed to create disk image"
            exit 1
        }
        log_success "Created 40GB disk: ${DISK_FILE}"
    fi
}

start_qemu_for_install() {
    log_info "Starting QEMU for installation..."
    
    # Clean up old sockets
    rm -f "${QMP_SOCKET}" "${MONITOR_SOCKET}" 2>/dev/null || true
    
    ${QEMU_BIN} \
        -name "${VM_NAME}-install" \
        -machine mac99,via=pmu \
        -cpu 970fx \
        -m 2048 \
        -smp 2 \
        -bios "${ROM_FILE}" \
        -hda "${DISK_FILE}" \
        -cdrom "${ISO_FILE}" \
        -boot d \
        -device VGA,vgamem_mb=64 \
        -device secondary-vga,vgamem_mb=32 \
        -device usb-kbd \
        -device usb-mouse \
        -nic user,model=sungem \
        -rtc base=localtime \
        -audiodev coreaudio,id=snd0 \
        -display none \
        -serial null \
        -nographic \
        -qmp unix:${QMP_SOCKET},server,nowait \
        -monitor unix:${MONITOR_SOCKET},server,nowait \
        2>/tmp/qemu_install_${VM_NAME}.log &
    
    QEMU_PID=$!
    log_success "QEMU started with PID: ${QEMU_PID}"
    
    # Wait for sockets to be created
    for i in $(seq 1 20); do
        if [[ -S "${QMP_SOCKET}" ]]; then
            log_success "QMP socket created: ${QMP_SOCKET}"
            break
        fi
        sleep 0.5
    done
    
    # Verify QEMU is running
    if ! ps -p ${QEMU_PID} > /dev/null 2>&1; then
        log_error "QEMU failed to start"
        cat /tmp/qemu_install_${VM_NAME}.log
        exit 1
    fi
    
    return 0
}

wait_for_qemu_initialization() {
    log_info "Waiting for QEMU to initialize..."
    
    # Wait for VM to start booting
    for i in $(seq 1 30); do
        if [[ -S "${QMP_SOCKET}" ]]; then
            # Try to connect to QMP
            if timeout 2s python3 -c "
import socket, json, sys
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect('${QMP_SOCKET}')
    s.close()
    sys.exit(0)
except:
    sys.exit(1)
" 2>/dev/null; then
                log_success "QEMU is ready"
                return 0
            fi
        fi
        sleep 1
    done
    
    log_error "QEMU initialization timed out"
    return 1
}

run_installation() {
    log_info "Starting installation automation..."
    
    # Run the Python automation script
    python3 "${SCRIPT_DIR}/qemu_install_automation.py" \
        --vm-name "${VM_NAME}" \
        --iso "${ISO_FILE}" \
        --disk "${DISK_FILE}" \
        --rom "${ROM_FILE}" \
        --cpus 2 \
        --timeout ${TIMEOUT}
    
    return $?
}

# Main execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

main() {
    cleanup
    check_prerequisites
    create_disk_if_needed
    
    # Start QEMU
    if ! start_qemu_for_install; then
        exit 1
    fi
    
    # Wait for initialization
    if ! wait_for_qemu_initialization; then
        exit 1
    fi
    
    # Run installation automation
    if run_installation; then
        log_success "Installation completed successfully!"
    else
        log_error "Installation failed or timed out"
        exit 1
    fi
}

main "$@"
