#!/bin/bash
# VM Management - Delete VM
# Group: vm, Action: delete
# This script calls the main vm-manager.sh with the delete command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the delete command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" delete "$@"