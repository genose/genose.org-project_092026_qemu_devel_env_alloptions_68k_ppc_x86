#!/bin/bash
# VM Management - Clone VM
# Group: vm, Action: clone
# This script calls the main vm-manager.sh with the clone command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the clone command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" clone "$@"