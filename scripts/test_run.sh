#!/bin/bash
# Test - Run Tests
# Group: test, Action: run
# This script calls the main vm-manager.sh with the run-tests command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the run-tests command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" run-tests "$@"