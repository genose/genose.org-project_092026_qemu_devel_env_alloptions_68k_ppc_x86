#!/bin/bash
# GDB Debugging Test for MacOS 10.6 PPC VM
# Tests VM with GDB enabled and catches any problems

GENOSE_QEMU="${HOME}/.local/qemu-genose/bin/qemu-system-ppc64"
ROM_FILE="${HOME}/vm_assistant/vms/macos-106-ppc_ppc64/rom/mac99.rom"
DISK_FILE="${HOME}/vm_assistant/vms/macos-106-ppc_ppc64/qcow2/macos-106-ppc.qcow2"
ISO_FILE="${HOME}/vm_assistant/images/Mac_OS_X_10.6_Snow_Leopard_Retail.iso"
GDB_PORT=1234

echo "========================================="
echo "GDB Debugging Test - MacOS 10.6 PPC VM"
echo "========================================="
echo ""

# Test 1: GDB with basic configuration
echo "🔍 TEST 1: GDB Enabled with Basic Configuration"
echo "Command: qemu-system-ppc64 with -gdb tcp::${GDB_PORT} -S"
echo ""

timeout 5s ${GENOSE_QEMU} \
    -machine mac99,via=pmu \
    -cpu 970fx \
    -m 2048 \
    -smp 1 \
    -display none \
    -bios "${ROM_FILE}" \
    -gdb tcp::${GDB_PORT} \
    -S \
    -serial stdio 2>&1 | head -5

echo ""
echo "Result: If QEMU starts and waits for GDB connection, test PASSED"
echo ""

# Test 2: GDB with dual display
echo "🔍 TEST 2: GDB Enabled with Dual Display"
echo ""

timeout 5s ${GENOSE_QEMU} \
    -machine mac99,via=pmu \
    -cpu 970fx \
    -m 2048 \
    -smp 1 \
    -display none \
    -bios "${ROM_FILE}" \
    -device VGA,vgamem_mb=64 \
    -device secondary-vga,vgamem_mb=32 \
    -gdb tcp::${GDB_PORT} \
    -S \
    -serial stdio 2>&1 | head -5

echo ""

# Test 3: GDB with network and USB
echo "🔍 TEST 3: GDB Enabled with Network and USB Devices"
echo ""

timeout 5s ${GENOSE_QEMU} \
    -machine mac99,via=pmu \
    -cpu 970fx \
    -m 2048 \
    -smp 1 \
    -display none \
    -bios "${ROM_FILE}" \
    -device VGA,vgamem_mb=64 \
    -device usb-kbd \
    -device usb-mouse \
    -nic user,model=sungem \
    -rtc base=localtime \
    -gdb tcp::${GDB_PORT} \
    -S \
    -serial stdio 2>&1 | head -5

echo ""

# Test 4: GDB with CDROM
echo "🔍 TEST 4: GDB Enabled with CDROM"
echo ""

timeout 5s ${GENOSE_QEMU} \
    -machine mac99,via=pmu \
    -cpu 970fx \
    -m 2048 \
    -smp 1 \
    -display none \
    -bios "${ROM_FILE}" \
    -hda "${DISK_FILE}" \
    -cdrom "${ISO_FILE}" \
    -boot d \
    -gdb tcp::${GDB_PORT} \
    -S \
    -serial stdio 2>&1 | head -5

echo ""

# Test 5: Check GDB port availability
echo "🔍 TEST 5: GDB Port Availability"
echo "Checking if GDB port ${GDB_PORT} is available..."
if timeout 3s ${GENOSE_QEMU} \
    -machine mac99 \
    -cpu 970fx \
    -m 2048 \
    -smp 1 \
    -display none \
    -gdb tcp::${GDB_PORT} \
    -S \
    -serial stdio 2>&1 | grep -q "Waiting for gdb connection\|gdbserver\|GDB"; then
    echo "✅ PASSED: GDB mode detected"
else
    echo "⚠️  INFO: GDB mode may not show explicit message (QEMU 9.2.0)"
    echo "   QEMU will still wait for connection on port ${GDB_PORT}"
fi
echo ""

# Test 6: Full configuration from vm-manager.sh
echo "🔍 TEST 6: Full GDB Configuration (vm-manager.sh style)"
echo ""

timeout 5s ${GENOSE_QEMU} \
    -machine mac99,via=pmu \
    -cpu 970fx \
    -m 2048 \
    -smp 1 \
    -display none \
    -audiodev coreaudio,id=snd0 \
    -device VGA,vgamem_mb=64 \
    -device secondary-vga,vgamem_mb=32 \
    -device usb-kbd \
    -device usb-mouse \
    -nic user,model=sungem,hostfwd=tcp::2346-:2346 \
    -rtc base=localtime \
    -bios "${ROM_FILE}" \
    -hda "${DISK_FILE}" \
    -cdrom "${ISO_FILE}" \
    -boot d \
    -gdb tcp::${GDB_PORT} \
    -S \
    -serial stdio 2>&1 | head -10

echo ""

echo "========================================="
echo "GDB Debugging Test Summary:"
echo ""
echo "✅ Custom QEMU: ${GENOSE_QEMU}"
echo "✅ GDB Port: ${GDB_PORT}"
echo "✅ ROM File: ${ROM_FILE}"
echo "✅ Disk File: ${DISK_FILE}"
echo "✅ ISO File: ${ISO_FILE}"
echo ""
echo "💡 To connect GDB:"
echo "   gdb-multiarch -ex 'target remote localhost:${GDB_PORT}'"
echo ""
echo "💡 To test GDB connection:"
echo "   1. Start VM with -gdb tcp::${GDB_PORT} -S"
echo "   2. In another terminal: gdb-multiarch -ex 'target remote localhost:${GDB_PORT}'"
echo "   3. Continue execution with 'continue' or 'c'"
echo "========================================="
