# Supported CPUs

**Last Updated:** 2026-08-09  
**Version:** 1.1  
**Status:** ✅ Complete

---

## 📋 Overview

This document lists all CPU architectures and models supported by the custom bootloader. The bootloader implements automatic detection and configuration for each CPU type.

---

## 🪶 Motorola 68k Family

### Fully Supported CPUs

| CPU Model | CPU_ID | Detection Method | Features | Status |
|-----------|--------|------------------|----------|--------|
| **68000** | 1 | movec test (fails) | 16-bit, no VBR, no MMU | ✅ Complete |
| **68010** | 2 | movec test (succeeds), cpusha test (fails) | VBR, 32-bit addressing | ✅ Complete |
| **68020** | 3 | movec test (succeeds), cpusha test (fails), MMU test | VBR, 32-bit, MMU | ✅ Complete |
| **68030** | 4 | movec test (succeeds), cpusha test (fails), MMU test | VBR, 32-bit, MMU | ✅ Complete |
| **68040** | 5 | movec test (succeeds), cpusha test (succeeds), ptest test (succeeds) | VBR, 32-bit, MMU, Cache, Burst | ✅ Complete |
| **68060** | 6 | movec test (succeeds), cpusha test (succeeds), ptest test (fails) | VBR, 32-bit, MMU, Cache, Burst, FPU | ✅ Complete |

### NEW: Extended 68k Support (2026-08-09)

| CPU Model | CPU_ID | Detection Method | Features | Status |
|-----------|--------|------------------|----------|--------|
| **68LC040** | 7 | 68040 detection + FPU test (fails) | VBR, 32-bit, MMU, Cache, Burst, **No FPU** | ✅ NEW |
| **68EC040** | 8 | 68040 detection + MMU test (limited) | VBR, 32-bit, **Limited MMU**, Cache, Burst | ✅ NEW |
| **68070** | 9 | 68060+ detection | VBR, 32-bit, MMU, Cache, Burst, FPU | ✅ NEW |
| **ApolloCore (68080)** | 10 | 68060+ detection + Apollo extensions | VBR, 32-bit, MMU, Cache, Burst, FPU, **Apollo extensions** | ✅ NEW |

### 68k CPU Detection Flow

```
                      ┌─────────────────────┐
                      │   Entry Point        │
                      │   (detect_68k_cpu)   │
                      └──────────┬──────────┘
                                 │
                                 ▼
              ┌─────────────────────────────────────┐
              │ Test: movec vbr,d0                 │
              │ (68000: trap / 68010+: succeed)      │
              └──────────┬─────────────────────────┘
                         │
           ┌─────────────┴─────────────┐
           ▼                           ▼
    ┌──────────────┐            ┌──────────────────┐
    │ 68000        │            │ Test: cpusha dc   │
    │ Detected     │            │ (68010-68030:     │
    └──────────────┘            │  trap / 68040+:   │
                               │  succeed)        │
                               └─────────┬────────┘
                                         │
                         ┌───────────────┴───────────────┐
                         ▼                               ▼
                  ┌──────────────────┐          ┌──────────────────┐
                  │ Test: fmovecr    │          │ Test: ptest #0,  │
                  │ (68LC040: trap)  │          │ #7,d0            │
                  │                  │          │ (68040: succeed  │
                  └─────────┬────────┘          │ / 68060+: trap)  │
                            │                       └─────────┬────────┘
                            ▼                               │
                  ┌──────────────────┐                        ┌───────┴───────┐
                  │ 68LC040          │                        ▼               ▼
                  │ Detected         │               ┌──────────────┐ ┌──────────────┐
                  └──────────────────┘               │ 68040        │ │ 68060+/68070 │
                                                   │ Detected     │ │ ApolloCore   │
                                                   └──────────────┘ └──────────────┘
```

### 68k Feature Matrix

