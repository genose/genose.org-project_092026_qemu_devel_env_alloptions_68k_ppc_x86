#!/bin/bash
# Configuration - List All Config Backups
# Group: config, Action: list_backups
# This script calls the main vm-manager.sh with the list-backups command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the list-backups command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" list-backups "$@"