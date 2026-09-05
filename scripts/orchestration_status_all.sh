#!/bin/bash
# Orchestration - Status of All VMs
# Group: orchestration, Action: status_all
# This script calls the main vm-manager.sh with the status-all command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If called directly, execute the status-all command from main script
exec "${SCRIPT_DIR}/../vm-manager.sh" status-all "$@"