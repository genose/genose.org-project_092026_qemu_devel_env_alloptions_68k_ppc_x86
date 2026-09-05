#!/bin/bash
# Debug - Start Debug Session
# Group: debug, Action: start
# This script calls the main vm-manager.sh with the debug command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the debug command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" debug "$@"