| Feature | 68000 | 68010 | 68020 | 68030 | 68040 | 68LC040 | 68EC040 | 68060 | 68070 | ApolloCore |
|---------|-------|-------|-------|-------|-------|---------|---------|-------|-------|------------|
| 16-bit Addressing | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 32-bit Addressing | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| VBR (Vector Base Register) | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| MMU | ❌ | ❌ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ |
| Cache | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Burst Mode | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Type 7 Stack Frames | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| FPU | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| ptest Instruction | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Apollo Extensions | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**Legend:**
- ✅ = Fully supported/present
- ❌ = Not supported/not present
- ⚠️ = Limited/partial support (68EC040 has limited MMU)

---

## 🍎 PowerPC Family

### Supported PPC CPUs

| CPU Model | CPU_ID | PVR Value | Detection Method | Features | Status |
|-----------|--------|-----------|------------------|----------|--------|
| **PPC601** | 101 | 0x0001 | PVR read | 32-bit, MMU, FPU | ✅ Complete |
| **PPC603** | 103 | 0x0003 | PVR read | 32-bit, MMU, FPU | ✅ Complete |
| **PPC604** | 104 | 0x0004 | PVR read | 32-bit, MMU, FPU, Burst | ✅ Complete |
| **PPC750 (G3)** | 108 | 0x0008 | PVR read | 32-bit, MMU, FPU, AltiVec (opt) | ✅ Complete |
| **PPC7410 (G4)** | 112 | 0x000C | PVR read | 32-bit, MMU, FPU, AltiVec | ✅ Complete |
| **PPC7455 (G4 Enhanced)** | 140 | 0x800C | PVR read | 32-bit, MMU, FPU, AltiVec | ✅ Complete |
| **PPC970 (G5)** | 153 | 0x0039 | PVR read | 64-bit, MMU, FPU, AltiVec | ✅ Complete |

### PPC CPU Detection Flow

```
┌─────────────────────┐
│   Entry Point        │
│   (PPC Code)         │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   mfspr r3, 287      │  Read Processor Version Register
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   Extract high 16    │  Get PVR version bits
│   bits of PVR        │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────────────────┐
│  Switch on PVR value:                      │
│  0x0001 -> PPC601                        │
│  0x0003 -> PPC603                        │
│  0x0004 -> PPC604                        │
│  0x0008 -> PPC750 (G3)                   │
│  0x000C -> PPC7410 (G4)                  │
│  0x800C -> PPC7455 (G4 Enhanced)         │
│  0x0039 -> PPC970 (G5)                   │
└─────────────────────────────────────────┘
```

### PPC Feature Matrix

| Feature | 601 | 603 | 604 | 750 | 7410 | 7455 | 970 |
|---------|-----|-----|-----|-----|------|------|-----|
| 32-bit Mode | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 64-bit Mode | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| MMU | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| FPU | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| AltiVec | ❌ | ❌ | ❌ | ⚠️ | ✅ | ✅ | ✅ |
| SMP | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**Legend:**
- ✅ = Fully supported/present
- ❌ = Not supported/not present
- ⚠️ = Optional/available on some models

---

## 🎯 CPU-Specific Notes

### 68LC040 (Low-Cost 68040)
- **Description:** 68040 without FPU
- **Detection:** Passes 68040 tests (movec, cpusha) but fails FPU test (fmovecr)
- **Use Case:** Embedded systems where FPU is not needed
- **Compatibility:** Same as 68040 except for floating-point operations

### 68EC040 (Embedded Controller 68040)
- **Description:** 68040 with limited MMU
- **Detection:** Passes 68040 tests, may have different MMU behavior
- **Use Case:** Embedded controller applications
- **Compatibility:** Similar to 68040 with potential MMU limitations

### 68060
- **Description:** Enhanced 68040 with superscalar execution
- **Detection:** Passes movec and cpusha tests, but ptest instruction is not present
- **Use Case:** High-performance 68k systems
- **Compatibility:** Backward compatible with 68040, plus additional features

