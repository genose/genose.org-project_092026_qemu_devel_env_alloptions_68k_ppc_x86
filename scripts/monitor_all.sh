#!/bin/bash
# Monitor - Monitor All VMs
# Group: monitor, Action: all
# This script calls the main vm-manager.sh with the monitor command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the monitor command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" monitor "$@"