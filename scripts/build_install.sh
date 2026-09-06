#!/bin/bash
# Build QEMU - Install QEMU
# Group: build, Action: install
# This script calls the main vm-manager.sh with the build-install command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the build-install command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" build-install "$@"
