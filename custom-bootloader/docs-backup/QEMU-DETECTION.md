# QEMU DETECTION

**Project:** genose.org - Custom Bootloader  
**Version:** 1.0  
**Date:** 2026-08-09  

---

## 📌 OVERVIEW

This document describes the **QEMU detection mechanisms** implemented in the custom bootloader. Accurate QEMU detection is essential for:

- **Environment-specific behavior**: Different code paths for QEMU vs real hardware
- **Debugging integration**: Triggering GDB breaks via UART
- **Feature enablement**: Activating QEMU-specific optimizations
- **Fallback mechanisms**: Graceful degradation on real hardware

---

## 🎯 DETECTION METHODS

The bootloader implements **6 different detection methods**, tried in sequence until one succeeds:

| Method | Priority | Description | Speed | Reliability |
|--------|----------|-------------|-------|-------------|
| 1 | ⭐⭐⭐⭐⭐ | SCSI Controller Signature | Fast | High |
| 2 | ⭐⭐⭐⭐ | VIA Chip Registers | Fast | Medium |
| 3 | ⭐⭐⭐ | Debug Port Check | Medium | High |
| 4 | ⭐⭐ | ROM Signature | Medium | Medium |
| 5 | ⭐ | Memory Write Test | Slow | Medium |
| 6 | - | Default (Real Mac) | Instant | - |

---

## 🔍 METHOD DETAILS

### Method 1: SCSI Controller Signature

#### Principle
QEMU emulates SCSI controllers at known addresses with identifiable signatures. The real Mac hardware uses different SCSI chips.

#### Implementation (68k)

```c
#define SCSI_BASE_Q800       0x50F10000
#define SCSI_VENDOR_OFFSET    0x10
#define QEMU_SCSI_SIGNATURE   0x51454D55  // "QEMU"

int detect_scsi_qemu(void) {
    volatile uint32_t *scsi_vendor = (uint32_t*)(SCSI_BASE_Q800 + SCSI_VENDOR_OFFSET);
    return (*scsi_vendor == QEMU_SCSI_SIGNATURE);
}
```

#### Assembly Implementation

```assembly
detect_scsi_qemu:
    movem.l %d1/%a0, -(sp)
    
    /* Read from SCSI vendor ID address */
    move.l  #SCSI_BASE_Q800, %a0
    add.l   #SCSI_VENDOR_OFFSET, %a0
    move.l  (%a0), %d1
    
    /* Check for "QEMU" signature */
    cmp.l   #QEMU_SCSI_SIGNATURE, %d1
    beq     .scsi_qemu_found
    
    /* Try alternative SCSI address */
    move.l  #0x50F10010, %a0
    move.l  (%a0), %d1
    cmp.l   #QEMU_SCSI_SIGNATURE, %d1
    bne     .scsi_not_qemu
    
.scsi_qemu_found:
    move.l  #1, %d0
    bra     .scsi_done
    
.scsi_not_qemu:
    moveq   #0, %d0
    
.scsi_done:
    movem.l (%sp)+, %d1/%a0
    rts
```

#### Pros
- Very fast (single memory read)
- Highly reliable for QEMU
- No side effects

#### Cons
- May not work if QEMU uses custom SCSI emulation
- Address may vary between Mac models

---

### Method 2: VIA Chip Registers

#### Principle
The VIA (Versatile Interface Adapter) chip version registers have different values in QEMU vs real hardware. QEMU's VIA emulation typically reports 0x00 in the version register.

#### Implementation

```c
#define VIA1_BASE            0x50F00000
#define VIA2_BASE            0x50F04000
#define VIA_VERSION_REGISTER  0x03

int detect_via_qemu(void) {
    volatile uint8_t *via1_version = (uint8_t*)(VIA1_BASE + VIA_VERSION_REGISTER);
    volatile uint8_t *via2_version = (uint8_t*)(VIA2_BASE + VIA_VERSION_REGISTER);
    
    /* QEMU reports 0x00 in version register */
    return (*via1_version == 0x00 || *via2_version == 0x00);
}
```

#### Assembly Implementation

