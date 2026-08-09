# QEMU 9.2.0 Patches

This directory contains upstream backport patches from the QEMU
`stable-9.2` branch applied on top of the vendored `v9.2.0` tag.

All patches are cherry-picked from the official QEMU project and included
in QEMU 9.2.1 and later.  They are provided here so that `build_qemu.sh`
can apply them automatically before configuring — no need to upgrade the
base version.

`build_qemu.sh patch` (or the `all` flow) applies every `.patch` file found
under `patches/` **in lexicographic order** within each subdirectory,
processing subdirectories in the order: `general/`, `m68k/`, `ppc/`, `sparc/`.

---

## Directory layout

```
patches/
  general/   Fixes that affect all targets (networking, big-endian hosts)
  m68k/      Fixes specific to Motorola 68000 targets (Mac 68k, Amiga, Atari)
  ppc/       Fixes specific to PowerPC targets (mac99 G3/G4, mac_oldworld)
  sparc/     Fixes specific to SPARC targets (sun4u/sun4m, Solaris guests)
```

---

## Patches included

### general/

| File | Upstream commit | Fixed in | Summary |
|---|---|---|---|
| `0001-hw-net-Fix-NULL-dereference-with-software-RSS.patch` | `4f5adbe6` | **v9.2.1** | Fix NULL dereference in virtio-net when eBPF RSS program fails to attach |
| `0002-vdpa-Allow-vDPA-to-work-on-big-endian-machine.patch` | `bcf9282f` | **v9.2.1** | Allow vDPA networking on big-endian hosts (PPC/SPARC); prevents silent fallback to userspace virtio |

### m68k/

No upstream stable-9.2 backports are currently required for the m68k
target.  The `q800` (Mac Quadra 800) and `virt` machines are stable in 9.2.0.
Drop `.patch` files here if you need to carry local fixes.

### ppc/

| File | Upstream commit | Fixed in | Summary |
|---|---|---|---|
| `0001-target-ppc-Fix-facility-interrupt-checks-for-VSX.patch` | `6726d487` | **v9.2.3** | Fix facility interrupt ordering for VSX instructions — **critical**: caused crash (`Raised an exception without defined vector 94`) when booting NetBSD/macppc on mac99 G3/G4 (PPC 7xx/74xx). Resolves GitLab issue #2741. |
| `0002-ppc-spapr-fix-default-cpu-for-pre-9.0-machines.patch` | `64e16e38` | **v9.2.3** | Fix default CPU selection for compat machines older than QEMU 9.0 (pseries/sPAPR). |

### sparc/

| File | Upstream commit | Fixed in | Summary |
|---|---|---|---|
| `0001-target-sparc-Fix-gdbstub-incorrectly-handling-regist.patch` | `9a516504` | **v9.2.2** | Fix gdbstub off-by-one for floating-point registers f32–f62 — registers f32 and f34 aliased to same value under GDB. Broken debugging of Solaris guests on sun4u. |
| `0002-target-sparc-Fix-register-selection-for-all-F-TOx-an.patch` | `5afb837e` | **v9.2.2** | Fix FP conversion instruction register encoding (fdtox, fqtox, etc.) — **regression in QEMU 9.x** causing incorrect floating-point results. Resolves GitLab issue #2802. |

---

## Adding new patches

1. Generate a patch with `git format-patch -1 <commit> -o patches/<subdir>/`
2. Name it `NNNN-brief-description.patch` so it sorts correctly.
3. Test it applies cleanly: `git -C qemu-9.2.0 apply --check patches/<subdir>/<patch>`

`build_qemu.sh` uses `git apply` inside the QEMU source tree, so patches
must be in unified diff format relative to the QEMU source root.
