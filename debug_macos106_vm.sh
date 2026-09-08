#!/bin/bash
# =============================================================================
# MacOS 10.6 PPC VM - Complete Debugging and Monitoring Solution
# 
# This script provides a complete debugging environment for MacOS 10.6 PPC VM:
#   1. Starts VM with GDB debugging enabled
#   2. Captures all output to log files
#   3. Tests GDB connection
#   4. Provides interactive monitoring
#   5. Allows manual GDB connection for debugging
# =============================================================================

set -euo pipefail

# Configuration
GENOSE_QEMU="${HOME}/.local/qemu-genose/bin/qemu-system-ppc64"
ROM_FILE="${HOME}/vm_assistant/vms/macos-106-ppc_ppc64/rom/mac99.rom"
DISK_FILE="${HOME}/vm_assistant/vms/macos-106-ppc_ppc64/qcow2/macos-106-ppc.qcow2"
ISO_FILE="${HOME}/vm_assistant/images/Mac_OS_X_10.6_Snow_Leopard_Retail.iso"
GDB_PORT=1234
VM_NAME="macos-106-ppc_ppc64"

# Log files with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCREEN_LOG="/tmp/${VM_NAME}_screen_${TIMESTAMP}.log"
QEMU_LOG="/tmp/${VM_NAME}_qemu_${TIMESTAMP}.log"
GDB_LOG="/tmp/${VM_NAME}_gdb_${TIMESTAMP}.log"
MONITOR_LOG="/tmp/${VM_NAME}_monitor_${TIMESTAMP}.log"

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
    rm -f "/tmp/vm_pid_${VM_NAME}.txt" 2>/dev/null || true
    log_info "Cleanup complete"
}

check_prerequisites() {
    echo -e "\n${PURPLE}=== Checking Prerequisites ===${NC}"
    
    # Check QEMU
    if [[ ! -x "${GENOSE_QEMU}" ]]; then
        log_error "Custom QEMU not found at ${GENOSE_QEMU}"
        echo "Build QEMU first: ./vm-manager.sh build-qemu"
        exit 1
    fi
    log_success "Custom QEMU: ${GENOSE_QEMU}"
    
    # Check ROM
    if [[ ! -f "${ROM_FILE}" ]]; then
        log_error "ROM file not found: ${ROM_FILE}"
        exit 1
    fi
    local rom_size=$(du -h "${ROM_FILE}" | cut -f1)
    log_success "ROM: ${ROM_FILE} (${rom_size})"
    
    # Check disk
    if [[ ! -f "${DISK_FILE}" ]]; then
        log_error "Disk file not found: ${DISK_FILE}"
        exit 1
    fi
    local disk_size=$(du -h "${DISK_FILE}" | cut -f1)
    log_success "Disk: ${DISK_FILE} (${disk_size})"
    
    # Check ISO
    if [[ ! -f "${ISO_FILE}" ]]; then
        log_error "ISO file not found: ${ISO_FILE}"
        exit 1
    fi
    local iso_size=$(du -h "${ISO_FILE}" | cut -f1)
    log_success "ISO: ${ISO_FILE} (${iso_size})"
    
    # Check GDB
    local gdb_bin=""
    for candidate in gdb-multiarch gdb gdb64; do
        if command -v "${candidate}" &>/dev/null; then
            gdb_bin="${candidate}"
            break
        fi
    done
    
    if [[ -z "${gdb_bin}" ]]; then
        log_warn "GDB not found. Install gdb-multiarch for best results."
        GDB_BIN="gdb"
    else
        log_success "GDB: ${gdb_bin}"
        GDB_BIN="${gdb_bin}"
    fi
    
    echo ""
}

start_vm_background() {
    echo -e "\n${PURPLE}=== Starting VM in Background ===${NC}"
    
    # Clear log files
    > "${SCREEN_LOG}"
    > "${QEMU_LOG}"
    > "${GDB_LOG}"
    
    log_info "Starting QEMU with GDB debugging..."
    
    # Start QEMU with screen output to serial file and monitor to stdio
    ${GENOSE_QEMU} \
        -machine mac99,via=pmu \
        -cpu 970fx \
        -m 2048 \
        -smp 1 \
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
        -gdb tcp::${GDB_PORT} \
        -S \
        -nographic \
        -serial file:${SCREEN_LOG} \
        -monitor telnet:127.0.0.1:5555,server,nowait \
        > "${MONITOR_LOG}" \
        2> "${QEMU_LOG}" &
    
    QEMU_PID=$!
    echo "${QEMU_PID}" > "/tmp/vm_pid_${VM_NAME}.txt"
    
    log_success "VM started with PID: ${QEMU_PID}"
    log_info "  Screen output: ${SCREEN_LOG}"
    log_info "  QEMU stderr: ${QEMU_LOG}"
    log_info "  Monitor: telnet 127.0.0.1 5555"
    log_info "  GDB port: ${GDB_PORT}"
    
    # Wait for QEMU to initialize
    sleep 3
    
    if ! ps -p ${QEMU_PID} > /dev/null 2>&1; then
        log_error "QEMU failed to start!"
        log_info "QEMU Log:"
        cat "${QEMU_LOG}"
        exit 1
    fi
    
    log_success "QEMU is running (PID: ${QEMU_PID})"
}