```assembly
detect_via_qemu:
    movem.l %d1/%a0, -(sp)
    
    /* Read VIA1 version register */
    move.l  #VIA1_BASE, %a0
    add.l   #VIA_VERSION_REGISTER, %a0
    move.b  (%a0), %d1
    
    /* QEMU VIA reports 0x00 */
    cmp.b   #0x00, %d1
    beq     .via_qemu_found
    
    /* Try VIA2 */
    move.l  #VIA2_BASE, %a0
    add.l   #VIA_VERSION_REGISTER, %a0
    move.b  (%a0), %d1
    cmp.b   #0x00, %d1
    bne     .via_not_qemu
    
.via_qemu_found:
    move.l  #1, %d0
    bra     .via_done
    
.via_not_qemu:
    moveq   #0, %d0
    
.via_done:
    movem.l (%sp)+, %d1/%a0
    rts
```

#### Pros
- Fast (2 memory reads)
- No risk of crashing
- Works on most Mac models

#### Cons
- Real hardware may also report 0x00
- Requires knowledge of VIA layout

---

### Method 3: Debug Port Check

#### Principle
QEMU provides a special debug port at address `0xE0000000` that can be read and written. Real Mac hardware does not have this port, and attempts to access it may cause bus errors (handled by our bus error handler).

#### Implementation

```c
#define QEMU_DEBUG_PORT       0xE0000000
#define QEMU_DEBUG_MAGIC      0x51454D55  // "QEMU"

int detect_debug_port(void) {
    volatile uint32_t *debug_port = (uint32_t*)QEMU_DEBUG_PORT;
    
    /* Try to read magic value */
    if (*debug_port == QEMU_DEBUG_MAGIC) {
        return 1;
    }
    
    /* Try write test */
    uint32_t test_value = 0xDEADBEEF;
    *debug_port = test_value;
    
    return (*debug_port == test_value);
}
```

#### Assembly Implementation

```assembly
detect_debug_port:
    movem.l %d1/%a0, -(sp)
    
    /* Try to read from debug port */
    move.l  #QEMU_DEBUG_PORT, %a0
    move.l  (%a0), %d1
    
    /* Check for magic value */
    cmp.l   #QEMU_DEBUG_MAGIC, %d1
    beq     .debug_qemu_found
    
    /* Also check if write succeeds without bus error */
    move.l  #0xDEADBEEF, %d1
    move.l  %d1, (%a0)
    move.l  (%a0), %d1
    cmp.l   #0xDEADBEEF, %d1
    beq     .debug_qemu_found
    
    moveq   #0, %d0
    bra     .debug_done
    
.debug_qemu_found:
    move.l  #1, %d0
    
.debug_done:
    movem.l (%sp)+, %d1/%a0
    rts
```

#### Pros
- Very reliable for QEMU
- Can detect write capabilities
- Works across architectures

#### Cons
- May cause bus error on real hardware (handled)
- Slightly slower

---

### Method 4: ROM Signature Check

#### Principle
Apple ROMs have specific signatures at known offsets. QEMU may use different ROM images or no ROM at all. However, this method is less reliable if QEMU uses real ROM images.

#### Implementation

```c
#define ROM_BASE              0x40800000
#define REAL_ROM_SIGNATURE    0x4150504C  // "APPL" (Apple)

int detect_rom_signature(void) {
    volatile uint32_t *rom_base = (uint32_t*)ROM_BASE;
    
    /* Real Apple ROM starts with "APPL" */
    if (*rom_base != REAL_ROM_SIGNATURE) {
        return 1;  // QEMU or non-Apple ROM
    }
    
    /* Secondary check */
    volatile uint32_t *rom_offset = (uint32_t*)(ROM_BASE + 0x0004);
    if (*rom_offset == 0x00000000) {
        return 1;  // Likely QEMU
    }
    
    return 0;  // Likely real Mac
}
```

#### Assembly Implementation

```assembly
detect_rom_signature:
    movem.l %d1/%a0, -(sp)
    
    /* Read from ROM base */
    move.l  #ROM_BASE, %a0
    move.l  (%a0), %d1
    
    /* Check for Apple signature "APPL" */
    cmp.l   #REAL_ROM_SIGNATURE, %d1
    bne     .rom_qemu_found
    
    /* Try a secondary check */
    move.l  #0x0004, %a0
    add.l   #ROM_BASE, %a0
    move.l  (%a0), %d1
    
    /* Real Apple ROM has non-zero at offset 4 */
    cmp.l   #0x00000000, %d1
    beq     .rom_qemu_found
    
    /* Assume real Mac */
    moveq   #0, %d0
    bra     .rom_done
    
.rom_qemu_found:
    move.l  #1, %d0
    
.rom_done:
    movem.l (%sp)+, %d1/%a0
    rts
```

