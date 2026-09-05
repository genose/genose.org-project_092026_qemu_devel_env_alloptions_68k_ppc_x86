#!/bin/bash
# Script Generator - Create wrapper scripts automatically
# This tool helps generate the wrapper scripts for the vm-manager.sh functions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/../vm-manager.sh"

# Function to create a wrapper script
create_wrapper() {
    local group="$1"
    local action="$2"
    local command="$3"
    local description="$4"
    
    local filename="${SCRIPT_DIR}/${group}_${action}.sh"
    
    cat > "$filename" << EOF
#!/bin/bash
# ${description}
# Group: ${group}, Action: ${action}
# This script calls the main vm-manager.sh with the ${command} command

set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the ${command} command from main script
exec "\${SCRIPT_DIR}/vm-manager.sh" ${command} "\$@"
EOF
    
    chmod +x "$filename"
    echo "Created: $filename"
}

# Function to create a standalone script
create_standalone() {
    local group="$1"
    local action="$2"
    local function_name="$3"
    local description="$4"
    
    local filename="${SCRIPT_DIR}/${group}_${action}.sh"
    
    cat > "$filename" << EOF
#!/bin/bash
# ${description}
# Group: ${group}, Action: ${action}
# This script implements ${function_name} functionality independently

set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
source "\${SCRIPT_DIR}/common.sh"

# TODO: Extract ${function_name} function from main script and implement here
# For now, call the main script as fallback
if [[ "\${BASH_SOURCE[0]}" == "\${0}" ]]; then
    exec "\${SCRIPT_DIR}/../vm-manager.sh" ${function_name} "\$@"
fi
EOF
    
    chmod +x "$filename"
    echo "Created (stub): $filename"
}

# Function to extract and list available commands from main script
extract_commands() {
    echo "Available CLI commands from main script:"
    grep -E "^[[:space:]]+[a-z-]+\).*Show" "$MAIN_SCRIPT" | sed 's/.*\([a-z-]*\).*/\1/' | sort | uniq
    echo ""
    echo "Available function names:"
    grep "^[a-z_].*().*{" "$MAIN_SCRIPT" | sed 's/().*//' | sort | uniq | head -20
    echo "... (truncated, total: $(grep -c '^[a-z_].*().*{' "$MAIN_SCRIPT")) functions)"
}

# Main execution
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --wrapper GROUP ACTION COMMAND DESCRIPTION  Create a wrapper script"
    echo "  --standalone GROUP ACTION FUNCTION DESCRIPTION  Create a standalone script stub"
    echo "  --extract                                List available commands and functions"
    echo "  --help                                  Show this help"
}

case "${1:---help}" in
    --wrapper)
        if [[ $# -lt 5 ]]; then
            echo "Error: --wrapper requires GROUP ACTION COMMAND DESCRIPTION"
            usage
            exit 1
        fi
        create_wrapper "$2" "$3" "$4" "$5"
        ;;
    --standalone)
        if [[ $# -lt 5 ]]; then
            echo "Error: --standalone requires GROUP ACTION FUNCTION DESCRIPTION"
            usage
            exit 1
        fi
        create_standalone "$2" "$3" "$4" "$5"
        ;;
    --extract)
        extract_commands
        ;;
    --help|-h|help)
        usage
        ;;
    *)
        echo "Error: Unknown option: $1"
        usage
        exit 1
        ;;
esac