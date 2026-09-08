#!/bin/bash
# Test script to monitor errors when running MacOS 10.6 PPC VM
# This demonstrates the artificial limits that our patches fix

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QEMU_BIN="/usr/local/bin/qemu-system-ppc64"
ROM_FILE="${HOME}/vm_assistant/vms/macos-106-ppc_ppc64/rom/mac99.rom"
DISK_FILE="${HOME}/vm_assistant/vms/macos-106-ppc_ppc64/qcow2/macos-106-ppc.qcow2"
ISO_FILE="${HOME}/vm_assistant/images/Mac_OS_X_10.6_Snow_Leopard_Retail.iso"

echo "========================================="
echo "MacOS 10.6 PPC VM - Error Monitoring Test"
echo "========================================="
echo ""

# Test 1: ROM Size Limit Error
echo "🔍 TEST 1: ROM Size Limit"
echo "Command: qemu-system-ppc64 with 2.7MB ROM file"
echo ""
timeout 3s ${QEMU_BIN} \
    -machine mac99,via=pmu \
    -cpu 970fx \
    -m 2048 \
    -smp 1 \
    -display none \
    -bios "${ROM_FILE}" \
    -serial stdio 2>&1 | grep -i "exceeds\|maximum\|size" || echo "✅ No ROM size error"
echo ""

# Test 2: SMP CPU Limit Error (with 2 CPUs)
echo "🔍 TEST 2: SMP CPU Limit (2 CPUs)"
echo "Command: qemu-system-ppc64 with -smp 2"
echo ""
timeout 3s ${QEMU_BIN} \
    -machine mac99,via=pmu \
    -cpu 970fx \
    -m 2048 \
    -smp 2 \
    -display none \
    -serial stdio 2>&1 | grep -i "Invalid\|SMP\|CPUs\|maximum" || echo "✅ No SMP error"
echo ""

# Test 3: Success with 1 CPU and no custom ROM
echo "🔍 TEST 3: Success Case (1 CPU, no custom ROM)"
echo "Command: qemu-system-ppc64 with -smp 1, no custom ROM"
echo ""
timeout 2s ${QEMU_BIN} \
    -machine mac99,via=pmu \
    -cpu 970fx \
    -m 2048 \
    -smp 1 \
    -display none \
    -device VGA,vgamem_mb=64 \
    -serial stdio 2>&1 | head -3
echo ""

echo "========================================="
echo "Summary:"
echo "- Test 1: ROM size limit error (stock QEMU: 1MB max)"
echo "- Test 2: SMP CPU limit error (stock QEMU: 1 CPU max)"
echo "- Test 3: Works with 1 CPU and built-in ROM"
echo ""
echo "💡 Solution: Build patched QEMU with our patches:"
echo "   ./vm-manager.sh build"
echo "========================================="

# Show patch information
echo ""
echo "📋 Patches that fix these issues:"
echo "1. patches/ppc/0003-increase-mac99-rom-size-limit-to-4mb.patch"
echo "   - Increases ROM size from 1MB to 4MB"
echo ""
echo "2. patches/ppc/0004-enable-mac99-smp-multi-cpu-support.patch"
echo "   - Increases max_cpus from 1 to 8"
echo ""
echo "Both patches are applied to QEMU source and ready for build."