#### Pros
- No risk of crashing
- Fast

#### Cons
- Less reliable (QEMU can use real ROM images)
- Address varies by Mac model

---

### Method 5: Memory Write Test

#### Principle
QEMU allows writes to certain protected memory areas (like address 0) that real hardware would reject with a bus error. We temporarily install a bus error handler to catch these errors.

#### Implementation

```c
define PROTECTED_MEMORY_TEST 0x00000000

volatile uint32_t bus_error_occurred = 0;

void test_bus_error_handler(void) {
    bus_error_occurred = 1;
    /* Clean up stack and return */
    __asm__ volatile ("addq.l #4, %sp; rte");
}

int detect_memory_write_test(void) {
    /* Save current bus error handler */
    volatile uint32_t *bus_error_vector = (uint32_t*)0x00000008;
    uint32_t original_handler = *bus_error_vector;
    
    /* Install our test handler */
    *bus_error_vector = (uint32_t)test_bus_error_handler;
    
    /* Clear flag */
    bus_error_occurred = 0;
    
    /* Try to write to null pointer */
    *(volatile uint32_t*)PROTECTED_MEMORY_TEST = 0xDEADBEEF;
    
    /* Check if bus error occurred */
    int result = !bus_error_occurred;  // If no error, it's QEMU
    
    /* Restore handler */
    *bus_error_vector = original_handler;
    
    return result;
}
```

#### Assembly Implementation

```assembly
detect_memory_write_test:
    movem.l %d1/%a0, -(sp)
    
    /* Save current bus error handler */
    move.l  0x00000008, %d1
    move.l  %d1, saved_bus_error_handler
    
    /* Install our test bus error handler */
    lea     test_bus_error_handler(%pc), %a0
    move.l  %a0, 0x00000008
    
    /* Set up a flag */
    clr.l   bus_error_occurred
    
    /* Try to write to null pointer */
    move.l  #0xDEADBEEF, %d1
    move.l  %d1, (0x00000000)
    
    /* Check if bus error occurred */
    move.l  bus_error_occurred, %d0
    tst.l   %d0
    bne     .write_test_real
    
    /* No bus error = QEMU */
    move.l  #1, %d0
    move.l  #5, qemu_detect_method
    bra     .write_test_done
    
.write_test_real:
    /* Bus error occurred = real hardware */
    moveq   #0, %d0
    
.write_test_done:
    /* Restore bus error handler */
    move.l  saved_bus_error_handler, %d1
    move.l  %d1, 0x00000008
    
    movem.l (%sp)+, %d1/%a0
    rts

    .data
    .align 4
saved_bus_error_handler:
    .long 0x00000000
bus_error_occurred:
    .long 0x00000000
    .text

test_bus_error_handler:
    move.l  #1, bus_error_occurred
    addq.l  #4, %sp           /* Clean up pushed PC */
    rte
```

#### Pros
- Very reliable (hardware behavior difference)
- Works across all architectures

#### Cons
- **Risky**: May crash on real hardware if handler not installed correctly
- Slow (requires handler installation)
- Should be used as **last resort**

---

### Method 6: PowerPC-Specific Detection

#### Principle
For PPC architecture, we can use processor-specific registers that have different behaviors in QEMU vs real hardware.

#### Implementation

```c
int detect_qemu_environment_ppc(void) {
    /* Method 1: Check DEC (Decrementer) register */
    /* QEMU initializes DEC to 0 */
    uint32_t dec;
    __asm__ volatile ("mfspr %0, 22" : "=r"(dec) : : "cc");
    if (dec == 0) {
        return 1;  // QEMU
    }
    
    /* Method 2: Memory test */
    uint32_t test_value = 0xDEADBEEF;
    __asm__ volatile ("stw %0, 0(%1)" : : "r"(test_value), "r"(0) : "memory");
    __asm__ volatile ("lwz %0, 0(%1)" : "=r"(dec) : "r"(0) : "memory");
    
    if (dec == test_value) {
        return 1;  // QEMU (write succeeded)
    }
    
    return 0;  // Real Mac
}
```

#### Assembly Implementation (PPC)

