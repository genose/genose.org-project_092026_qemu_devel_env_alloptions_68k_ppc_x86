#!/bin/bash
# =============================================================================
# ISO/DMG File Discovery with User Approval
# 
# This script discovers ISO and DMG files in a directory and lets the user
# select which one to use, ensuring no file discovery happens without approval.
# 
# Features:
# - Recursively search directories for ISO/DMG files
# - Display found files with sizes and paths
# - User selects which file to use
# - Validate file integrity (optional)
# =============================================================================

set -euo pipefail

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

# Check if a directory is allowed for scanning
# This implements the user's requirement: "ISO/DMG or file discovery is not allowed
# without user approbation of which directory to start with"
check_directory_approval() {
    local dir="$1"
    
    # Check if directory is in the allowed list (vm_assistant directories)
    local allowed_dirs=(
        "${HOME}/vm_assistant"
        "${HOME}/vm_assistant/images"
        "${HOME}/vm_assistant/roms"
        "${HOME}/Documents"
        "${HOME}/Downloads"
    )
    
    for allowed in "${allowed_dirs[@]}"; do
        if [[ "${dir}" == "${allowed}"* ]]; then
            return 0  # Allowed
        fi
    done
    
    # For other directories, ask for explicit approval
    echo ""
    log_warn "Directory '${dir}' is not in the default allowed list."
    log_info "Allowed directories:"
    for allowed in "${allowed_dirs[@]}"; do
        echo "  - ${allowed}"
    done
    echo ""
    
    read -rp "Do you want to scan '${dir}' for ISO/DMG files? (yes/no): " choice
    case "${choice}" in
        yes|Yes|YES|y|Y)
            return 0
            ;;
        *)
            log_info "Scan cancelled for '${dir}'"
            return 1
            ;;
    esac
}

# Discover ISO and DMG files in a directory
discover_iso_dmg_files() {
    local search_dir="$1"
    local max_depth="${2:-3}"
    local output_file="${3:-/tmp/iso_dmg_list.txt}"
    
    > "${output_file}"
    
    if ! check_directory_approval "${search_dir}"; then
        return 1
    fi
    
    log_info "Scanning for ISO/DMG files in: ${search_dir}"
    
    # Find ISO files
    while IFS= read -r -d $'\0' iso_file; do
        if [[ -f "${iso_file}" ]]; then
            local size
            size=$(du -h "${iso_file}" | cut -f1)
            local mtime
            mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${iso_file}" 2>/dev/null || stat -c "%y" "${iso_file}" 2>/dev/null | cut -d'.' -f1)
            echo "ISO:${iso_file}:${size}:${mtime}" >> "${output_file}"
        fi
    done < <(find "${search_dir}" -maxdepth "${max_depth}" -type f \( -iname "*.iso" -o -iname "*.ISO" \) -print0 2>/dev/null)
    
    # Find DMG files
    while IFS= read -r -d $'\0' dmg_file; do
        if [[ -f "${dmg_file}" ]]; then
            local size
            size=$(du -h "${dmg_file}" | cut -f1)
            local mtime
            mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${dmg_file}" 2>/dev/null || stat -c "%y" "${dmg_file}" 2>/dev/null | cut -d'.' -f1)
            echo "DMG:${dmg_file}:${size}:${mtime}" >> "${output_file}"
        fi
    done < <(find "${search_dir}" -maxdepth "${max_depth}" -type f \( -iname "*.dmg" -o -iname "*.DMG" \) -print0 2>/dev/null)
    
    return 0
}

