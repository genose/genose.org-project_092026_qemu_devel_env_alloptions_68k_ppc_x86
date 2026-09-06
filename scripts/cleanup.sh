#!/bin/bash
# System - Cleanup Resources
# Group: system, Action: cleanup
# This script calls the main vm-manager.sh with the cleanup command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the cleanup command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" cleanup "$@"
