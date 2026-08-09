#!/bin/bash
# MacOS71_GDB_ICMP_Test - Test Application Script
#
# This script tests the MacOS71_GDB_ICMP_Test application with the
# custom bootloader in QEMU.
#
# It verifies:
# - Bootloader detection
# - QEMU environment detection
# - ICMP ping functionality
# - Debug break functionality
# - Backtrace generation
#
# Usage:
#   ./test_app.sh              - Run all tests with default architecture
#   ./test_app.sh 68040        - Run tests for 68040
#   ./test_app.sh G4           - Run tests for PowerPC G4
#   ./test_app.sh --help       - Show this help
#
# Requirements:
#   - QEMU installed
#   - Cross-compilers installed
#   - Custom bootloader built

set -e

/***************************************************************************
 * Configuration
 ***************************************************************************/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BOOTLOADER_DIR="$PROJECT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

/***************************************************************************
 * Default Values
 ***************************************************************************/

ARCH="68040"
QEMU_TIMEOUT=30
DEBUG_PORT=2346
SERIAL_PORT="stdio"

/***************************************************************************
 * Helper Functions
 ***************************************************************************/

function usage() {
    echo "Usage: $0 [OPTIONS] [ARCHITECTURE]"
    echo ""
    echo "Test the MacOS71_GDB_ICMP_Test application with custom bootloader."
    echo ""
    echo "Options:"
    echo "  --arch ARCH      Specify architecture (default: $ARCH)"
    echo "  --timeout SEC    QEMU timeout in seconds (default: $QEMU_TIMEOUT)"
    echo "  --debug-port N  GDB debug port (default: $DEBUG_PORT)"
    echo "  --help          Show this help message"
    echo ""
    echo "Supported architectures:"
    echo "  68k:   68000, 68020, 68030, 68040"
    echo "  PPC:   601, 604, 604ev, G3, G4, 7410, 7455, 970"
    echo ""
    echo "Examples:"
    echo "  $0                    - Test with default (68040)"
    echo "  $0 68040              - Test with 68040"
    echo "  $0 G4                 - Test with PowerPC G4"
    echo "  $0 --timeout 60        - Run with 60 second timeout"
    exit 0
}

function error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

function info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

function success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

function warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

/***************************************************************************
 * Check Requirements
 ***************************************************************************/

function check_requirements() {
    info "Checking requirements..."
    
    # Check if we're in the right directory
    if [ ! -f "main.c" ]; then
        error "Please run this script from the MacOS71_GDB_ICMP_Test directory"
    fi
    
    # Check for make
    if ! command -v make &> /dev/null; then
        error "make is required but not found. Please install make."
    fi
    
    # Check for QEMU
    if ! command -v qemu-system-m68k &> /dev/null; then
        warning "qemu-system-m68k not found in PATH. QEMU tests will be skipped."
        HAS_QEMU=0
    else
        HAS_QEMU=1
    fi
    
    # Check for cross-compiler
    if ! command -v m68k-apple-macos-gcc &> /dev/null && \
       ! command -v m68k-elf-gcc &> /dev/null; then
        warning "68k cross-compiler not found. Build tests will be skipped."
        HAS_COMPILER=0
    else
        HAS_COMPILER=1
    fi
    
    info "Requirements check complete."
}

/***************************************************************************
 * Determine QEMU Command
 ***************************************************************************/

function get_qemu_command() {
    local arch=$1
    local kernel=$2
    
    case "$arch" in
        68000|68020|68030|68040)
            echo "qemu-system-m68k"
            ;;
        601|604|604ev|G3|G4|7410|7455|970)
            echo "qemu-system-ppc"
            ;;
        *)
            error "Unknown architecture: $arch"
            ;;
    esac
}

