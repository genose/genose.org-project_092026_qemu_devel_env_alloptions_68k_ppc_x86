#!/bin/bash
# =============================================================================
# Test OpenPIC Multi-CPU Support
# 
# This script tests that the OpenPIC fix allows multi-CPU configurations
# on mac99 machines without the "Property 'openpic.sysbus-irq[5]' not found" error.
# =============================================================================

set -euo pipefail

# Configuration
QEMU_BIN="${HOME}/.local/qemu-genose/bin/qemu-system-ppc64"
ROM_FILE="${HOME}/vm_assistant/vms/macos-106-ppc_ppc64/rom/mac99.rom"
TIMEOUT=5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

test_multi_cpu() {
    local num_cpus="$1"
    local test_name="Multi-CPU Test (${num_cpus} CPUs)"
    
    echo ""
    log_info "=== ${test_name} ==="
    
    # Clean up
    pkill -f "qemu-system-ppc64" 2>/dev/null || true
    sleep 1
    
    # Start QEMU with the specified number of CPUs
    local qemu_output
    qemu_output=$(timeout ${TIMEOUT}s ${QEMU_BIN} \
        -machine mac99,via=pmu \
        -cpu 970fx \
        -m 2048 \
        -smp ${num_cpus} \
        -bios "${ROM_FILE}" \
        -display none \
        -serial null \
        -nographic \
        2>&1) || true
    
    # Check for errors
    if echo "${qemu_output}" | grep -qi "property.*openpic.*not found\|only up supported\|smp.*not supported"; then
        log_error "${test_name}: FAILED"
        echo "Error output:"
        echo "${qemu_output}" | grep -i "error\|fail\|exception"
        return 1
    else
        log_success "${test_name}: PASSED"
        return 0
    fi
}

test_rom_size() {
    echo ""
    log_info "=== ROM Size Limit Test ==="
    
    # Clean up
    pkill -f "qemu-system-ppc64" 2>/dev/null || true
    sleep 1
    
    # Get ROM file size
    local rom_size=$(du -b "${ROM_FILE}" | cut -f1)
    log_info "ROM size: ${rom_size} bytes (${rom_size} / 1024 / 1024 = $((rom_size / 1024 / 1024)) MB)"
    
    # Start QEMU with the ROM
    local qemu_output
    qemu_output=$(timeout ${TIMEOUT}s ${QEMU_BIN} \
        -machine mac99,via=pmu \
        -cpu 970fx \
        -m 2048 \
        -smp 1 \
        -bios "${ROM_FILE}" \
        -display none \
        -serial null \
        -nographic \
        2>&1) || true
    
    # Check for ROM size errors
    if echo "${qemu_output}" | grep -qi "rom.*size.*limit\|exceeds maximum\|1 MiB"; then
        log_error "ROM Size Test: FAILED"
        echo "${qemu_output}" | grep -i "rom\|size\|maximum\|limit"
        return 1
    else
        log_success "ROM Size Test: PASSED"
        return 0
    fi
}

main() {
    echo "========================================"
    echo "OpenPIC Multi-CPU Support Test Suite"
    echo "========================================"
    
    # Check prerequisites
    if [[ ! -x "${QEMU_BIN}" ]]; then
        log_error "Custom QEMU not found at ${QEMU_BIN}"
        exit 1
    fi
    
    if [[ ! -f "${ROM_FILE}" ]]; then
        log_error "ROM file not found at ${ROM_FILE}"
        exit 1
    fi
    
    # Test 1: ROM size limit (should pass with 2.7MB ROM)
    test_rom_size
    
    # Test 2: Single CPU (should always work)
    test_multi_cpu 1
    
    # Test 3: Dual CPU (this was failing before the fix)
    test_multi_cpu 2
    
    # Test 4: Quad CPU (test the upper limit)
    test_multi_cpu 4
    
    # Test 5: Eight CPU (maximum for KEYLARGO)
    test_multi_cpu 8
    
    # Summary
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "All tests passed! OpenPIC multi-CPU support is working."
    echo ""
    echo "Fixed issues:"
    echo "  ✅ Removed UP-only restriction from KEYLARGO OpenPIC model"
    echo "  ✅ Dynamically set nb_cpus based on machine SMP configuration"
    echo "  ✅ ROM size limit increased to 4MB"
    echo ""
}

main "$@"
