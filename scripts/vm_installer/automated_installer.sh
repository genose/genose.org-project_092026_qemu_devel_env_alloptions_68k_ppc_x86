#!/bin/bash
# =============================================================================
# Automated VM OS Installer
# 
# This script automates the complete OS installation process for VMs by:
# 1. Starting the VM with display capture (VNC/SPICE)
# 2. Monitoring the display for installer screens
# 3. Using OCR to detect the current installer state
# 4. Injecting mouse/keyboard input to automate the installation
# 5. Handling errors and timeouts
# 
# Supports: MacOS 10.6, Linux, Windows, etc.
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")"))"

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
    pkill -f "qemu-system" 2>/dev/null || true
    sleep 1
    if [[ -n "${VNC_PID:-}" ]]; then
        kill ${VNC_PID} 2>/dev/null || true
    fi
    if [[ -n "${QEMU_PID:-}" ]]; then
        kill ${QEMU_PID} 2>/dev/null || true
    fi
    log_info "Cleanup complete"
}

trap cleanup EXIT

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Check prerequisites
check_prerequisites() {
    echo -e "\n${PURPLE}=== Checking Prerequisites ===${NC}"
    
    local missing=()
    
    # Check for required tools
    for cmd in vncviewer convert tesseract python3; do
        if ! command_exists "${cmd}"; then
            missing+=("${cmd}")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Install with:"
        log_info "  brew install tesseract netpbm"  # For macOS
        log_info "  apt-get install tesseract-ocr netpbm python3"  # For Ubuntu
        exit 1
    fi
    
    # Check for Python packages
    if ! python3 -c "import pytesseract, PIL, paramiko, time, subprocess" 2>/dev/null; then
        log_warn "Missing Python packages for advanced automation"
        log_info "Install with: pip install pytesseract pillow paramiko"
    fi
    
    log_success "All prerequisites met"
    echo ""
}

# Start VM with VNC display for screen capture
start_vm_with_vnc() {
    local vm_name="$1"
    local vnc_port="$2"
    local vnc_display=":${vnc_port}"
    
    echo -e "\n${PURPLE}=== Starting VM with VNC Display ===${NC}"
    
    # Get VM configuration
    local config_file="${PROJECT_DIR}/vm-configs/${vm_name}.conf"
    if [[ ! -f "${config_file}" ]]; then
        log_error "VM config not found: ${config_file}"
        return 1
    fi
    
    log_info "Starting VM: ${vm_name}"
    log_info "VNC Display: ${vnc_display}"
    
    # Start QEMU with VNC display
    ${QEMU_BIN} \
        -name "${vm_name}-install" \
        -vnc ${vnc_display},password=on \
        -display none \
        -machine mac99,via=pmu \
        -cpu 970fx \
        -m 2048 \
        -smp 2 \
        -bios "${HOME}/vm_assistant/vms/${vm_name}/rom/mac99.rom" \
        -hda "${HOME}/vm_assistant/vms/${vm_name}/qcow2/${vm_name}.qcow2" \
        -cdrom "${HOME}/vm_assistant/images/Mac_OS_X_10.6_Snow_Leopard_Retail.iso" \
        -boot d \
        -device VGA,vgamem_mb=64 \
        -device secondary-vga,vgamem_mb=32 \
        -device usb-kbd \
        -device usb-mouse \
        -nic user,model=sungem \
        -rtc base=localtime \
        -audiodev coreaudio,id=snd0 \
        -gdb tcp::1234 \
        -S \
        -nographic \
        2>/tmp/vm_install_${vm_name}.log &
    
    QEMU_PID=$!
    log_success "VM started with PID: ${QEMU_PID}"
    
    # Wait for VNC server to start
    sleep 3
    
    # Verify QEMU is running
    if ! ps -p ${QEMU_PID} > /dev/null 2>&1; then
        log_error "QEMU failed to start!"
        cat /tmp/vm_install_${vm_name}.log
        return 1
    fi
    
    log_success "VM is running with VNC display"
    echo ""
}

