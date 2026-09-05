#!/bin/bash
# Configuration - Show Configuration History
# Group: config, Action: history
# This script calls the main vm-manager.sh with the config-history command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the config-history command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" config-history "$@"