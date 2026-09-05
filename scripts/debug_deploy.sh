#!/bin/bash
# Debug - Deploy Binary
# Group: debug, Action: deploy
# This script calls the main vm-manager.sh with the deploy command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the deploy command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" deploy "$@"