# Display found files and let user select
display_and_select() {
    local list_file="$1"
    local title="$2"
    local default_dir="$3"
    
    if [[ ! -s "${list_file}" ]]; then
        log_info "No ISO/DMG files found in the scanned directories."
        return 1
    fi
    
    log_success "Found ISO/DMG files:"
    echo ""
    
    # Count files
    local count=0
    while IFS= read -r line; do
        if [[ -n "${line}" ]]; then
            count=$((count + 1))
        fi
    done < "${list_file}"
    
    echo "Total: ${count} files found"
    echo ""
    
    # Display files in a nice format
    local i=1
    local file_list=()
    
    while IFS=: read -r type file size mtime; do
        if [[ -n "${file}" && -n "${size}" ]]; then
            file_list+=("${file}")
            
            # Color based on type
            local color="${CYAN}"
            if [[ "${type}" == "ISO" ]]; then
                color="${GREEN}"
            elif [[ "${type}" == "DMG" ]]; then
                color="${YELLOW}"
            fi
            
            printf "  ${color}%2d. [%s] %s (%s) - %s${NC}\n" \
                "${i}" "${type}" "$(basename "${file}")" "${size}" "${mtime}"
            
            i=$((i + 1))
        fi
    done < "${list_file}"
    
    echo ""
    
    # Let user select
    if [[ ${#file_list[@]} -eq 1 ]]; then
        # Only one file found, use it automatically
        echo "Only one file found, using: ${file_list[0]}"
        echo "${file_list[0]}"
        return 0
    fi
    
    # Multiple files, let user select
    read -rp "Select a file (1-${#file_list[@]}), or 'q' to quit: " choice
    
    case "${choice}" in
        q|Q)
            log_info "Selection cancelled"
            return 1
            ;;
        [0-9]*)
            local index=$((choice - 1))
            if [[ ${index} -ge 0 && ${index} -lt ${#file_list[@]} ]]; then
                echo "${file_list[${index}]}"
                return 0
            else
                log_error "Invalid selection"
                return 1
            fi
            ;;
        *)
            log_error "Invalid input"
            return 1
            ;;
    esac
}

# Validate ISO/DMG file integrity
validate_file() {
    local file="$1"
    
    if [[ ! -f "${file}" ]]; then
        log_error "File not found: ${file}"
        return 1
    fi
    
    # Check file size (minimum 10MB for valid ISO/DMG)
    local size_bytes
    size_bytes=$(stat -f "%z" "${file}" 2>/dev/null || stat -c "%s" "${file}" 2>/dev/null)
    
    if [[ "${size_bytes}" -lt 10485760 ]]; then  # 10MB
        log_warn "File is very small (${size_bytes} bytes), might be corrupted"
    fi
    
    # For ISO files, check if it's a valid ISO
    if [[ "${file}" == *.iso || "${file}" == *.ISO ]]; then
        # Check ISO header (first 5 bytes should be CD001)
        if command -v file &>/dev/null; then
            local file_type
            file_type=$(file -b "${file}" 2>/dev/null)
            log_info "File type: ${file_type}"
        fi
    fi
    
    return 0
}

# Interactive directory selection
select_directory() {
    local default_dir="${1:-${HOME}/vm_assistant/images}"
    
    echo ""
    log_info "ISO/DMG File Discovery"
    log_info "===================="
    echo ""
    log_info "This will scan directories for ISO and DMG files."
    log_info "You must approve each directory before it's scanned."
    echo ""
    
    read -rp "Enter directory to scan [${default_dir}]: " search_dir
    
    if [[ -z "${search_dir}" ]]; then
        search_dir="${default_dir}"
    fi
    
    # Expand tilde
    search_dir="${search_dir/#~/${HOME}}"
    
    # Validate directory
    if [[ ! -d "${search_dir}" ]]; then
        log_error "Directory does not exist: ${search_dir}"
        return 1
    fi
    
    echo "${search_dir}"
    return 0
}

# Main function
main() {
    local default_dir="${HOME}/vm_assistant/images"
    local temp_list="/tmp/iso_dmg_list_$(date +%s).txt"
    
    # Get directory from user
    local search_dir
    if ! search_dir=$(select_directory "${default_dir}"); then
        exit 1
    fi
    
    # Discover files
    if ! discover_iso_dmg_files "${search_dir}" 4 "${temp_list}"; then
        log_error "Discovery failed or cancelled"
        exit 1
    fi
    
    # Display and select
    local selected_file
    if ! selected_file=$(display_and_select "${temp_list}" "Select ISO/DMG File" "${search_dir}"); then
        log_info "No file selected"
        rm -f "${temp_list}"
        exit 1
    fi
    
    # Validate
    if ! validate_file "${selected_file}"; then
        log_error "File validation failed"
        rm -f "${temp_list}"
        exit 1
    fi
    
    # Clean up
    rm -f "${temp_list}"
    
    # Output the selected file
    echo "${selected_file}"
    log_success "Selected: ${selected_file}"
}

# Standalone execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
