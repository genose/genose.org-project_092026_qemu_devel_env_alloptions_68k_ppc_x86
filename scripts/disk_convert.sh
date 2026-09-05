#!/bin/bash
# Disk Management - Convert Disk Image
# Group: disk, Action: convert
# This script calls the main vm-manager.sh with the disk-convert command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If called directly, execute the disk-convert command from main script
exec "${SCRIPT_DIR}/../vm-manager.sh" disk-convert "$@"