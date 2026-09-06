#!/bin/bash
# Image Management - Eject Image
# Group: image, Action: eject
# This script calls the main vm-manager.sh with the image-eject command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the image-eject command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" image-eject "$@"
