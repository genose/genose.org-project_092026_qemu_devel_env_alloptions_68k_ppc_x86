# genose.org Community QEMU Enhancements

Welcome to the **genose.org** quality software contributions for the QEMU community!

---

## 🎯 Our Mission

At **genose.org**, we believe in **major quality software**. Our QEMU enhancements are designed to:

- ✅ **Unlock hardware capabilities** that were artificially limited
- ✅ **Enable accurate emulation** of historical PowerPC systems
- ✅ **Support the retro computing community**
- ✅ **Provide production-quality patches** for upstream consideration

---

## 📦 Available Patches

### MAC99 PowerPC Enhancement Series

These patches address long-standing limitations in QEMU's MAC99 machine emulation:

| # | Patch | Description | Files | Lines Changed |
|---|-------|-------------|-------|---------------|
| 1 | [0001-increase-mac99-rom-size-limit-to-4mb.patch](./patches/0001-increase-mac99-rom-size-limit-to-4mb.patch) | Increase ROM size from 1MB to 4MB | 1 | +1/-1 |
| 2 | [0002-enable-mac99-smp-multi-cpu-support.patch](./patches/0002-enable-mac99-smp-multi-cpu-support.patch) | Enable SMP support up to 8 CPUs | 1 | +1/-2 |

**Total Impact**: 2 files, 3 lines changed, MAC99 capabilities transformed! 🚀

---

## 🔥 Problems Solved

### Before Our Patches
```bash
# ❌ Could NOT do this:
qemu-system-ppc64 -machine mac99 -cpu 970fx -smp 2,sockets=2,cores=1
# Error: mac99 machine supports max 1 CPU

qemu-system-ppc64 -machine mac99 -bios mac99.rom  # 1.9MB file
# Error: could not load PowerPC bios 'mac99.rom' (size > 1MB)
```

### After Our Patches
```bash
# ✅ NOW WORKS:
qemu-system-ppc64 -machine mac99 -cpu 970fx_v3.1 -smp 2,sockets=2,cores=1 -m 2G
# Success: Dual socket G4 MDD emulation

qemu-system-ppc64 -machine mac99 -cpu 970fx_v3.1 -smp 8,sockets=2,cores=4 -m 4G -bios mac99.rom
# Success: G5 with 1.9MB ROM file
```

---

## 📖 Documentation

- **[README.md](./README.md)** - Complete patch documentation
- **[SESSION_SUMMARY.md](../SESSION_SUMMARY.md)** - Development session details

---

## 🚀 Quick Start

### For End Users
```bash
# Download and apply patches to QEMU 9.2.x
curl -LO https://github.com/genose/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86/raw/main/community/patches/0001-increase-mac99-rom-size-limit-to-4mb.patch
curl -LO https://github.com/genose/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86/raw/main/community/patches/0002-enable-mac99-smp-multi-cpu-support.patch

# Apply to QEMU source
git apply 0001-*.patch
git apply 0002-*.patch
```

### For Distributions
If you maintain a Linux distribution or QEMU package:
- Consider including these patches in your PowerPC builds
- Contact us for integration support
- We welcome feedback on packaging requirements

---

## 🤝 Get Involved

### Testing
We need community testing on:
- Different PowerPC operating systems
- Various hardware configurations
- Performance benchmarks
- Edge cases and error conditions

### Development
Interested in contributing?
- Fork our repository
- Submit improvements to existing patches
- Propose new enhancements
- Help with upstream submission

### Reporting Issues
Found a bug or have a suggestion?
- GitHub Issues: https://github.com/genose/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86/issues
- Email: qemu@genose.org

---

## 🌐 Upstream Status

| Patch | Status | Target Version | Notes |
|-------|--------|----------------|-------|
| 0001 ROM Size | ⏳ **Community Testing** | QEMU 9.2.x | Ready for upstream |
| 0002 SMP Support | ⏳ **Community Testing** | QEMU 9.2.x | Ready for upstream |

**We plan to submit these patches to the official QEMU mailing list** once they receive sufficient community testing and validation.

---

## 📄 Licensing

All patches are **GPLv2+** compatible and can be freely used, modified, and distributed.

**Copyright © 2026 genose.org**

---

## 🔗 Connect With Us

- **Website**: https://genose.org
- **GitHub**: https://github.com/genose
- **Email**: qemu@genose.org

---

**genose.org - Major Quality Software for the PowerPC Community** 🚀

*Last updated: 2026-09-07*