test_gdb_connection() {
    echo -e "\n${PURPLE}=== Testing GDB Connection ===${NC}"
    
    log_info "Connecting to GDB port ${GDB_PORT}..."
    
    local gdb_output
    gdb_output=$(timeout 5s ${GDB_BIN} -q \
        -ex "target remote localhost:${GDB_PORT}" \
        -ex "info registers" \
        -ex "info all-registers" \
        -ex "monitor info cpus" \
        -ex "monitor info mem" \
        -ex "quit" 2>&1) || true
    
    echo "${gdb_output}" > "${GDB_LOG}"
    
    if echo "${gdb_output}" | grep -q "Remote debugging using localhost"; then
        log_success "GDB connection successful!"
        
        echo "CPU State:"
        echo "${gdb_output}" | grep -A 15 "Remote debugging"
        echo ""
        
        # Show some register values
        log_info "Register values captured in: ${GDB_LOG}"
        return 0
    else
        log_error "GDB connection failed!"
        echo "${gdb_output}"
        return 1
    fi
}

continue_execution() {
    echo -e "\n${PURPLE}=== Continuing VM Execution ===${NC}"
    
    log_info "Sending continue command..."
    
    local output
    output=$(timeout 3s ${GDB_BIN} -q \
        -ex "target remote localhost:${GDB_PORT}" \
        -ex "continue" \
        -ex "quit" 2>&1) || true
    
    log_success "Continue command sent"
    echo "${output}" | head -5
    
    # Wait for VM to start booting
    sleep 2
}

monitor_vm() {
    echo -e "\n${PURPLE}=== Monitoring VM Activity ===${NC}"
    
    # Check screen output
    log_info "Checking screen output..."
    if [[ -s "${SCREEN_LOG}" ]]; then
        local lines=$(wc -l < "${SCREEN_LOG}")
        log_success "Screen output: ${lines} lines"
        
        echo "Last 10 lines of screen output:"
        tail -10 "${SCREEN_LOG}"
        echo ""
    else
        log_warn "No screen output captured yet"
    fi
    
    # Check QEMU log
    log_info "Checking QEMU stderr log..."
    if [[ -s "${QEMU_LOG}" ]]; then
        local size=$(du -h "${QEMU_LOG}" | cut -f1)
        local lines=$(wc -l < "${QEMU_LOG}")
        log_success "QEMU log: ${size} (${lines} lines)"
        
        # Check for errors
        local errors=$(grep -i -c "error\|fail\|exception" "${QEMU_LOG}" 2>/dev/null || echo "0")
        if [[ ${errors} -gt 0 ]]; then
            log_warn "Found ${errors} potential issues in QEMU log"
            grep -i "error\|fail\|exception" "${QEMU_LOG}" | head -5
            echo ""
        fi
    else
        log_warn "No QEMU log output yet"
    fi
    
    # Check monitor log
    if [[ -s "${MONITOR_LOG}" ]]; then
        log_info "Monitor log has content"
        tail -5 "${MONITOR_LOG}"
        echo ""
    fi
}

display_summary() {
    echo -e "\n${PURPLE}=== DEBUG SUMMARY ===${NC}"
    
    echo "Configuration:"
    echo "  Machine: mac99,via=pmu"
    echo "  CPU: 970fx"
    echo "  RAM: 2048 MB"
    echo "  ROM: ${ROM_FILE}"
    echo "  Disk: ${DISK_FILE}"
    echo "  ISO: ${ISO_FILE}"
    echo ""
    
    echo "Debug Settings:"
    echo "  GDB Port: ${GDB_PORT}"
    echo "  Monitor Port: 5555"
    echo ""
    
    echo "Log Files:"
    echo "  Screen: ${SCREEN_LOG} ($(du -h "${SCREEN_LOG}" 2>/dev/null | cut -f1 || echo "0"))"
    echo "  QEMU:   ${QEMU_LOG} ($(du -h "${QEMU_LOG}" 2>/dev/null | cut -f1 || echo "0"))"
    echo "  GDB:    ${GDB_LOG} ($(du -h "${GDB_LOG}" 2>/dev/null | cut -f1 || echo "0"))"
    echo "  Monitor:${MONITOR_LOG} ($(du -h "${MONITOR_LOG}" 2>/dev/null | cut -f1 || echo "0"))"
    echo ""
    
    echo "VM Status:"
    if ps -p ${QEMU_PID} > /dev/null 2>&1; then
        log_success "VM is RUNNING (PID: ${QEMU_PID})"
    else
        log_error "VM has STOPPED"
    fi
    echo ""
    
    echo "Interactive Commands:"
    echo "  1. Connect GDB: ${GDB_BIN} -ex 'target remote localhost:${GDB_PORT}'"
    echo "  2. Connect Monitor: telnet 127.0.0.1 5555"
    echo "  3. View Screen: tail -f ${SCREEN_LOG}"
    echo "  4. View QEMU Log: tail -f ${QEMU_LOG}"
    echo "  5. Stop VM: kill ${QEMU_PID}"
    echo ""
}

# Main function
main() {
    trap cleanup EXIT
    
    cleanup
    check_prerequisites
    start_vm_background
    
    # Give VM time to initialize
    sleep 2
    
    # Test GDB connection
    if test_gdb_connection; then
        continue_execution
    else
        log_warn "GDB connection test failed, but VM may still be running"
    fi
    
    # Monitor activity
    monitor_vm
    
    # Display summary
    display_summary
    
    echo ""
    log_info "VM is running in background. Use the commands above to interact."
    log_info "Press Ctrl+C to stop the VM and exit."
    
    # Keep running until user stops
    while ps -p ${QEMU_PID} > /dev/null 2>&1; do
        sleep 1
    done
    
    log_info "VM has stopped"
}

main "$@"
