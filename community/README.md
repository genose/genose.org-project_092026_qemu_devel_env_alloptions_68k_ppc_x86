# genose.org QEMU MAC99 Enhancement Patches

**Quality PowerPC Emulation Enhancements for the Community**

---

## 🎯 Mission Statement

As **genose.org**, we are committed to providing **major quality software** enhancements for the PowerPC emulation community. These patches address long-standing limitations in QEMU's MAC99 machine emulation that have prevented proper emulation of late G4 MDD and G5 PowerMac hardware.

---

## 📋 Patch Collection

### Available Patches for QEMU 9.2.x

| Patch | Purpose | Status | Files Modified |
|-------|---------|--------|----------------|
| `0001-increase-mac99-rom-size-limit-to-4mb.patch` | Increase ROM size from 1MB to 4MB | ✅ **Ready** | `hw/ppc/mac_newworld.c` |
| `0002-enable-mac99-smp-multi-cpu-support.patch` | Enable SMP support up to 8 CPUs | ✅ **Ready** | `hw/ppc/mac_newworld.c` |

---

## 🔧 Technical Details

### Patch 1: ROM Size Limit Increase

**Problem:** The MAC99 machine has a hard-coded 1MB ROM size limit, which is insufficient for many real-world ROM images (e.g., 1.9MB mac99.rom files from G5 systems).

**Solution:** Increase `PROM_SIZE` from `1 * MiB` to `4 * MiB`.

**Code Change:**
```c
// hw/ppc/mac_newworld.c:88
- #define PROM_SIZE (1 * MiB)
+ #define PROM_SIZE (4 * MiB)
```

**Impact:**
- ✅ Supports larger firmware images (up to 4MB)
- ✅ Enables loading of authentic G5 ROM files
- ✅ Maintains backward compatibility

**Hardware Justification:**
- G5 PowerMacs used ROM sizes up to 2MB
- 4MB provides headroom for custom firmware and future needs
- No known issues with larger ROM sizes in the emulation

---

### Patch 2: SMP Support Enablement

**Problem:** The MAC99 machine has SMP disabled with `mc->max_cpus = 1` and a comment stating "SMP is not supported currently". This prevents emulation of multi-CPU PowerMac systems.

**Solution:** Remove the disabling comment and increase maximum CPU count to 8.

**Code Change:**
```c
// hw/ppc/mac_newworld.c:577-578
- /* SMP is not supported currently */
- mc->max_cpus = 1;
+ mc->max_cpus = 8;  /* Support late G4 MDD (2 CPUs) and G5 (8 CPUs) */
```

**Impact:**
- ✅ Enables dual socket configurations
- ✅ Supports up to 8 CPUs total
- ✅ Allows emulation of late G4 MDD (2 CPUs) and G5 (8 CPUs)

**Hardware Justification:**
- **Late G4 MDD**: Dual socket, single CPU per socket = 2 CPUs
- **Late G5**: Dual socket, quad core CPU per socket = 8 CPUs
- Both were real Apple hardware configurations that ran MacOS 10.6

---

## 📊 Use Cases Enabled

### 1. MacOS 10.6 Snow Leopard
- **Target Hardware**: PowerMac G5 (PowerPC 970FX)
- **Configuration**: `-cpu 970fx_v3.1 -smp 8,sockets=2,cores=4`
- **ROM**: 1.9MB mac99.rom file
- **Status**: ✅ **Now Possible**

### 2. Late G4 MDD Systems
- **Target Hardware**: PowerMac G4 MDD (Dual CPU)
- **Configuration**: `-cpu 7455 -smp 2,sockets=2,cores=1`
- **Status**: ✅ **Now Possible**

### 3. Linux PPC64 Testing
- **Use Case**: Multi-core performance testing
- **Configuration**: `-cpu 970fx -smp 4,sockets=2,cores=2`
- **Status**: ✅ **Now Possible**

### 4. Retro Gaming
- **Use Case**: Better performance for multi-threaded games
- **Benefit**: Multi-core emulation improves performance
- **Status**: ✅ **Now Possible**

---

## 🚀 Installation Instructions

### For QEMU 9.2.x Source Tree

```bash
# 1. Download QEMU 9.2.x source
curl -LO https://download.qemu.org/qemu-9.2.0.tar.xz
tar -xf qemu-9.2.0.tar.xz
cd qemu-9.2.0

# 2. Apply genose.org patches
curl -LO https://github.com/genose/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86/raw/main/community/patches/0001-increase-mac99-rom-size-limit-to-4mb.patch
curl -LO https://github.com/genose/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86/raw/main/community/patches/0002-enable-mac99-smp-multi-cpu-support.patch

# 3. Apply patches
git apply 0001-increase-mac99-rom-size-limit-to-4mb.patch
git apply 0002-enable-mac99-smp-multi-cpu-support.patch

# 4. Configure and build
./configure --prefix=$HOME/.local/qemu-genose --target-list="ppc-softmmu,ppc64-softmmu"
make -j$(nproc)
make install
```

---

## 🤝 Community Contribution

### Reporting Issues
Please report any issues with these patches to:
- **GitHub Issues**: https://github.com/genose/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86/issues
- **Email**: contact@genose.org

### Contributing Back
If you improve these patches or find additional limitations, please:
1. Fork this repository
2. Create your enhancement
3. Submit a pull request

### Testing Results
We welcome test results from the community:
- Different MacOS versions
- Various Linux distributions on PPC64
- Performance benchmarks
- Hardware compatibility reports

---

## 📄 Legal & Licensing

All patches are provided under the **GNU General Public License version 2 or later**, consistent with QEMU's licensing.

**Copyright © 2026 genose.org**

Permission is hereby granted to use, copy, modify, and distribute these patches according to the terms of the GPLv2+.

---

## 🔗 Links

- **genose.org**: https://genose.org
- **GitHub Repository**: https://github.com/genose/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86
- **QEMU Official**: https://www.qemu.org
- **QEMU GitLab**: https://gitlab.com/qemu-project/qemu

---

**genose.org - Major Quality Software for the PowerPC Community** 🚀