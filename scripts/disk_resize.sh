#!/bin/bash
# Disk Management - Resize Disk Image
# Group: disk, Action: resize
# This script calls the main vm-manager.sh with the disk-resize command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If called directly, execute the disk-resize command from main script
exec "${SCRIPT_DIR}/../vm-manager.sh" disk-resize "$@"