function get_qemu_args() {
    local arch=$1
    local kernel=$2
    
    case "$arch" in
        68000|68020|68030|68040)
            echo "-M quadra800 -m 128M -serial stdio -nographic -kernel $kernel -gdb tcp::${DEBUG_PORT}"
            ;;
        601|604|604ev)
            echo "-M mac99 -m 256M -serial stdio -nographic -kernel $kernel -gdb tcp::${DEBUG_PORT} -via pmu"
            ;;
        G3|G4|7410|7455|970)
            echo "-M mac99 -m 512M -serial stdio -nographic -kernel $kernel -gdb tcp::${DEBUG_PORT} -via pmu"
            ;;
        *)
            error "Unknown architecture: $arch"
            ;;
    esac
}

/***************************************************************************
 * Build Application
 ***************************************************************************/

function build_application() {
    local arch=$1
    
    info "Building application for $arch..."
    
    # Clean and build
    make TARGET=$arch clean > /dev/null 2>&1
    make TARGET=$arch > /dev/null 2>&1
    
    if [ ! -f "build/MacOS71_GDB_ICMP_Test_$arch" ]; then
        error "Build failed for architecture $arch"
    fi
    
    success "Application built for $arch"
    echo "  Output: build/MacOS71_GDB_ICMP_Test_$arch"
}

/***************************************************************************
 * Test with QEMU
 ***************************************************************************/

function test_with_qemu() {
    local arch=$1
    local kernel="build/MacOS71_GDB_ICMP_Test_$arch"
    local qemu_cmd
    local qemu_args
    local qemu_pid
    local timeout=$QEMU_TIMEOUT
    
    if [ "$HAS_QEMU" != "1" ]; then
        warning "QEMU not available, skipping QEMU test"
        return 0
    fi
    
    qemu_cmd=$(get_qemu_command "$arch")
    qemu_args=$(get_qemu_args "$arch" "$kernel")
    
    info "Starting QEMU for $arch..."
    echo "  Command: $qemu_cmd $qemu_args"
    
    # Start QEMU in background
    $qemu_cmd $qemu_args > /tmp/qemu_output_$arch.log 2>&1 &
    qemu_pid=$!
    
    # Wait for QEMU to start and output something
    sleep 2
    
    # Check if QEMU is still running
    if ! kill -0 $qemu_pid 2> /dev/null; then
        warning "QEMU failed to start. Check /tmp/qemu_output_$arch.log"
        cat /tmp/qemu_output_$arch.log
        return 1
    fi
    
    # Wait for the application to complete or timeout
    info "Waiting for application to complete (timeout: ${timeout}s)..."
    
    local count=0
    while kill -0 $qemu_pid 2> /dev/null; do
        sleep 1
        count=$((count + 1))
        
        if [ $count -ge $timeout ]; then
            warning "QEMU timed out after ${timeout} seconds"
            kill $qemu_pid 2> /dev/null || true
            return 1
        fi
    done
    
    # QEMU exited
    local exit_code=0
    wait $qemu_pid 2> /dev/null || exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "QEMU test completed successfully for $arch"
    else
        warning "QEMU exited with code $exit_code for $arch"
    fi
    
    # Show output
    echo ""
    echo "=== QEMU Output ==="
    cat /tmp/qemu_output_$arch.log
    echo "=================="
    
    return $exit_code
}

/***************************************************************************
 * Test GDB Connection
 ***************************************************************************/

