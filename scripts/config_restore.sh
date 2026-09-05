#!/bin/bash
# Configuration - Restore Configuration
# Group: config, Action: restore
# This script calls the main vm-manager.sh with the config-restore command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the config-restore command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" config-restore "$@"