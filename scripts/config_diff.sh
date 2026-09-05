#!/bin/bash
# Configuration - Show Configuration Diff
# Group: config, Action: diff
# This script calls the main vm-manager.sh with the config-diff command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the config-diff command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" config-diff "$@"