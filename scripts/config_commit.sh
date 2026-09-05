#!/bin/bash
# Configuration - Commit Configuration
# Group: config, Action: commit
# This script calls the main vm-manager.sh with the config-commit command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the config-commit command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" config-commit "$@"