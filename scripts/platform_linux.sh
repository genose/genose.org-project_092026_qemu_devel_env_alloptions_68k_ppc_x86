#!/bin/bash
# Platform - Launch Linux VM
# Group: platform, Action: linux
# This script calls the main vm-manager.sh with the linux command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the linux command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" linux "$@"