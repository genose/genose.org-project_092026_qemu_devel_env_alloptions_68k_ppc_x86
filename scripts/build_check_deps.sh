#!/bin/bash
# Build QEMU - Check Dependencies
# Part of vm-manager.sh - Split into modular scripts
# Group: build, Action: check_deps

set -euo pipefail

# Load common functions and variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

check_build_deps() {
    local missing=()
    local deps=(git curl tar make ninja pkg-config python3 gcc g++ flex bison)
    for d in "${deps[@]}"; do
        command -v "$d" &>/dev/null || missing+=("$d")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing build dependencies: ${missing[*]}"
        case "$(uname -s)" in
            Linux)
                warn "On Debian/Ubuntu: sudo apt-get install build-essential git ninja-build pkg-config python3-pip libglib2.0-dev libpixman-1-dev libsdl2-dev libgtk-3-dev libvte-2.91-dev libslirp-dev libbz2-dev liblzo2-dev libsnappy-dev libssh-dev libusbredirhost-dev libcacard-dev libepoxy-dev libncurses-dev libspice-server-dev libspice-protocol-dev"
                ;;
            Darwin)
                warn "On macOS: brew install ninja pkg-config glib pixman sdl2 gtk+3 libslirp spice-protocol spice-gtk"
                ;;
            *)
                warn "On Fedora/RHEL: sudo dnf install @development-tools ninja-build glib2-devel pixman-devel SDL2-devel gtk3-devel slirp-devel bzip2-devel lzo-devel snappy-devel libssh-devel usbredir-devel openssl-devel spice-protocol spice-server-devol"
                ;;
        esac
        die "Install the missing dependencies before continuing."
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    heading "Checking Build Dependencies"
    check_build_deps
    log "All build dependencies are satisfied!"
fi