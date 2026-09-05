#!/bin/bash
# GDB - Connect to VM
# Group: gdb, Action: connect
# This script calls the main vm-manager.sh debug-connect functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the debug-connect command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" debug-connect "$@"