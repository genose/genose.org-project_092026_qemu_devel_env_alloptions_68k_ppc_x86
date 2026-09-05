#!/bin/bash
# Orchestration - Stop All VMs
# Group: orchestration, Action: stop_all
# This script calls the main vm-manager.sh with the stop-all command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If called directly, execute the stop-all command from main script
exec "${SCRIPT_DIR}/../vm-manager.sh" stop-all "$@"