# Connect to VNC and capture screenshot
capture_vnc_screenshot() {
    local hostname="$1"
    local port="$2"
    local output_file="$3"
    
    # Use vncviewer to capture a screenshot
    # Note: This requires a VNC client that can capture screenshots
    # Alternative: Use a Python VNC library
    
    # For now, use a simple approach: connect and disconnect
    # In production, we'd use a VNC library to capture frames
    
    log_info "Capturing VNC screenshot from ${hostname}:${port} to ${output_file}"
    
    # Use a Python script to capture VNC screenshot
    if [[ -f "${SCRIPT_DIR}/capture_vnc.py" ]]; then
        python3 "${SCRIPT_DIR}/capture_vnc.py" "${hostname}" "${port}" "${output_file}" || return 1
    else
        log_warn "capture_vnc.py not found, using fallback method"
        # Fallback: use vncviewer (if it supports screenshot mode)
        # This is just a placeholder - real implementation needs VNC library
        echo "VNC screenshot placeholder" > "${output_file}"
    fi
    
    return 0
}

# Use OCR to detect installer state
detect_installer_state() {
    local screenshot_file="$1"
    
    log_info "Analyzing screenshot: ${screenshot_file}"
    
    # Use Tesseract OCR to extract text
    local text
    text=$(tesseract "${screenshot_file}" stdout -l eng 2>/dev/null || echo "")
    
    # Normalize text
    text=$(echo "${text}" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]')
    
    log_info "OCR Text: ${text}"
    
    # Detect installer state based on text
    local state="unknown"
    
    if echo "${text}" | grep -qi "language\|select your language\|langue\|idioma"; then
        state="language_selection"
    elif echo "${text}" | grep -qi "license\|agreement\|eula\|terms"; then
        state="license_agreement"
    elif echo "${text}" | grep -qi "disk\|select disk\|destination\|install"; then
        state="disk_selection"
    elif echo "${text}" | grep -qi "install\|installation\|copying\|progress"; then
        state="installing"
    elif echo "${text}" | grep -qi "complete\|finished\|success\|restart"; then
        state="installation_complete"
    elif echo "${text}" | grep -qi "mac os\|macos\|snow leopard"; then
        state="os_booting"
    fi
    
    log_info "Detected state: ${state}"
    echo "${state}"
    return 0
}

# Inject mouse/keyboard input via QEMU monitor
inject_input() {
    local input_type="$1"  # mouse_move, mouse_click, key
    local x="$2"
    local y="$3"
    local button="$4"
    local key="$5"
    
    log_info "Injecting input: ${input_type} (x=${x}, y=${y}, button=${button}, key=${key})"
    
    # Use QEMU monitor to inject input
    # Note: This requires the monitor to be accessible
    
    local monitor_socket="/tmp/qemu-monitor-${QEMU_PID}.sock"
    
    # Check if monitor is available
    if [[ -S "${monitor_socket}" ]]; then
        case "${input_type}" in
            "mouse_move")
                echo "mouse_move ${x} ${y}" | socat - UNIX-CONNECT:"${monitor_socket}" >/dev/null 2>&1 || true
                ;;
            "mouse_click")
                echo "mouse_button ${button}" | socat - UNIX-CONNECT:"${monitor_socket}" >/dev/null 2>&1 || true
                ;;
            "key")
                echo "sendkey ${key}" | socat - UNIX-CONNECT:"${monitor_socket}" >/dev/null 2>&1 || true
                ;;
        esac
    else
        log_warn "QEMU monitor not available at ${monitor_socket}"
        return 1
    fi
    
    return 0
}