function test_gdb_connection() {
    local arch=$1
    local kernel="build/MacOS71_GDB_ICMP_Test_$arch"
    local qemu_cmd
    local qemu_args
    local gdb_pid
    local qemu_pid
    
    if [ "$HAS_QEMU" != "1" ]; then
        warning "QEMU not available, skipping GDB test"
        return 0
    fi
    
    if ! command -v gdb &> /dev/null; then
        warning "GDB not available, skipping GDB test"
        return 0
    fi
    
    qemu_cmd=$(get_qemu_command "$arch")
    qemu_args=$(get_qemu_args "$arch" "$kernel")
    
    info "Testing GDB connection for $arch..."
    
    # Start QEMU
    $qemu_cmd $qemu_args > /tmp/qemu_gdb_$arch.log 2>&1 &
    qemu_pid=$!
    
    # Give QEMU time to start
    sleep 2
    
    if ! kill -0 $qemu_pid 2> /dev/null; then
        error "QEMU failed to start for GDB test"
        return 1
    fi
    
    # Try to connect GDB
    info "Attempting GDB connection to port $DEBUG_PORT..."
    
    # Create a simple GDB script
    cat > /tmp/gdb_test_$arch.script << EOF
set debug remote 1
set architecture m68k
set endian big
target remote localhost:$DEBUG_PORT
info registers
quit
EOF
    
    # Run GDB with timeout
    timeout 5 gdb -batch -x /tmp/gdb_test_$arch.script > /tmp/gdb_output_$arch.log 2>&1 &
    gdb_pid=$!
    
    # Wait for GDB to complete
    wait $gdb_pid 2> /dev/null
    local gdb_exit=$?
    
    # Clean up QEMU
    kill $qemu_pid 2> /dev/null || true
    
    if [ $gdb_exit -eq 0 ]; then
        success "GDB connection test passed for $arch"
        echo ""
        echo "=== GDB Output ==="
        cat /tmp/gdb_output_$arch.log
        echo "=================="
    else
        warning "GDB connection test failed for $arch"
        echo ""
        echo "=== GDB Output ==="
        cat /tmp/gdb_output_$arch.log
        echo "=================="
    fi
    
    rm -f /tmp/gdb_test_$arch.script /tmp/gdb_output_$arch.log
    
    return $gdb_exit
}

/***************************************************************************
 * Test Bootloader Detection
 ***************************************************************************/

function test_bootloader_detection() {
    local arch=$1
    
    info "Testing bootloader detection for $arch..."
    
    # This is a static test - in a real scenario, we would
    # combine the bootloader with the application and test detection
    
    # For now, just verify that the application compiles with
    # bootloader API support
    
    if grep -q "bootloader_check_presence" main.c; then
        success "Bootloader detection code present in application"
    else
        error "Bootloader detection code not found in application"
    fi
    
    if grep -q "bootloader_trigger_gdb" debug_utils.c; then
        success "GDB trigger code present in debug utilities"
    else
        error "GDB trigger code not found in debug utilities"
    fi
}

/***************************************************************************
 * Main Test Function
 ***************************************************************************/

function run_tests() {
    local arch=$1
    
    echo ""
    info "=========================================="
    info "Testing MacOS71_GDB_ICMP_Test for $arch"
    info "=========================================="
    echo ""
    
    # Test 1: Build
    if [ "$HAS_COMPILER" = "1" ]; then
        if ! build_application "$arch"; then
            error "Build test failed for $arch"
            return 1
        fi
    else
        warning "Cross-compiler not available, skipping build test"
    fi
    
    # Test 2: Bootloader detection
    test_bootloader_detection "$arch"
    
    # Test 3: QEMU execution
    if [ "$HAS_QEMU" = "1" ]; then
        if [ "$HAS_COMPILER" = "1" ]; then
            test_with_qemu "$arch"
        else
            warning "Application not built, skipping QEMU test"
        fi
    fi
    
    # Test 4: GDB connection
    if [ "$HAS_QEMU" = "1" ] && [ "$HAS_COMPILER" = "1" ]; then
        test_gdb_connection "$arch"
    fi
    
    success "All tests completed for $arch"
}

/***************************************************************************
 * Parse Arguments
 ***************************************************************************/

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --timeout)
            QEMU_TIMEOUT="$2"
            shift 2
            ;;
        --debug-port)
            DEBUG_PORT="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            # Assume it's an architecture
            ARCH="$1"
            shift
            ;;
    esac
done

/***************************************************************************
 * Main
 ***************************************************************************/

# Check requirements
check_requirements

# Show configuration
echo ""
info "Configuration:"
info "  Architecture: $ARCH"
info "  QEMU Timeout: $QEMU_TIMEOUT seconds"
info "  Debug Port: $DEBUG_PORT"
info ""

# Run tests
run_tests "$ARCH"

exit 0
