# COPILOT CONTEXT

## Repository
- Name: `genose/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86`
- Local path: `/home/runner/work/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86`

## Current Task Snapshot
- Request: finalize and validate PR #3 (review fixes for PR #2 merge).
- Status: code review passed (no comments), CodeQL skipped (trivial changes), PR ready for merge.

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
