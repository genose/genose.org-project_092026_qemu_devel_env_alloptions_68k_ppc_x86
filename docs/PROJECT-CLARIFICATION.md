# Project Clarification

*Document Type: Architectural Clarification*  
*Generated: 2026-09-03*  
*Purpose: Canonical Description of Project Purpose and Scope*

---

## 🎯 Core Purpose

**This tool is a development environment builder, NOT a general-purpose VM manager.**

The system is specifically designed to:

1. **Build full development environments** for cross-platform development
2. **Deploy test binaries** to target VMs
3. **Enable GDB debugging** from host machine to guest VMs
4. **Provide GUI interfaces** via XDialog + XQuartz

---

## 🏗️ Architecture

### Component Separation

| Component | Location | Responsibility |
|-----------|----------|----------------|
| **Cross-compiling toolchain** | External Git Repository | Source code → Target binary compilation |
| **This tool (vm-manager.sh)** | This Repository | VM management, binary deployment, debugging bridge |

### Workflow

```
1. BUILD PHASE
   Host Machine + External Cross-Compilation Toolchain
   Source Code → Cross-Compiler → Target Binary

2. DEPLOY PHASE  
   This Tool (vm-manager.sh)
   Target Binary → Target VM Deployment

3. DEBUG PHASE
   GDB Bridge: Host ↔ Guest VM
   Host GDB Client → Guest GDB Server

4. ITERATE
   Modify → Rebuild → Redeploy → Debug
```

---

## 🖥️ GUI Implementation

**GUI is provided by XDialog + XQuartz:**

- **XDialog**: Graphical dialog boxes, file selectors, message boxes
- **XQuartz**: X11 server for macOS enabling GUI applications from VMs to display on host

### GUI Capabilities

- ✅ File selection dialogs
- ✅ Input dialogs for configuration
- ✅ Message boxes and notifications
- ✅ X11 forwarding for GUI applications
- ✅ GUI application display on macOS host

---

## 🔧 Key Integrations

### GDB Debugging Infrastructure

- ✅ GDB bridge setup between host and guest
- ✅ Configurable GDB ports (default: 1234)
- ✅ TCP port forwarding for GDB connection
- ✅ Multiple VM debugging support
- ✅ Debug flag configuration for QEMU
- ✅ Pause at startup for debugger attachment

### Supported Architectures

- 68k (MacOS System 7 - 8.1)
- PPC (MacOS 7.5.2 - 9.2.2)
- PPC64 (MacOS X on G5, Tiger, Leopard)
- x86/x86_64 (Linux, Windows XP, OpenStep, Haiku)
- SPARC/SPARC64 (Solaris)
- ARM/ARM64
- And more...

---

## 📋 Summary

**Correct Understanding:**

> This tool is here to **build and provide around a full Dev ENV with GDB ability to drive the deployed test binary from the VM**

**Cross-compiling toolchain:** Handled by **another git repo** (external)

**GUI:** **XDialog + XQuartz**

---

## ✅ Verification

- [x] Development environment focus confirmed
- [x] Cross-compilation toolchain is external
- [x] GDB debugging is central feature
- [x] GUI via XDialog + XQuartz confirmed
- [x] Binary deployment workflow understood

---

*Document created based on user clarification of project scope and purpose*
*Last updated: 2026-09-03*