#!/bin/bash
# Export - Export to QCOW2
# Group: export, Action: qcow2
# This script calls the main vm-manager.sh with the export-qcow2 command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the export-qcow2 command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" export-qcow2 "$@"