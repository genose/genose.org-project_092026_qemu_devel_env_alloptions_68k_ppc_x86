#!/bin/bash
# GUI Scripts Menu - XDialog-based menu for scripts directory
# Group: gui, Action: scripts_menu
# Simple and working XDialog menu for modular scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we can use XDialog
use_xdialog() {
    [[ -n "${DISPLAY:-}" ]] && command -v xdialog &>/dev/null
}

# Main menu
if use_xdialog; then
    # Build menu items - simple static list of key scripts
    choice=$(xdialog \
        --backtitle "VM Manager" \
        --title "Scripts Menu" \
        --menu "Select a script to execute:" \
        20 70 15 \
        1 "VM List" \
        2 "VM Create" \
        3 "VM Launch" \
        4 "Build Check Deps" \
        5 "Config Backup" \
        6 "Debug Start" \
        7 "Platform Linux" \
        8 "Monitor All" \
        9 "Test Run" \
        10 "Export QCOW2" \
        0 "Back to Main Menu" \
        Q "Quit" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1) exec bash "${SCRIPT_DIR}/vm_list.sh" "$@" ;;
        2) exec bash "${SCRIPT_DIR}/vm_create.sh" "$@" ;;
        3) exec bash "${SCRIPT_DIR}/vm_launch.sh" "$@" ;;
        4) exec bash "${SCRIPT_DIR}/build_check_deps.sh" "$@" ;;
        5) exec bash "${SCRIPT_DIR}/config_backup.sh" "$@" ;;
        6) exec bash "${SCRIPT_DIR}/debug_start.sh" "$@" ;;
        7) exec bash "${SCRIPT_DIR}/platform_linux.sh" "$@" ;;
        8) exec bash "${SCRIPT_DIR}/monitor_all.sh" "$@" ;;
        9) exec bash "${SCRIPT_DIR}/test_run.sh" "$@" ;;
        10) exec bash "${SCRIPT_DIR}/export_qcow2.sh" "$@" ;;
        0|Q) exit 0 ;;
    esac
else
    # Simple CLI menu
    echo "Available Scripts (XDialog not available):"
    echo "1) vm_list.sh"
    echo "2) vm_create.sh"
    echo "3) vm_launch.sh"
    echo "4) build_check_deps.sh"
    echo "5) config_backup.sh"
    echo "6) debug_start.sh"
    echo "7) platform_linux.sh"
    echo "8) monitor_all.sh"
    echo "9) test_run.sh"
    echo "10) export_qcow2.sh"
    echo "0) Quit"
    echo ""
    
    read -rp "Select script: " choice
    
    case "$choice" in
        1) exec bash "${SCRIPT_DIR}/vm_list.sh" "$@" ;;
        2) exec bash "${SCRIPT_DIR}/vm_create.sh" "$@" ;;
        3) exec bash "${SCRIPT_DIR}/vm_launch.sh" "$@" ;;
        4) exec bash "${SCRIPT_DIR}/build_check_deps.sh" "$@" ;;
        5) exec bash "${SCRIPT_DIR}/config_backup.sh" "$@" ;;
        6) exec bash "${SCRIPT_DIR}/debug_start.sh" "$@" ;;
        7) exec bash "${SCRIPT_DIR}/platform_linux.sh" "$@" ;;
        8) exec bash "${SCRIPT_DIR}/monitor_all.sh" "$@" ;;
        9) exec bash "${SCRIPT_DIR}/test_run.sh" "$@" ;;
        10) exec bash "${SCRIPT_DIR}/export_qcow2.sh" "$@" ;;
        0|Q|q) exit 0 ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi