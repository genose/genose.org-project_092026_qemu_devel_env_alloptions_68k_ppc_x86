# COPILOT CONTEXT

## Repository
- Name: `genose/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86`
- Local path: `/home/runner/work/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86`

## Current Task Snapshot
- Request: resolve conflicts between branch `copilot/pr-2-review-feedback` and `origin/main`.
- Status: conflicts resolved and committed.
  - `build_qemu.sh`: two conflict regions resolved (SPICE comment + macOS/Fedora dep hints — kept correct package names `spice-gtk` / `spice-server-devel`).
  - `COPILOT-CONTEXT.MD`: kept branch version (main had deleted it).
  - `vm_assist.sh` / `README.md`: merged cleanly; branch versions retained (SPICE deps, shellcheck directive, safer printf).

## Project Snapshot
- Purpose: custom QEMU retro development environment with build and VM-assist tooling.
- Main scripts:
  - `build_qemu.sh` (configure/build/install QEMU)
  - `vm_assist.sh` (interactive and preset VM launcher)
- Important directories:
  - `patches/` (upstream backport patch sets by architecture)
  - `vm-configs/` (platform configuration references)
  - `qemu-9.2.0/` (QEMU source submodule)

## Known Commands (from README)
- Build flow:
  - `bash build_qemu.sh`
  - `bash build_qemu.sh configure`
  - `bash build_qemu.sh build`
  - `bash build_qemu.sh install`
- VM launcher:
  - `bash vm_assist.sh`
  - `bash vm_assist.sh <preset>`

## Next Enhancement Notes
- Keep this file updated with:
  - active objective
  - modified files
  - validation steps run
  - open questions and follow-up tasks