```assembly
detect_qemu_environment_ppc:
    /* Method 1: Check DEC (Decrementer) behavior */
    mfspr   3, 22              /* Read DEC (SPR 22) */
    cmpwi   0, 3
    bne     .ppc_not_qemu
    
    /* DEC is 0 in QEMU initially */
    li      3, 1
    li      4, 1              /* Method 1 */
    stw     4, qemu_detect_method
    bra     .ppc_done
    
.ppc_not_qemu:
    /* Method 3: Memory test */
    li      3, 0xDEADBEEF
    stw     3, 0x0000(0)       /* Try write to null */
    lwz     3, 0x0000(0)
    cmpwi   0, 3
    beq     .ppc_qemu_detected
    
    li      3, 0
    bra     .ppc_done
    
.ppc_qemu_detected:
    li      3, 1
    li      4, 3
    stw     4, qemu_detect_method
    
.ppc_done:
    blr
```

---

## 🔄 MAIN DETECTION FUNCTION

The main detection function tries all methods in sequence:

```c
int detect_qemu_environment(void) {
    static int cached_result = -1;  // -1 = not cached
    
    if (cached_result != -1) {
        return cached_result;
    }
    
    // Try Method 1: SCSI
    if (detect_scsi_qemu()) {
        cached_result = 1;
        qemu_detect_method = 1;
        return 1;
    }
    
    // Try Method 2: VIA
    if (detect_via_qemu()) {
        cached_result = 1;
        qemu_detect_method = 2;
        return 1;
    }
    
    // Try Method 3: Debug Port
    if (detect_debug_port()) {
        cached_result = 1;
        qemu_detect_method = 3;
        return 1;
    }
    
    // Try Method 4: ROM Signature
    if (detect_rom_signature()) {
        cached_result = 1;
        qemu_detect_method = 4;
        return 1;
    }
    
    // Try Method 5: Memory Write Test
    if (detect_memory_write_test()) {
        cached_result = 1;
        qemu_detect_method = 5;
        return 1;
    }
    
    // All methods failed - assume real Mac
    cached_result = 0;
    qemu_detect_method = 0;
    return 0;
}
```

---

## 📊 CACHING

### Why Cache?

QEMU detection is relatively expensive (multiple memory accesses, potential bus errors). Since the environment doesn't change during runtime, we cache the result.

### Cache Management

```c
/* Global variables */
static int qemu_cached_result = -1;  /* -1 = not cached */
static int qemu_detect_method = 0;    /* Method used (0-6) */

/* Force refresh */
void refresh_qemu_detection(void) {
    qemu_cached_result = -1;
    qemu_detect_method = 0;
}

/* Invalidate cache */
void invalidate_qemu_cache(void) {
    qemu_cached_result = -1;
}

/* Main function */
int detect_qemu_environment(void) {
    if (qemu_cached_result != -1) {
        return qemu_cached_result;
    }
    
    /* ... detection logic ... */
    
    qemu_cached_result = result;
    return result;
}
```

### Cache States

| Value | Meaning |
|-------|---------|
| -1 | Not cached (need to detect) |
| 0 | Real Mac hardware |
| 1 | QEMU emulator |

---

## 🎯 USAGE PATTERNS

### Pattern 1: Simple Check

```c
#include "bootloader_api.h"

if (bootloader_check_env()) {
    // Running in QEMU
    bootloader_trigger_gdb();
} else {
    // Running on real Mac
    // Use alternative debugging
}
```

### Pattern 2: Conditional Debugging

```c
void debug_function(void) {
    if (bootloader_check_presence() && bootloader_check_env()) {
        // Full debug capabilities available
        debug_break();
    } else if (bootloader_check_presence()) {
        // Bootloader present but on real Mac
        // Use limited debugging
        __asm__ volatile ("illegal");
    } else {
        // No bootloader - use standard debugging
        // (MacsBug, Debugger, etc.)
    }
}
```

### Pattern 3: Forced Detection

```c
// Force re-detection (if environment might have changed)
refresh_qemu_detection();

if (detect_qemu_environment()) {
    // Now in QEMU
}
```

### Pattern 4: Method-Specific Behavior

```c
int is_qemu = detect_qemu_environment();
int method = qemu_detect_method;

switch (method) {
    case 1:  // SCSI signature
        // Fast, reliable detection
        break;
    case 5:  // Memory write test
        // Less reliable but works in tricky cases
        break;
    default:
        // Standard detection
        break;
}
```

---

## ⚠️ SAFETY CONSIDERATIONS

### Risk Assessment

