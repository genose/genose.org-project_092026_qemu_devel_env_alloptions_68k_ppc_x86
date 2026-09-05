# VM Manager Scripts Directory

This directory contains modular scripts that are part of the `vm-manager.sh` project, organized following the pattern `scripts/(group)_(action).sh`.

## Structure

```
scripts/
├── common.sh              # Common functions and variables shared by all scripts
├── README.md              # This file
├── build/                # Build QEMU related scripts
│   ├── build_full.sh     # Full build pipeline
│   ├── build_download.sh  # Download QEMU source
│   ├── build_check_deps.sh # Check build dependencies
│   └── ...
├── vm/                   # Virtual Machine management scripts
│   ├── vm_list.sh        # List all VMs
│   ├── vm_create.sh      # Create new VM
│   ├── vm_launch.sh      # Launch VM
│   └── ...
├── debug/                # Debugging related scripts
│   ├── debug_start.sh    # Start debug session
│   └── ...
├── monitor/              # Monitoring scripts
├── export/               # Export/Import scripts
├── platform/             # Platform-specific scripts
├── image/                # Image management scripts
├── disk/                 # Disk management scripts
├── config/               # Configuration management scripts
├── toolchain/            # Toolchain management scripts
├── source/               # Source code management scripts
├── test/                 # Testing framework scripts
├── gui/                  # GUI application scripts
├── deployment/           # Deployment scripts
├── snapshot/             # Snapshot management scripts
├── session/              # Session management scripts
├── breakpoint/           # Breakpoint preset scripts
├── multivm/              # Multi-VM debugging scripts
├── symbols/              # Debug symbol management scripts
├── gdb/                  # GDB configuration scripts
└── spice/                # SPICE advanced features scripts
```

## Script Types

### 1. Wrapper Scripts
Simple scripts that call the main `vm-manager.sh` with specific arguments:

```bash
#!/bin/bash
# Group: vm, Action: list
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${SCRIPT_DIR}/vm-manager.sh" list "$@"
```

### 2. Standalone Scripts
Independent scripts that source `common.sh` and implement functionality directly:

```bash
#!/bin/bash
# Group: build, Action: check_deps
source "${SCRIPT_DIR}/common.sh"

check_build_deps() {
    # Function implementation
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_build_deps
fi
```

## Naming Convention

- **Group**: The functional category (e.g., `build`, `vm`, `debug`)
- **Action**: The specific operation (e.g., `list`, `create`, `start`)
- **Format**: `scripts/(group)_(action).sh`

## Available Commands

Each script can be executed directly:

```bash
# VM Management
./scripts/vm_list.sh           # List all VMs
./scripts/vm_create.sh         # Create new VM
./scripts/vm_launch.sh         # Launch a VM

# Build Management  
./scripts/build_full.sh        # Full build pipeline
./scripts/build_download.sh    # Download QEMU source
./scripts/build_check_deps.sh  # Check build dependencies

# Debug Management
./scripts/debug_start.sh       # Start debug session
```

## Integration with Main Script

The main `vm-manager.sh` script can still be used as before. The individual scripts in this directory provide:

1. **Modular access**: Direct access to specific functionality
2. **Better organization**: Logical grouping of related functions
3. **Easier maintenance**: Smaller, focused scripts instead of one massive file
4. **Selective execution**: Run only the needed components

## Creating New Scripts

1. Identify the group and action
2. Create a new file: `scripts/(group)_(action).sh`
3. Choose the appropriate type (wrapper or standalone)
4. For standalone scripts, source `common.sh` for shared utilities
5. Make the script executable: `chmod +x scripts/(group)_(action).sh`
6. Test the script independently

## Migration Status

- [x] Infrastructure created (common.sh, directory structure)
- [x] Example wrapper scripts (vm_list.sh, vm_create.sh, etc.)
- [x] Example standalone scripts (build_check_deps.sh)
- [ ] Remaining functions to be migrated

This modular approach allows for gradual migration of functionality from the monolithic `vm-manager.sh` to organized, maintainable scripts.