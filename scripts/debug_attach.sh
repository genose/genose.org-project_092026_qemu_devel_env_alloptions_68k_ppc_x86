#!/bin/bash
# Debug - Attach to VM
# Group: debug, Action: attach
# This script calls the main vm-manager.sh with the debug-attach command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the debug-attach command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" debug-attach "$@"