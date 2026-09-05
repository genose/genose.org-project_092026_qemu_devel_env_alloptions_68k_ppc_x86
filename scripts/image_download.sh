#!/bin/bash
# Image Management - Download Image
# Group: image, Action: download
# This script calls the main vm-manager.sh with the download-iso command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If called directly, execute the download-iso command from main script
exec "${SCRIPT_DIR}/../vm-manager.sh" download-iso "$@"