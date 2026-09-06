#!/bin/bash
# Build QEMU - Compile QEMU
# Group: build, Action: compile
# This script calls the main vm-manager.sh with the build-compile command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the build-compile command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" build-compile "$@"
