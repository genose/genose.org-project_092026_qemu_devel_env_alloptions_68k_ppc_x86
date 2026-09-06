#!/bin/bash
# VM Management - Snapshot Operations
# Group: vm, Action: snapshot
# This script calls the main vm-manager.sh with the snapshot command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the snapshot command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" snapshot "$@"