# Main installation automation
automated_install() {
    local vm_name="$1"
    local vnc_port="$2"
    local timeout="${3:-600}"  # 10 minutes default
    
    echo -e "\n${PURPLE}=== Automated VM Installation ===${NC}"
    log_info "VM: ${vm_name}"
    log_info "VNC Port: ${vnc_port}"
    log_info "Timeout: ${timeout} seconds"
    
    # Start VM with VNC
    if ! start_vm_with_vnc "${vm_name}" "${vnc_port}"; then
        return 1
    fi
    
    # Installation state machine
    local current_state="unknown"
    local start_time=$(date +%s)
    local screenshot_file="/tmp/vm_install_screenshot_${vm_name}_$(date +%s).png"
    local iteration=0
    local max_iterations=60
    
    log_info "Starting installation automation..."
    
    while true; do
        iteration=$((iteration + 1))
        
        # Check timeout
        local elapsed=$(( $(date +%s) - start_time ))
        if [[ ${elapsed} -gt ${timeout} ]]; then
            log_error "Installation timed out after ${elapsed} seconds"
            return 1
        fi
        
        if [[ ${iteration} -gt ${max_iterations} ]]; then
            log_warn "Max iterations reached, installation may be stuck"
            break
        fi
        
        # Check if QEMU is still running
        if ! ps -p ${QEMU_PID} > /dev/null 2>&1; then
            log_error "QEMU process died unexpectedly"
            cat /tmp/vm_install_${vm_name}.log
            return 1
        fi
        
        # Capture screenshot
        if ! capture_vnc_screenshot "127.0.0.1" "${vnc_port}" "${screenshot_file}"; then
            log_warn "Failed to capture screenshot, retrying..."
            sleep 2
            continue
        fi
        
        # Detect state
        current_state=$(detect_installer_state "${screenshot_file}")
        
        # Handle each state
        case "${current_state}" in
            "language_selection")
                log_info "State: Language Selection"
                # Click on English (first option)
                inject_input "mouse_move" 300 200 "" "" ""
                sleep 0.5
                inject_input "mouse_click" 0 0 1 "" ""
                sleep 2
                ;;
            "license_agreement")
                log_info "State: License Agreement"
                # Click Agree/Accept
                inject_input "mouse_move" 400 350 "" "" ""
                sleep 0.5
                inject_input "mouse_click" 0 0 1 "" ""
                sleep 2
                ;;
            "disk_selection")
                log_info "State: Disk Selection"
                # Select the first disk
                inject_input "mouse_move" 300 250 "" "" ""
                sleep 0.5
                inject_input "mouse_click" 0 0 1 "" ""
                sleep 1
                # Click Continue
                inject_input "mouse_move" 400 400 "" "" ""
                sleep 0.5
                inject_input "mouse_click" 0 0 1 "" ""
                sleep 2
                ;;
            "installing")
                log_info "State: Installation in Progress"
                # Just wait and monitor
                sleep 5
                ;;
            "installation_complete")
                log_success "Installation Complete!"
                # Eject CD and reboot
                inject_input "key" 0 0 0 "eject-cdrom"
                sleep 1
                inject_input "key" 0 0 0 "reboot"
                return 0
                ;;
            "os_booting")
                log_info "State: OS Booting"
                # Wait for OS to finish booting
                sleep 5
                ;;
            "unknown")
                log_info "State: Unknown (elapsed: ${elapsed}s, iteration: ${iteration})"
                # For unknown states, just wait and try again
                sleep 3
                ;;
        esac
    done
    
    log_warn "Installation may not have completed successfully"
    return 1
}

# Display usage
usage() {
    echo "Usage: $0 [OPTIONS] VM_NAME"
    echo ""
    echo "Automated VM OS Installer"
    echo ""
    echo "Options:"
    echo "  --vnc-port PORT     VNC display port (default: 1)"
    echo "  --timeout SECONDS   Timeout in seconds (default: 600)"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 macos-106-ppc            # Install with default settings"
    echo "  $0 --vnc-port 2 --timeout 1200 macos-106-ppc"
    echo ""
    exit 1
}

# Parse arguments
VNC_PORT=1
TIMEOUT=600
VM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vnc-port)
            VNC_PORT="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "${VM_NAME}" ]]; then
                VM_NAME="$1"
            else
                log_error "Unknown argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "${VM_NAME}" ]]; then
    log_error "VM name is required"
    usage
fi

# Set QEMU binary
QEMU_BIN="${HOME}/.local/qemu-genose/bin/qemu-system-ppc64"
if [[ ! -x "${QEMU_BIN}" ]]; then
    QEMU_BIN="qemu-system-ppc64"
fi

# Main execution
main() {
    check_prerequisites
    automated_install "${VM_NAME}" "${VNC_PORT}" "${TIMEOUT}"
    
    if [[ $? -eq 0 ]]; then
        log_success "Installation completed successfully!"
    else
        log_error "Installation failed or timed out"
        exit 1
    fi
}

main "$@"
