#!/bin/bash
# Debug - Test Debug Connection
# Group: debug, Action: test
# This script calls the main vm-manager.sh with the debug-test command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the debug-test command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" debug-test "$@"