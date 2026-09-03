# GitHub Copilot Instructions

## Project overview

This repository provides a custom QEMU 9.2.0 build system and interactive VM-assist launcher
for retro computing platforms (Motorola 68k, PowerPC 32/64-bit, x86/x86_64, SPARC/SPARC64).

**Key scripts:**
- `build_qemu.sh` — configure, patch, build, and install QEMU
- `vm_assist.sh` — interactive and preset-driven VM launcher

**Directory layout:**
```
build_qemu.sh        QEMU build script
vm_assist.sh         Interactive VM launcher
qemu-9.2.0/          QEMU 9.2.0 source (git submodule)
patches/
  general/           Patches affecting all targets
  m68k/              Motorola 68k target patches
  ppc/               PowerPC target patches
  sparc/             SPARC target patches
  README.md          Patch catalog with upstream commit references
vm-configs/          Per-platform environment reference files (.env)
COPILOT-CONTEXT.MD   Live task context — keep updated each session
```

## Coding conventions

- **Shell:** `bash` only (`#!/usr/bin/env bash`). Always open scripts with `set -euo pipefail`.
- Add `# shellcheck disable=SC2054` at the top of any script that passes QEMU flags with
  embedded commas (e.g., audio driver lists, `-device` sub-options).
- Use the established colour helpers (`log`, `warn`, `die`, `heading`) already defined in both
  scripts — do not add raw `echo` for user-facing messages.
- Prefer `mapfile -t array < <(...)` over `array=($(...))` for word-splitting safety.
- Quote all variable expansions; use `[[ … ]]` (not `[ … ]`) for conditionals.
- Do not introduce new external runtime dependencies without updating the dependency lists in
  both `build_qemu.sh` (`check_deps`) and `README.md`.

## Build system

- QEMU is built via `bash build_qemu.sh [download|patch|configure|build|install|all]`.
- On x86 hosts the configure step auto-expands to **all** `qemu-system-*` softmmu targets
  found under `qemu-9.2.0/configs/targets/`.
- Host CFLAGS on x86 always include `-march=x86-64 -mtune=westmere -mno-avx -mno-avx2`
  (override via `QEMU_X86_COMPAT_CFLAGS`).
- Extra configure flags live in `EXTRA_CONFIG_FLAGS` inside `build_qemu.sh`; add new
  `--enable-*` options there and document the matching build dependency in `README.md`.

## Patch management

- Patches go in subdirectory `patches/<category>/` named `NNNN-short-description.patch`.
- Apply order: `general/` → `m68k/` → `ppc/` → `sparc/` → root `patches/`.
- All patches must be idempotent (the `apply_patches` function checks `git apply --reverse`
  before applying).
- Document every new patch in `patches/README.md` with its upstream commit SHA and the
  QEMU stable branch it was cherry-picked from.

## VM launcher (vm_assist.sh)

- Each platform preset is a self-contained function named `launch_<platform>`.
- Interactive prompts use the `ask` / `ask_ram_size` helpers — never raw `read`.
- RAM input must go through `ask_ram_size` (validates plain MiB or M/G suffix).
- QEMU binary resolution goes through `qemu_bin <name>` (checks `QEMU_BIN_DIR` first,
  then system `PATH`).
- Firmware/ROM images > 1 MiB must be attached via `-drive if=pflash` (not `-bios`).
- Repeated `-device` entries are the correct way to expose multi-screen setups.

## Supported guest platforms

| Platform | QEMU binary | Machine | CPU examples |
|---|---|---|---|
| MacOS 68k (System 7 – 8.1) | `qemu-system-m68k` | `q800` | `m68040` |
| MacOS PPC (7.5.2 – 9.2.2) | `qemu-system-ppc` | `mac99,via=pmu` | `601`, `604`, `7455` |
| Atari ST/STE/TT/Falcon | Hatari (preferred) or `qemu-system-m68k` | — | — |
| Amiga / AROS | FS-UAE or `qemu-system-m68k` | `virt` | `m68040` |
| HaikuOS | `qemu-system-x86_64` | `q35` | `host` (KVM) |
| Solaris x86 | `qemu-system-i386` | `pc` | `pentium3` |
| Solaris SPARC | `qemu-system-sparc64` | `sun4u` | `TI UltraSparc IIi` |
| Windows XP | `qemu-system-i386` | `pc` | `pentium3` |
| OpenStep | `qemu-system-i386` | `pc` | `pentium` |

## Key environment variables

| Variable | Default | Notes |
|---|---|---|
| `QEMU_VERSION` | `9.2.0` | |
| `QEMU_INSTALL_PREFIX` | `~/.local/qemu-retro` | |
| `QEMU_X86_COMPAT_CFLAGS` | `-march=x86-64 -mtune=westmere -mno-avx -mno-avx2` | x86 host only |
| `JOBS` | `nproc` | |
| `QEMU_PREFIX` | `~/.local/qemu-retro` | vm_assist.sh |
| `VM_IMAGE_DIR` | `~/vm_assistant/images` | |
| `VM_SHARED_DIR` | `~/vm_assistant/shares` | |
| `VM_LOG_DIR` | `~/vm_assistant/logs` | |
| `DEFAULT_DISPLAY` | `sdl` | sdl/gtk/vnc/curses/none |
| `DEFAULT_MACOS_SHARE_DIR` | `~/vm_assistant/shares` | host share for classic Mac guests |
| `DEFAULT_GDB_BRIDGE_PORT` | `2346` | host-side bridge port |
| `DEFAULT_QEMU_GDB_PORT` | `1234` | QEMU GDB stub port |

## What to avoid

- Do **not** use AVX/AVX2 intrinsics or compiler flags targeting newer than Westmere on the host build.
- Do **not** commit guest disk images, ROM dumps, or proprietary firmware files.
- Do **not** modify `qemu-9.2.0/` source directly — use the `patches/` mechanism instead.
- Do **not** remove or skip the `set -euo pipefail` guard in any shell script.
- Do **not** use `sudo` inside the build or launcher scripts — document privilege requirements in `README.md` only.
- Keep `COPILOT-CONTEXT.MD` updated at the end of each working session with the active objective, modified files, validation steps run, and open follow-up tasks.
