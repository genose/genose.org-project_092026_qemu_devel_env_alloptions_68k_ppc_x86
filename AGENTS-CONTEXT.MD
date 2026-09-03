# Agent Context - genose.org QEMU Retro Development Environment
**Last Updated:** 2026-09-03  
**Project:** Custom QEMU build and VM-assist launcher for retro computing platforms  
**Repository:** `genose/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86`  
**Maintainer:** Mistral Vibe + Copilot Integration

---

## 📋 TABLE OF CONTENTS
1. [Project Overview](#-project-overview)
2. [Current Status](#-current-status)
3. [Core Components](#-core-components)
4. [Supported Platforms](#-supported-platforms)
5. [Build System](#-build-system)
6. [VM Launcher](#-vm-launcher)
7. [Configuration Management](#-configuration-management)
8. [Patch Management](#-patch-management)
9. [Session History](#-session-history)
10. [Next Steps & Objectives](#-next-steps--objectives)

---

## 🎯 PROJECT OVERVIEW

**Purpose:** Create a comprehensive VM management assistant for retro computing and modern systems, combining custom QEMU compilation with intelligent VM launching capabilities.

**Key Capabilities:**
- Custom QEMU 9.2.0+ build system with upstream backport patches
- VM-assist launcher with 14 architecture presets
- UTM.app integration for macOS users
- File sharing via Samba, Netatalk, 9P/VirtFS
- Multi-screen display support
- GDB debugging bridges
- ISO/ROM management system

**Supported Environments:**
- **Primary:** macOS (with QEMU and optional UTM.app)
- **Secondary:** Linux, *BSD (QEMU-only)
- **Build:** Cross-platform with platform-specific dependency handling

---

## ✅ CURRENT STATUS

### Git State
- **Branch:** `main` (clean, up to date with origin/main)
- **Last Commit:** `4388319` - Merge PR #3 from copilot/pr-2-review-feedback
- **Conflict Resolution:** Complete - all merge conflicts resolved
  - `build_qemu.sh`: SPICE comment + macOS/Fedora dependency hints preserved
  - `COPILOT-CONTEXT.MD`: Kept (main had deleted it)
  - `vm_assist.sh` / `README.md`: Merged cleanly

### Main Components Status
| Component | Status | Version | Notes |
|---|---|---|---|
| `build_qemu.sh` | ✅ Active | - | SPICE support, all retro targets |
| `vm_assist.sh` | ✅ Active | - | 8 platform presets |
| `vm-assistant-unified.sh` | ✅ Available | ~2400 lines | Merged best features |
| `patches/` | ✅ Applied | 6 upstream | general/ppc/sparc |
| `qemu-9.2.0/` | ✅ Submodule | 9.2.0 | Git submodule |
| System QEMU | ✅ Detected | 11.0.3 | `/usr/local/bin/qemu-system-ppc64` |

### Recent Achievements (2026-09-03)
- ✅ Dynamic ISO discovery from `~/vm_assistant/isos/` implemented
- ✅ Auto-detection of QEMU display backends (cocoa/sdl/gtk)
- ✅ MacOS 10.6 PPC test infrastructure created
- ✅ ISO management integration with Gestion des ISOs paths
- ✅ Git working tree cleaned (untracked files removed)

---

## 🏗️ CORE COMPONENTS

### 1. build_qemu.sh (12.5 KiB)
- **Purpose:** Custom QEMU compilation with retro target focus
- **Targets:** m68k, ppc, ppc64, i386, x86_64, sparc, sparc64
- **x86 Host Feature:** Auto-expands to ALL `qemu-system-*` targets
- **Compatibility Flags:** `-march=x86-64 -mtune=westmere -mno-avx -mno-avx2`
- **Features Enabled:** SPICE, VirtFS, USB redirection, SmartCard, OpenGL
- **Patch System:** Automatic application from `patches/{general,m68k,ppc,sparc}/`

**Commands:**
```bash
bash build_qemu.sh all          # Full build pipeline
bash build_qemu.sh configure    # Just configure
bash build_qemu.sh build        # Just compile
bash build_qemu.sh install      # Just install
bash build_qemu.sh patch        # Apply upstream patches
```

### 2. vm_assist.sh (52.7 KiB)
- **Purpose:** Interactive and preset-driven VM launcher
- **Platforms:** 8 presets (MacOS 68k/PPC, Atari, Amiga, HaikuOS, Solaris x86/SPARC, Windows XP, OpenStep)
- **Display Backends:** SDL, GTK, VNC, curses, none, SPICE
- **Features:** Multi-screen, GDB bridging, 9P/VirtFS, RAM sizing, firmware auto-detection

**Commands:**
```bash
bash vm_assist.sh              # Interactive menu
bash vm_assist.sh macos-ppc    # Direct launch
bash vm_assist.sh images       # Disk image management
```

### 3. vm-assistant-unified.sh (~2400 lines)
- **Purpose:** Unified VM assistant combining best features
- **Architectures:** 14 total (ppc, 604ev, 68040, apollocore, i386, sparc, arm, etc.)
- **Integration:** UTM.app, MacPorts, Homebrew, XQuartz, RAMDISK

### 4. vm-assistant/ Directory
- `vm-assistant-macports.sh` - MacPorts dependency installer
- `vm-assistant-network.sh` - Samba/Netatalk configuration
- `vm-assistant-test-connections.sh` - Connection testing

---

## 🖥️ SUPPORTED PLATFORMS

### PowerPC/Macintosh
| Model | CPU Options | Machine | Notes |
|---|---|---|---|
| Old World | 601, 604, 7455 (G4) | mac99 | ROM required |
| New World | 7455 (G4), 970 (G5) | mac99,via=pmu | OpenBIOS default |
| G5 Dual | 970fx | mac99,via=pmu | -smp 2,sockets=2,cores=1 |
| G5 Dual Core | 970mp | mac99,via=pmu | -smp 2,sockets=1,cores=2 |

**Supported OS:**
- Mac OS 7.1 - 9.2.2 (68k + PPC)
- Mac OS X 10.2 - 10.6 (PPC/ppc64)

### Motorola 68k
| Platform | CPU Options | Machine | Emulator |
|---|---|---|---|
| Mac 68k | m68000-m68040 | q800 | qemu-system-m68k |
| Atari ST/TT | m68000-m68040 | - | Hatari preferred |
| Amiga | m68040 | virt | FS-UAE preferred |

**Supported OS:**
- Mac OS 7.1 - 8.1
- Atari TOS, EmuTOS
- AROS (AmigaOS-compatible)

### x86/x86_64
| Platform | CPU | Machine | OS |
|---|---|---|---|
| HaikuOS | host (KVM) | q35 | HaikuOS i386/x86_64 |
| Solaris | pentium3 | pc | Solaris x86 |
| Windows XP | pentium3 | pc | Windows XP i386 |
| OpenStep | pentium | pc | OpenStep i386 |

### SPARC/SPARC64
| Platform | CPU | Machine | OS |
|---|---|---|---|
| Solaris | TI UltraSparc IIi | sun4u | Solaris SPARC |

---

## ⚙️ BUILD SYSTEM

### Dependencies

**Debian/Ubuntu:**
```bash
sudo apt-get install build-essential git ninja-build pkg-config python3-pip \
  libglib2.0-dev libpixman-1-dev libsdl2-dev libgtk-3-dev libvte-2.91-dev \
  libslirp-dev libbz2-dev liblzo2-dev libsnappy-dev libssh-dev \
  libusbredirhost-dev libcacard-dev libepoxy-dev libncurses-dev \
  libspice-server-dev libspice-protocol-dev
```

**macOS (Homebrew):**
```bash
brew install ninja pkg-config glib pixman sdl2 gtk+3 libslirp spice-protocol spice-gtk
```

**Fedora/RHEL:**
```bash
sudo dnf install @development-tools ninja-build glib2-devel pixman-devel \
  SDL2-devel gtk3-devel slirp-devel bzip2-devel lzo-devel snappy-devel \
  libssh-devel usbredir-devel openssl-devel spice-protocol spice-server-devel
```

### Environment Variables
| Variable | Default | Description |
|---|---|---|
| `QEMU_VERSION` | 9.2.0 | QEMU version to build |
| `QEMU_INSTALL_PREFIX` | ~/.local/qemu-retro | Installation prefix |
| `QEMU_X86_COMPAT_CFLAGS` | `-march=x86-64 -mtune=westmere -mno-avx -mno-avx2` | Host C/C++ flags |
| `PATCHES_DIR` | ./patches | Directory of .patch files |
| `JOBS` | nproc | Parallel build jobs |

---

## 🚀 VM LAUNCHER

### Configuration Files
All platform configurations in `vm-configs/*.env`:
- `macos-68k.env` - Mac OS 7.1-8.1 (68k)
- `macos-ppc.env` - Mac OS 7.5.2-9.2.2 (PPC G3/G4)
- `macos-ppc64.env` - Mac OS X (PPC G5/970)
- `atari.env` - Atari ST/STE/TT/Falcon
- `amiga.env` - Amiga/AROS (68k)
- `haiku.env` - HaikuOS (i386/x86_64)
- `solaris-x86.env` - Solaris x86
- `solaris-sparc.env` - Solaris SPARC
- `windows-xp.env` - Windows XP i386
- `openstep.env` - OpenStep i386

### Key Features
- **Multi-screen:** Multiple VGA devices, PCI/AGP configurations
- **RAM Sizing:** Plain MiB values or QEMU suffixes (512M, 4G, etc.)
- **Firmware:** Auto-detection, -bios vs pflash based on file size
- **Network:** NAT, User, None modes with port forwarding
- **GDB Debugging:** Guest GDB bridge, QEMU GDB stub
- **Host Integration:** /tmp/volatile_hd RAMDISK, AFP/Netatalk endpoints

---

## 📁 CONFIGURATION MANAGEMENT

### Paths
| Directory | Purpose | Environment Variable |
|---|---|---|
| `~/.local/qemu-retro/` | QEMU installation | `QEMU_INSTALL_PREFIX` |
| `~/vm_assistant/images/` | Disk images | `VM_IMAGE_DIR` |
| `~/vm_assistant/shares/` | 9P/VirtFS sharing | `VM_SHARED_DIR` |
| `~/vm_assistant/logs/` | Session logs | `VM_LOG_DIR` |
| `~/vm_assistant/isos/` | ISO storage (Gestion des ISOs) | `VM_ASSISTANT_ISO_DIR` |
| `~/vm_assistant/vms/` | VM configurations | - |
| `~/vm_assistant/shares/` | RAMDISK for Mac guests | `DEFAULT_MACOS_SHARE_DIR` |

### Defaults
| Setting | Default | Notes |
|---|---|---|
| Display Backend | Auto-detected | cocoa (macOS), gtk/sdl (Linux) |
| RAM | 256 MiB | Per-platform configurable |
| Network Model | Platform-specific | sungem (PPC), e1000 (x86) |
| Audio Backend | sdl | -audiodev sdl,id=snd0 |

---

## 🔧 PATCH MANAGEMENT

### Patch Organization
```
patches/
├── general/
│   ├── 0001-fix-null-deref-virtio-net.patch
│   └── 0002-allow-vdpa-be-hosts.patch
├── ppc/
│   ├── 0001-fix-vsx-interrupt-g3g4.patch
│   └── 0002-fix-default-cpu-pre9.patch
└── sparc/
    ├── 0001-fix-gdb-stub-f32-f62.patch
    └── 0002-fix-fp-convert-fdtox.patch
```

### Patch Application
- **Order:** general → m68k → ppc → sparc → root patches/
- **Idempotent:** Checks if already applied before applying
- **Format:** Named `NNNN-description.patch`
- **Source:** Official QEMU stable-9.2 cherry-picks

See `patches/README.md` for full catalog with commit SHAs.

---

## 📊 SESSION HISTORY

### 2026-09-03 (Current Session)
- ✅ Reloaded project context and memory
- ✅ Created `test_macos106_ppc.sh` for MacOS 10.6 PPC testing
- ✅ Created `vm-configs/macos-106-ppc.env` configuration
- ✅ Implemented dynamic ISO discovery from `~/vm_assistant/isos/`
- ✅ Added display backend auto-detection (cocoa/sdl/gtk)
- ✅ Fixed QEMU 11.0.3 display backend compatibility
- ✅ Cleaned git working tree
- ✅ **Merged COPILOT-CONTEXT.MD and MISTRAL-CONTEXT.MD into AGENTS-CONTEXT.MD**
- ✅ **Created unified `vm-manager.sh` combining all scripts into ONE TOOL**
  - Merged: build_qemu.sh + vm_assist.sh + vm-assistant-unified.sh
  - Unified CLI with subcommands for build, manage, launch, configure
  - Dynamic ISO discovery, display backend detection
  - 14+ architecture support (68k, PPC, x86, SPARC, ARM)
  - Interactive menu + CLI modes

### 2026-08-09 (Previous Session)
- ✅ PR #2 created via GitHub CLI
- ✅ SPICE support added to build_qemu.sh
- ✅ SPICE dependencies added for Debian, macOS, Fedora
- ✅ PPC boot fix: Changed default `via` from `cuda` to `pmu`
- ✅ Merged duplicate validate_vm_config() functions
- ✅ All corrections committed and pushed
- ✅ Context fusion: COPILOT-CONTEXT.MD integrated into MISTRAL-CONTEXT.MD

### 2026-08-08
- ✅ Analyzed vm_assist.sh and vm-assistant-vm.sh
- ✅ Identified missing features from MISTRAL-CONTEXT.MD
- ✅ Fixed PPC boot issue (via=pmu)
- ✅ Merged duplicate validation functions
- ✅ Committed all changes
- ✅ Pushed to origin/merged_qemu_build_and_vm_assistant

---

## 🎯 NEXT STEPS & OBJECTIVES

### Priority 1: Testing & Validation
- [x] Test MacOS 10.6 PPC installation with dynamic ISO discovery
- [x] Verify display backend auto-detection across platforms
- [x] Test SPICE clipboard/drag-drop functionality
- [x] Validate multi-screen configurations
- [x] **Test unified `vm-manager.sh` tool** - All commands verified

### Priority 2: Documentation
- [x] Update README.md with MacOS 10.6 PPC support notes
- [x] Document dynamic ISO discovery in AGENTS-CONTEXT.MD
- [x] Merged COPILOT-CONTEXT.MD and MISTRAL-CONTEXT.MD into AGENTS-CONTEXT.MD
- [x] **Document unified `vm-manager.sh` in AGENTS-CONTEXT.MD**
- [ ] Update .github/copilot-instructions.md with new workflows

### Priority 3: Code Quality
- [ ] ShellCheck validation for vm-manager.sh
- [x] Standardize error handling across scripts (return codes fixed)
- [x] Improve cross-platform compatibility (macOS/Linux/BSD)
- [ ] Add unit tests for core functions

### Priority 4: Cleanup & Deployment
- [ ] Commit `vm-manager.sh` to repository
- [ ] Update README.md to reference unified tool
- [ ] Archive or remove legacy scripts (optional)
- [ ] Update all references to use `vm-manager.sh`

---

## 💡 USAGE EXAMPLES

### Build QEMU
```bash
# Full build (configure, patch, compile, install)
bash build_qemu.sh all

# Individual steps
bash build_qemu.sh download
bash build_qemu.sh patch
bash build_qemu.sh configure
bash build_qemu.sh build
bash build_qemu.sh install
```

### Launch VMs
```bash
# Interactive menu
bash vm_assist.sh

# Direct platform launch
bash vm_assist.sh macos-ppc
bash vm_assist.sh macos-ppc64
bash vm_assist.sh haiku
bash vm_assist.sh solaris-sparc

# With custom options
QEMU_PREFIX=/custom/path bash vm_assist.sh macos-ppc
```

### Test MacOS 10.6 PPC
```bash
# List available ISOs
bash test_macos106_ppc.sh list_isos

# Show QEMU command
bash test_macos106_ppc.sh show_cmd

# Create disk image
bash test_macos106_ppc.sh create_disk

# Launch installer (interactive ISO selection)
bash test_macos106_ppc.sh menu
```

---

## 📝 MAINTENANCE NOTES

### File Structure
```
.
├── vm-manager.sh             # ⭐ UNIFIED TOOL: Build + Manage + Launch + Configure
│                              #    Replaces: build_qemu.sh + vm_assist.sh + vm-assistant-unified.sh
│                              #    1147 lines, 20+ commands, 14+ architectures
├── build_qemu.sh              # Legacy: QEMU build automation (308 lines)
├── vm_assist.sh               # Legacy: Interactive VM launcher (1434 lines)
├── vm-assistant-unified.sh    # Legacy: Unified VM assistant (2377 lines)
├── vm-assistant/              # Legacy VM assistant modules
│   ├── vm-assistant-macports.sh
│   ├── vm-assistant-network.sh
│   └── vm-assistant-test-connections.sh
├── vm-configs/                # Platform configuration templates
│   ├── macos-68k.env
│   ├── macos-ppc.env
│   ├── macos-ppc64.env
│   ├── macos-106-ppc.env      # NEW: MacOS 10.6 PPC config
│   ├── atari.env
│   ├── amiga.env
│   ├── haiku.env
│   ├── solaris-x86.env
│   ├── solaris-sparc.env
│   ├── windows-xp.env
│   └── openstep.env
├── patches/                   # Upstream backport patches
│   ├── general/
│   ├── m68k/
│   ├── ppc/
│   ├── sparc/
│   └── README.md
├── qemu-9.2.0/                # QEMU source (git submodule)
├── resources/                 # Additional resources
├── .github/
│   └── copilot-instructions.md
├── AGENTS-CONTEXT.MD         # THIS FILE: Merged master context
├── COPILOT-CONTEXT.MD        # Legacy: Current task context
├── MISTRAL-CONTEXT.MD        # Legacy: Historical context
├── README.md
├── INSTALL.sh
└── test_connection.sh
```

### Context Files Status
- **AGENTS-CONTEXT.MD** (THIS FILE): ✅ **ACTIVE** - Merged master context
- **COPILOT-CONTEXT.MD**: ⚠️ Legacy - Kept for reference, superseded by this file
- **MISTRAL-CONTEXT.MD**: ⚠️ Legacy - Historical context, superseded by this file

---

*Generated by Mistral Vibe*  
*Co-Authored-By: Mistral Vibe <vibe@mistral.ai>*  
*Date: 2026-09-03*
