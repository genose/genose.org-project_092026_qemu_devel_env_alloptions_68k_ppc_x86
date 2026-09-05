#!/bin/bash
# Platform - Launch MacOS PPC VM
# Group: platform, Action: macos_ppc
# This script calls the main vm-manager.sh with the macos-ppc command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the macos-ppc command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" macos-ppc "$@"