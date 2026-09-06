#!/bin/bash
# VM Management - Create VM from Template
# Group: vm, Action: create_template
# This script calls the main vm-manager.sh with the create-template command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the create-template command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" create-template "$@"
