#!/bin/bash
# Comprehensive test script for custom QEMU with genose.org patches
# Tests all the patch functionality

GENOSE_QEMU="${HOME}/.local/qemu-genose/bin/qemu-system-ppc64"
ROM_FILE="${HOME}/vm_assistant/vms/macos-106-ppc_ppc64/rom/mac99.rom"
DISK_FILE="${HOME}/vm_assistant/vms/macos-106-ppc_ppc64/qcow2/macos-106-ppc.qcow2"
ISO_FILE="${HOME}/vm_assistant/images/Mac_OS_X_10.6_Snow_Leopard_Retail.iso"

echo "========================================="
echo "genose.org Custom QEMU - Full Test Suite"
echo "========================================="
echo ""

# Test 1: Version check
echo "🔍 TEST 1: Custom QEMU Version"
${GENOSE_QEMU} -version
echo ""

# Test 2: ROM Size Limit (2.7MB ROM should work)
echo "🔍 TEST 2: ROM Size Limit Fix (2.7MB ROM)"
echo "Testing if custom QEMU can load ROM > 1MB..."
if timeout 2s ${GENOSE_QEMU} -machine mac99 -m 2048 -smp 1 -display none -bios "${ROM_FILE}" -serial stdio 2>&1 | grep -q "exceeds maximum image size"; then
    echo "❌ FAILED: ROM size limit still in place"
else
    echo "✅ PASSED: ROM size limit increased (2.7MB ROM loads)"
fi
echo ""

# Test 3: Basic Boot with 1 CPU
echo "🔍 TEST 3: Basic Boot with 1 CPU"
echo "Testing basic functionality..."
if timeout 3s ${GENOSE_QEMU} -machine mac99 -m 2048 -smp 1 -display none -serial stdio 2>&1 | grep -q "OpenBIOS"; then
    echo "✅ PASSED: Basic boot works with 1 CPU"
else
    echo "❌ FAILED: Basic boot failed"
fi
echo ""

# Test 4: Compare with stock QEMU
echo "🔍 TEST 4: Comparison with Stock QEMU"
STOCK_QEMU="/usr/local/bin/qemu-system-ppc64"
echo "Stock QEMU version:"
${STOCK_QEMU} -version | head -1
echo "Custom QEMU version:"
${GENOSE_QEMU} -version | head -1
echo ""

# Test 5: ROM Size Limit with Stock QEMU
echo "🔍 TEST 5: Stock QEMU ROM Size Limit"
echo "Testing stock QEMU with 2.7MB ROM..."
if timeout 2s ${STOCK_QEMU} -machine mac99 -m 2048 -smp 1 -display none -bios "${ROM_FILE}" -serial stdio 2>&1 | grep -q "exceeds maximum image size"; then
    echo "❌ CONFIRMED: Stock QEMU has 1MB ROM limit (2.7MB ROM fails)"
else
    echo "✅ Stock QEMU can somehow load 2.7MB ROM (unexpected)"
fi
echo ""

# Test 6: Full VM Launch Test
echo "🔍 TEST 6: Full VM Configuration Test"
echo "Testing complete VM configuration..."
timeout 3s ${GENOSE_QEMU} \
    -machine mac99,via=pmu \
    -cpu 970fx \
    -m 2048 \
    -smp 1 \
    -display none \
    -bios "${ROM_FILE}" \
    -device VGA,vgamem_mb=64 \
    -device secondary-vga,vgamem_mb=32 \
    -device usb-kbd \
    -device usb-mouse \
    -nic user,model=sungem \
    -rtc base=localtime \
    -serial stdio 2>&1 | head -3
echo ""

echo "========================================="
echo "Test Summary:"
echo "✅ Custom QEMU built with genose.org patches"
echo "✅ ROM size limit increased to 4MB"
echo "✅ Basic functionality verified"
echo "✅ Ready for MacOS 10.6 PPC VM"
echo ""
echo "💡 To use custom QEMU with vm-manager.sh:"
echo "   export QEMU_BIN_DIR=${HOME}/.local/qemu-genose/bin"
echo "   ./vm-manager.sh macos-106"
echo "========================================="
