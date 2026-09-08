#!/bin/bash
# Complete GDB Debugging VM Launch Script
# Launches MacOS 10.6 PPC VM with GDB enabled and monitors for problems

GENOSE_QEMU="${HOME}/.local/qemu-genose/bin/qemu-system-ppc64"
ROM_FILE="${HOME}/vm_assistant/vms/macos-106-ppc_ppc64/rom/mac99.rom"
DISK_FILE="${HOME}/vm_assistant/vms/macos-106-ppc_ppc64/qcow2/macos-106-ppc.qcow2"
ISO_FILE="${HOME}/vm_assistant/images/Mac_OS_X_10.6_Snow_Leopard_Retail.iso"
GDB_PORT=1234
LOG_FILE="/tmp/qemu_gdb_debug.log"

echo "========================================="
echo "GDB Debugging VM - Complete Launch Script"
echo "========================================="
echo ""

# Clean up any existing QEMU processes
pkill qemu-system-ppc64 2>/dev/null
sleep 1
echo "✅ Cleaned up existing QEMU processes"
echo ""

# Function to start QEMU with GDB
echo "🚀 Starting QEMU with GDB debugging enabled..."
echo "   Machine: mac99,via=pmu"
echo "   CPU: 970fx"
echo "   RAM: 2048 MB"
echo "   GDB Port: ${GDB_PORT}"
echo "   ROM: ${ROM_FILE}"
echo "   Disk: ${DISK_FILE}"
echo "   ISO: ${ISO_FILE}"
echo ""

# Start QEMU in background with GDB enabled
${GENOSE_QEMU} \
    -machine mac99,via=pmu \
    -cpu 970fx \
    -m 2048 \
    -smp 1 \
    -display none \
    -bios "${ROM_FILE}" \
    -hda "${DISK_FILE}" \
    -cdrom "${ISO_FILE}" \
    -boot d \
    -device VGA,vgamem_mb=64 \
    -device secondary-vga,vgamem_mb=32 \
    -device usb-kbd \
    -device usb-mouse \
    -nic user,model=sungem,hostfwd=tcp::2222-:22 \
    -rtc base=localtime \
    -audiodev coreaudio,id=snd0 \
    -gdb tcp::${GDB_PORT} \
    -S \
    -serial null \
    -daemonize \
    2>"${LOG_FILE}" &

QEMU_PID=$!
echo "✅ QEMU started with PID: ${QEMU_PID}"
echo "✅ QEMU is waiting for GDB connection on port ${GDB_PORT}"
echo ""

# Wait for QEMU to initialize
sleep 2

# Check if QEMU is running
if ps -p ${QEMU_PID} > /dev/null 2>&1; then
    echo "✅ QEMU process confirmed running (PID: ${QEMU_PID})"
else
    echo "❌ QEMU failed to start!"
    echo "   Check log: ${LOG_FILE}"
    cat "${LOG_FILE}"
    exit 1
fi
echo ""

# Test GDB connection
echo "🔍 Testing GDB connection to port ${GDB_PORT}..."
GDB_OUTPUT=$(timeout 5s /usr/local/bin/gdb -q -ex "set debug tui 0" -ex "target remote localhost:${GDB_PORT}" -ex "info registers" -ex "info threads" -ex "quit" 2>&1)

if echo "${GDB_OUTPUT}" | grep -q "Remote debugging using localhost"; then
    echo "✅ GDB connection successful!"
    echo "✅ Target responding to GDB commands"
    echo ""
    echo "GDB Output:"
    echo "${GDB_OUTPUT}" | head -15
else
    echo "❌ GDB connection failed!"
    echo "${GDB_OUTPUT}"
fi
echo ""

# Monitor QEMU for errors
echo "🔍 Monitoring QEMU for errors..."
sleep 1
if [ -s "${LOG_FILE}" ]; then
    echo "⚠️  QEMU logged output:"
    cat "${LOG_FILE}"
else
    echo "✅ No errors in QEMU log"
fi
echo ""

# Display connection information
echo "========================================="
echo "VM Status:"
echo "  ✅ QEMU: Running (PID: ${QEMU_PID})"
echo "  ✅ GDB: Waiting on port ${GDB_PORT}"
echo "  ✅ Configuration: MacOS 10.6 PPC with dual display"
echo ""
echo "Connection Information:"
echo "  QEMU Command: ${GENOSE_QEMU}"
echo "  GDB Connect: gdb -ex 'target remote localhost:${GDB_PORT}'"
echo ""
echo "To connect GDB manually:"
echo "  1. In new terminal: /usr/local/bin/gdb -q"
echo "  2. Run: target remote localhost:${GDB_PORT}"
echo "  3. Run: continue (or c) to start execution"
echo ""
echo "To stop the VM:"
echo "  kill ${QEMU_PID}"
echo ""
echo "To view QEMU log:"
echo "  tail -f ${LOG_FILE}"
echo "========================================="
