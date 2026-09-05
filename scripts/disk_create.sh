#!/bin/bash
# Disk Management - Create Disk Image
# Group: disk, Action: create
# This script calls the main vm-manager.sh with the disk-create command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If called directly, execute the disk-create command from main script
exec "${SCRIPT_DIR}/../vm-manager.sh" disk-create "$@"