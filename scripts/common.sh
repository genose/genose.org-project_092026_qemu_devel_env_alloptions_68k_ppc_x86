#!/bin/bash
# Common functions and variables for vm-manager scripts
# This file contains shared utilities used by all scripts

# Set strict mode
set -euo pipefail

# Initialize variables with defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Default configuration
QEMU_PREFIX="${QEMU_PREFIX:-${HOME}/.local/qemu-retro}"
QEMU_BIN_DIR="${QEMU_BIN_DIR:-${QEMU_PREFIX}/bin}"
QEMU_SRC_DIR="${QEMU_SRC_DIR:-${SCRIPT_DIR}/qemu-9.2.0}"
QEMU_BUILD_DIR="${QEMU_BUILD_DIR:-${QEMU_SRC_DIR}/build}"
QEMU_VERSION="${QEMU_VERSION:-9.2.0}"

VM_DIR="${VM_DIR:-${HOME}/vm_assistant/vms}"
VM_IMAGE_DIR="${VM_IMAGE_DIR:-${HOME}/vm_assistant/images}"
VM_SHARED_DIR="${VM_SHARED_DIR:-${HOME}/vm_assistant/shares}"
VM_LOG_DIR="${VM_LOG_DIR:-${HOME}/vm_assistant/logs}"
CONFIG_DIR="${CONFIG_DIR:-${HOME}/vm_assistant}"
PATCHES_DIR="${PATCHES_DIR:-${SCRIPT_DIR}/patches}"

DEFAULT_QEMU_GDB_PORT=1234
DEFAULT_DISPLAY="${DEFAULT_DISPLAY:-cocoa}"

# Color codes for output
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_PURPLE='\033[0;35m'
C_CYAN='\033[0;36m'
C_RESET='\033[0m'

# Common functions
log() {
    echo -e "${C_GREEN}[${SCRIPT_NAME}]${C_RESET} $*"
}

warn() {
    echo -e "${C_YELLOW}[${SCRIPT_NAME}] WARNING:${C_RESET} $*" >&2
}

die() {
    echo -e "${C_RED}[${SCRIPT_NAME}] ERROR:${C_RESET} $*" >&2
    exit 1
}

heading() {
    echo ""
    echo -e "${C_BLUE}=== $* ===${C_RESET}"
}

# Check if running in interactive mode
is_interactive() {
    [[ $- == *i* ]] && return 0 || return 1
}

# Simple ask function for user input
ask() {
    local prompt="$1"
    local default="$2"
    if [[ -n "$default" ]]; then
        read -rp "$prompt [$default]: " input
        echo "${input:-$default}"
    else
        read -rp "$prompt: " input
        echo "$input"
    fi
}

trim() {
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"           # remove leading whitespace
    str="${str%"${str##*[![:space:]]]}"}"          # remove trailing whitespace
    echo "$str"
}

# Ensure directories exist
ensure_dirs() {
    for dir in "$@"; do
        [[ -d "$dir" ]] || mkdir -p "$dir"
    done
}

# Export common variables and functions for use by other scripts
export SCRIPT_DIR SCRIPT_NAME QEMU_PREFIX QEMU_BIN_DIR QEMU_SRC_DIR QEMU_BUILD_DIR QEMU_VERSION
export VM_DIR VM_IMAGE_DIR VM_SHARED_DIR VM_LOG_DIR CONFIG_DIR PATCHES_DIR
export DEFAULT_QEMU_GDB_PORT DEFAULT_DISPLAY

export C_RED C_GREEN C_YELLOW C_BLUE C_PURPLE C_CYAN C_RESET

export -f log warn die heading is_interactive ask trim ensure_dirs