### 68070
- **Description:** Hypothetical 68k variant (not officially released by Motorola)
- **Detection:** Same as 68060 (treated as 68060-class CPU)
- **Use Case:** Custom implementations or clones
- **Compatibility:** Assumed to be 68060-compatible

### ApolloCore (68080)
- **Description:** Modern 68k-compatible CPU by Apollo Computer
- **Detection:** Passes all 68060 tests plus Apollo-specific instruction tests
- **Use Case:** Retro computing and modern 68k development
- **Compatibility:** 68060-compatible with additional instructions and features
- **Website:** [Apollo Computer](https://www.apollo-computer.com/)

---

## 📊 Statistics

### Total Supported CPUs: 16

- **68k Family:** 10 CPUs
  - 68000, 68010, 68020, 68030
  - 68040, 68LC040, 68EC040
  - 68060, 68070, ApolloCore (68080)

- **PowerPC Family:** 7 CPUs
  - PPC601, PPC603, PPC604
  - PPC750 (G3)
  - PPC7410, PPC7455 (G4)
  - PPC970 (G5)

---

## 🔧 Implementation Details

### CPU Detection Files

| File | Description | Location |
|------|-------------|----------|
| `config.h` | CPU_ID and feature definitions | include/config.h |
| `detect.s` (68k) | 68k CPU detection assembly | src/cpu/m68k/detect.s |
| `detect.s` (PPC) | PPC CPU detection assembly | src/cpu/ppc/detect.s |
| `messages.s` | CPU-specific messages | src/common/messages.s |

### Detection Methods

#### 68k Detection
1. **movec instruction test:** Distinguishes 68000 from 68010+
2. **cpusha instruction test:** Distinguishes 68010-68030 from 68040+
3. **ptest instruction test:** Distinguishes 68040 from 68060+
4. **FPU test (fmovecr):** Distinguishes 68040 from 68LC040

#### PPC Detection
1. **Read PVR (Processor Version Register):** Identifies specific PPC model
2. **Extract high 16 bits:** Gets version information
3. **Compare with known values:** Matches against PVR database

---

## 🎛️ Adding New CPU Support

To add support for a new CPU:

### For 68k CPUs:

1. **Add CPU_ID to config.h:**
   ```c
   #define CPU_ID_NEWCPU 11
   ```

2. **Add CPU name string:**
   ```c
   #define CPU_NAME_NEWCPU "New CPU Name"
   ```

3. **Add feature flags in detect_68k_features:**
   ```asm
   cmp.l #CPU_ID_NEWCPU, %d0
   beq detect_newcpu_features
   
   detect_newcpu_features:
       move.l #FEATURE_FLAGS, %d1
       bra detect_done
   ```

4. **Add display message:**
   ```asm
   display_newcpu:
       pea msg_newcpu_running(%pc)
       bra display_string_common
   ```

5. **Add message string:**
   ```asm
   msg_newcpu_running:
       .asciz "New CPU Name running ...\r\n"
   ```

### For PPC CPUs:

1. **Add CPU_ID to config.h:**
   ```c
   #define CPU_ID_NEWPPC 102
   ```

2. **Add PVR value:**
   ```c
   #define PVR_NEWPPC 0x1234
   ```

3. **Add to PPC detection in detect_ppc.s:**
   ```asm
   cmpwi 3, CPU_ID_NEWPPC
   beq display_ppc_new
   ```

4. **Add CPU name and PVR to detection logic**

---

## 📚 References

- [Motorola 68000 Family Documentation](https://en.wikipedia.org/wiki/Motorola_68000_family)
- [PowerPC Documentation](https://en.wikipedia.org/wiki/PowerPC)
- [Apollo Computer](https://www.apollo-computer.com/)
- [68000 CPU Differences](http://eab.abime.net/showthread.php?t=68322)
- [PVR Values Reference](https://wiki.osdev.org/CPU_Registers_(PowerPC))

---

*Document generated by Mistral Vibe*  
*Date: 2026-08-09*  
*Last Updated: 2026-08-09*
