#!/bin/bash
# Orchestration - Start All VMs
# Group: orchestration, Action: start_all
# This script calls the main vm-manager.sh with the start-all command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If called directly, execute the start-all command from main script
exec "${SCRIPT_DIR}/../vm-manager.sh" start-all "$@"