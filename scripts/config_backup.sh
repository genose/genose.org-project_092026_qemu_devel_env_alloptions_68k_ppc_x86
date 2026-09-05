#!/bin/bash
# Configuration - Backup Configuration
# Group: config, Action: backup
# This script calls the main vm-manager.sh with the config-backup command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the config-backup command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" config-backup "$@"