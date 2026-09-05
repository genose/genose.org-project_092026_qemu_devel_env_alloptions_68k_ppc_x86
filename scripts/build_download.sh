#!/bin/bash
# Build QEMU - Download Source
# Group: build, Action: download
# This script calls the main vm-manager.sh with the download command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the download command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" build-download "$@"