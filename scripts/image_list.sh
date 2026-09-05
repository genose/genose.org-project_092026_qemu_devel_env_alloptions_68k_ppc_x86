#!/bin/bash
# Image Management - List Images
# Group: image, Action: list
# This script calls the main vm-manager.sh with the image-list command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If called directly, execute the image-list command from main script
exec "${SCRIPT_DIR}/../vm-manager.sh" image-list "$@"