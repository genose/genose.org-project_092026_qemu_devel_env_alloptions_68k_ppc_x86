#!/bin/bash
# Import - Import VM
# Group: import, Action: vm
# This script calls the main vm-manager.sh with the import command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the import command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" import "$@"