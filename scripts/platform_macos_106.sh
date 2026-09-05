#!/bin/bash
# Platform - Launch MacOS 10.6 PPC VM
# Group: platform, Action: macos_106
# This script calls the main vm-manager.sh with the macos-106 command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# If called directly, execute the macos-106 command from main script
exec "${SCRIPT_DIR}/vm-manager.sh" macos-106 "$@"