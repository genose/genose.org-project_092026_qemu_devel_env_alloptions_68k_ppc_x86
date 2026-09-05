#!/bin/bash
# Build QEMU - Full Pipeline
# Group: build, Action: full
# This script calls the main vm-manager.sh with the build command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the build command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" build "$@"