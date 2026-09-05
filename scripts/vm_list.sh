#!/bin/bash
# VM Management - List VMs
# Group: vm, Action: list
# This script calls the main vm-manager.sh with the list command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the list command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" list "$@"