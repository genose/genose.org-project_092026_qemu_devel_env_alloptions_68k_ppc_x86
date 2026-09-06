#!/bin/bash
# Image Management - Insert Image
# Group: image, Action: insert
# This script calls the main vm-manager.sh with the image-insert command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the image-insert command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" image-insert "$@"