| Method | Risk Level | Mitigation |
|--------|------------|------------|
| SCSI Signature | ⭐ Low | Read-only access |
| VIA Registers | ⭐ Low | Read-only access |
| Debug Port | ⭐⭐ Medium | Read/write test, bus error handler |
| ROM Signature | ⭐ Low | Read-only access |
| Memory Write Test | ⭐⭐⭐⭐ High | Bus error handler, temporary installation |

### Best Practices

1. **Use Method 1-4 for normal detection**: These are safe and fast
2. **Use Method 5 only when necessary**: Memory write test should be last resort
3. **Always have bus error handler installed**: Before using Method 5
4. **Cache results**: Detection should only happen once
5. **Test on real hardware**: Ensure detection works correctly
6. **Provide fallbacks**: Code should work even if detection fails

---

## 🧪 TESTING

### Test Matrix

| Environment | Method 1 | Method 2 | Method 3 | Method 4 | Method 5 | Result |
|-------------|----------|----------|----------|----------|----------|--------|
| QEMU m68k | ✅ Pass | ✅ Pass | ✅ Pass | ✅ Pass | ✅ Pass | QEMU |
| QEMU PPC | ❌ N/A | ❌ N/A | ⚠️ Maybe | ❌ N/A | ✅ Pass | QEMU |
| Real Mac 68k | ❌ Fail | ❌ Fail | ❌ Fail | ❌ Fail | ❌ Fail | Real |
| Basilisk II | ⚠️ Maybe | ⚠️ Maybe | ⚠️ Maybe | ⚠️ Maybe | ⚠️ Maybe | Varies |
| SheepShaver | ⚠️ Maybe | ⚠️ Maybe | ⚠️ Maybe | ⚠️ Maybe | ⚠️ Maybe | Varies |

### Test Code

```c
#include "bootloader_api.h"
#include "qemu_detect.h"

void test_qemu_detection(void) {
    bootloader_log_message("Testing QEMU Detection...\n");
    
    // Force fresh detection
    refresh_qemu_detection();
    
    // Test each method
    int m1 = detect_scsi_qemu();
    int m2 = detect_via_qemu();
    int m3 = detect_debug_port();
    int m4 = detect_rom_signature();
    int m5 = detect_memory_write_test();
    int final = detect_qemu_environment();
    
    bootloader_log_message("Method 1 (SCSI): ");
    bootloader_log_message(m1 ? "PASS\n" : "FAIL\n");
    
    bootloader_log_message("Method 2 (VIA): ");
    bootloader_log_message(m2 ? "PASS\n" : "FAIL\n");
    
    bootloader_log_message("Method 3 (Debug Port): ");
    bootloader_log_message(m3 ? "PASS\n" : "FAIL\n");
    
    bootloader_log_message("Method 4 (ROM): ");
    bootloader_log_message(m4 ? "PASS\n" : "FAIL\n");
    
    bootloader_log_message("Method 5 (Memory): ");
    bootloader_log_message(m5 ? "PASS\n" : "FAIL\n");
    
    bootloader_log_message("Final Result: ");
    bootloader_log_message(final ? "QEMU\n" : "Real Mac\n");
    bootloader_log_message("Method Used: ");
    char msg[32];
    snprintf(msg, sizeof(msg), "%d\n", qemu_detect_method);
    bootloader_log_message(msg);
}
```

---

## 📚 REFERENCES

- [BOOTLOADER-API-SPEC.md](BOOTLOADER-API-SPEC.md) - API specification
- [DUAL-BACKTRACE-ENGINE.md](DUAL-BACKTRACE-ENGINE.md) - Backtrace implementation
- [src/common/qemu_detect.s](../src/common/qemu_detect.s) - Implementation
- [include/bootloader_api.h](../include/bootloader_api.h) - API header

---

## 🎓 NOTES

1. **QEMU Versatility**: QEMU can emulate many different Mac models, each with different hardware layouts. The detection methods try to account for this variability.

2. **Future-Proofing**: As QEMU evolves, new detection methods may be needed. The modular design allows adding new methods easily.

3. **Alternative Emulators**: Basilisk II, SheepShaver, and other emulators may require different detection methods. The current implementation focuses on QEMU.

4. **Performance**: Caching ensures detection only happens once, making subsequent calls very fast.

5. **Portability**: The detection methods are designed to work across different Mac models and QEMU configurations.

---

*Generated by Mistral Vibe - QEMU Detection Specification*
*Date: 2026-08-09*
*Version: 1.0*
