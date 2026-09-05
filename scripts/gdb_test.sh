#!/bin/bash
# GDB - Test GDB Connection
# Group: gdb, Action: test
# This script calls the main vm-manager.sh test-gdb command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the test-gdb command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" test-gdb "$@"