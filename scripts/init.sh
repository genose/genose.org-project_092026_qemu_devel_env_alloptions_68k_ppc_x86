#!/bin/bash
# System - Initialize VM Manager
# Group: system, Action: init
# This script calls the main vm-manager.sh with the init command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the init command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" init "$@"
