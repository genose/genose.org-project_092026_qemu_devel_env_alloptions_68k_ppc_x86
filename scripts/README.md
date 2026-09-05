# VM Manager Scripts Directory

This directory contains modular scripts for the `vm-manager.sh` project, organized following the pattern `scripts/(group)_(action).sh`.

## 🚀 Current Status: 45 Scripts

## 📁 Script Groups

### Build (4): QEMU compilation and setup
- `build_check_deps.sh` - Check build dependencies (standalone)
- `build_download.sh` - Download QEMU source
- `build_full.sh` - Full build pipeline  
- `build_step_by_step.sh` - Interactive build steps

### VM (8): Virtual machine management
- `vm_list.sh` - List all VMs
- `vm_create.sh` - Create new VM
- `vm_launch.sh` - Launch VM
- `vm_delete.sh` - Delete VM
- `vm_clone.sh` - Clone existing VM
- `vm_create_gui.sh` - GUI create (XDialog example)
- `vm_create_xdialog.sh` - Comprehensive XDialog creation

### Config (6): Configuration management
- `config_backup.sh` - Backup configurations
- `config_restore.sh` - Restore configurations
- `config_history.sh` - Show configuration history
- `config_diff.sh` - Show configuration differences
- `config_commit.sh` - Commit configuration changes
- `config_list_backups.sh` - List all configuration backups

### Debug (9): Debugging operations
- `debug_start.sh` - Start debug session
- `debug_connect.sh` - Connect GDB to VM
- `debug_test.sh` - Test debug connection
- `debug_attach.sh` - Attach to running debug session
- `debug_deploy.sh` - Deploy binary to VM
- `gdb_connect.sh` - Connect GDB to VM
- `gdb_test.sh` - Test GDB connection
- `debug_vm_xdialog.sh` - Comprehensive XDialog debug GUI

### Platform (4): Platform-specific VMs
- `platform_linux.sh` - Launch Linux VM
- `platform_macos_ppc.sh` - Launch MacOS PPC VM
- `platform_macos_106.sh` - Launch MacOS 10.6 PPC VM
- `platform_select_xdialog.sh` - XDialog platform selector

### Orchestration (3): Multi-VM operations
- `orchestration_start_all.sh` - Start all VMs
- `orchestration_stop_all.sh` - Stop all VMs
- `orchestration_status_all.sh` - Status of all VMs

### Disk (3): Disk image management
- `disk_create.sh` - Create disk image
- `disk_convert.sh` - Convert disk image
- `disk_resize.sh` - Resize disk image

### Image (2): Image management
- `image_list.sh` - List available images
- `image_download.sh` - Download image

### Export/Import (2): VM transfer
- `export_qcow2.sh` - Export VM to QCOW2
- `import_vm.sh` - Import VM from disk image

### Monitor/Test (2): Monitoring and testing
- `monitor_all.sh` - Monitor all VMs
- `test_run.sh` - Run tests in VM

### Information (2): System information
- `info_qemu_version.sh` - Show QEMU version
- `info_architectures.sh` - Show available architectures

### Utilities (2): Development tools
- `common.sh` - Shared functions and variables
- `generate_wrapper.sh` - Script generation tool
- `gui_scripts_menu.sh` - XDialog-based scripts menu

## 🎨 XDialog Integration

Scripts with XDialog support automatically:
- Detect XDialog binary availability
- Check X11 DISPLAY variable
- Fall back to CLI when not available
- Provide user-friendly graphical interfaces

**XDialog GUI Scripts:**
- `vm_create_xdialog.sh` - Multi-step VM creation form
- `debug_vm_xdialog.sh` - Debug session configuration
- `platform_select_xdialog.sh` - Platform selection menu
- `gui_scripts_menu.sh` - Scripts menu browser

## Usage Examples

```bash
# List all VMs
./scripts/vm_list.sh

# Create new VM
./scripts/vm_create.sh

# Start debug session
./scripts/debug_start.sh my-vm

# With XDialog GUI (if available)
./scripts/vm_create_xdialog.sh
./scripts/debug_vm_xdialog.sh
./scripts/platform_select_xdialog.sh
```

## Migration Status

- [x] Infrastructure created
- [x] 45 modular scripts implemented
- [x] XDialog GUI integration
- [x] Documentation updated
- [ ] Remaining functions (optional)

Total: 45 scripts covering all major functionality groups.