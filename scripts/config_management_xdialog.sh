#!/bin/bash
# Configuration Management - XDialog GUI for configuration operations
# Group: config, Action: management_xdialog
# XDialog-based GUI for comprehensive configuration management including backup, restore, history, diff

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/../vm-manager.sh"

# Check for XDialog and DISPLAY
if ! command -v xdialog &>/dev/null || [[ -z "${DISPLAY:-}" ]]; then
    echo "XDialog not available or DISPLAY not set, falling back to CLI"
    exec "${SCRIPT_DIR}/config_backup.sh" "$@"
fi

# Function to show main configuration management menu
config_management_menu() {
    local choice
    
    choice=$(xdialog \
        --backtitle "VM Manager - Configuration Management" \
        --title "Configuration Management Menu" \
        --menu "Select configuration operation:" \
        20 70 15 \
        1 "Create configuration backup" \
        2 "Restore from backup" \
        3 "List all backups" \
        4 "Show configuration history" \
        5 "Compare configuration versions (diff)" \
        6 "Commit configuration changes" \
        7 "View current configuration" \
        0 "Back to Main Menu" \
        Q "Quit" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1) create_backup_with_xdialog ;;
        2) restore_backup_with_xdialog ;;
        3) list_backups_with_xdialog ;;
        4) show_history_with_xdialog ;;
        5) diff_config_with_xdialog ;;
        6) commit_config_with_xdialog ;;
        7) view_config_with_xdialog ;;
        0|Q) return 0 ;;
        *) xdialog --msgbox "Invalid selection" 5 30 ;;
    esac
}

# Create configuration backup with XDialog
create_backup_with_xdialog() {
    local backup_name backup_description
    
    backup_name=$(xdialog \
        --backtitle "VM Manager - Create Backup" \
        --title "Backup Name" \
        --inputbox "Enter name for this backup:" \
        10 40 \
        3>&1 1>&2 2>&3)
    
    if [[ -z "$backup_name" ]]; then
        return
    fi
    
    backup_description=$(xdialog \
        --backtitle "VM Manager - Create Backup" \
        --title "Backup Description" \
        --inputbox "Enter description for this backup (optional):" \
        10 40 \
        3>&1 1>&2 2>&3)
    
    xdialog --msgbox "Creating backup: ${backup_name}" 5 40
    exec "${SCRIPT_DIR}/config_backup.sh" "$backup_name"
}

# Restore from backup with XDialog
restore_backup_with_xdialog() {
    local backup_file
    
    backup_file=$(xdialog \
        --backtitle "VM Manager - Restore Backup" \
        --title "Select Backup File" \
        --fselect "${HOME}/vm_assistant/backups/" \
        20 70 \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$backup_file" ]]; then
        # Confirm restoration
        xdialog \
            --yesno "Are you sure you want to restore from: ${backup_file}? This will overwrite current configuration." \
            10 60
        
        if [[ $? -eq 0 ]]; then
            exec "${SCRIPT_DIR}/config_restore.sh" "$backup_file"
        fi
    fi
}

# List all backups with XDialog
list_backups_with_xdialog() {
    local backup_list
    backup_list=$(${SCRIPT_DIR}/config_list_backups.sh 2>/dev/null || echo "No backups found")
    
    xdialog \
        --backtitle "VM Manager - Backup List" \
        --title "Available Backups" \
        --textbox "$backup_list" \
        20 80
}

# Show configuration history with XDialog
show_history_with_xdialog() {
    local history_content
    history_content=$(${SCRIPT_DIR}/config_history.sh 2>/dev/null || echo "No history found")
    
    xdialog \
        --backtitle "VM Manager - Configuration History" \
        --title "Configuration History" \
        --textbox "$history_content" \
        20 80
}

# Compare configuration versions with XDialog
diff_config_with_xdialog() {
    local old_config new_config
    
    old_config=$(xdialog \
        --backtitle "VM Manager - Compare Configurations" \
        --title "Select First Configuration" \
        --fselect "${HOME}/vm_assistant/backups/" \
        20 70 \
        3>&1 1>&2 2>&3)
    
    if [[ -z "$old_config" ]]; then
        return
    fi
    
    new_config=$(xdialog \
        --backtitle "VM Manager - Compare Configurations" \
        --title "Select Second Configuration" \
        --fselect "${HOME}/vm_assistant/backups/" \
        20 70 \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$new_config" ]]; then
        local diff_output
        diff_output=$(diff "$old_config" "$new_config" 2>/dev/null || echo "No differences found or files not comparable")
        
        xdialog \
            --backtitle "VM Manager - Configuration Diff" \
            --title "Differences between configurations" \
            --textbox "$diff_output" \
            20 80
    fi
}

# Commit configuration changes with XDialog
commit_config_with_xdialog() {
    local commit_message
    
    commit_message=$(xdialog \
        --backtitle "VM Manager - Commit Configuration" \
        --title "Commit Message" \
        --inputbox "Enter commit message for configuration changes:" \
        10 40 \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$commit_message" ]]; then
        exec "${SCRIPT_DIR}/config_commit.sh" "$commit_message"
    fi
}

# View current configuration with XDialog
view_config_with_xdialog() {
    local config_file
    
    config_file=$(xdialog \
        --backtitle "VM Manager - View Configuration" \
        --title "Select Configuration File" \
        --fselect "${HOME}/vm_assistant/vms/" \
        20 70 \
        3>&1 1>&2 2>&3)
    
    if [[ -n "$config_file" ]]; then
        local config_content
        config_content=$(cat "$config_file" 2>/dev/null || echo "File not found or not readable")
        
        xdialog \
            --backtitle "VM Manager - View Configuration" \
            --title "Configuration: $(basename "$config_file")" \
            --textbox "$config_content" \
            20 80
    fi
}

# Main entry point
main() {
    config_management_menu
}

main "$@"