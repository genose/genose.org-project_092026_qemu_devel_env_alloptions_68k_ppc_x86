#!/bin/bash
# VM Management - Create VM with XDialog GUI
# Group: vm, Action: create_gui
# This script provides an XDialog-based GUI for creating VMs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/../vm-manager.sh"

# Check for XDialog
if ! command -v xdialog &>/dev/null || [[ -z "${DISPLAY:-}" ]]; then
    echo "XDialog not available or DISPLAY not set, falling back to CLI"
    exec "${SCRIPT_DIR}/vm_create.sh" "$@"
fi

# Use XDialog to create VM
xdialog \
    --title "Create New VM" \
    --msgbox "XDialog VM Creation GUI\n\nThis would launch the XDialog-based VM creation interface.\n\nFor now, falling back to CLI mode." \
    10 60

echo "Falling back to CLI mode..."
exec "${SCRIPT_DIR}/vm_create.sh" "$@"