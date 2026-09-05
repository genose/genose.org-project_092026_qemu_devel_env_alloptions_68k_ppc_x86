#!/bin/bash
# Information - Show QEMU Version
# Group: info, Action: qemu_version
# This script calls the main vm-manager.sh with the qemu-version command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If called directly, execute the qemu-version command from main script
exec "${SCRIPT_DIR}/../vm-manager.sh" qemu-version "$@"