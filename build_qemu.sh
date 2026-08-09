#!/usr/bin/env bash
# =============================================================================
# build_qemu.sh — Custom QEMU build script
# Targets: retro defaults (m68k, ppc, ppc64, i386, x86_64, sparc, sparc64)
#          x86 hosts auto-expand to all qemu-system-* targets, without AVX/AVX2
# Retro platforms: MacOS 7.1-9.2.2 (PPC/68k), Atari ST (68k),
#                  Amiga (68k), HaikuOS (x86/x86_64), Solaris family (x86/SPARC)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — override with environment variables if desired
# ---------------------------------------------------------------------------
QEMU_VERSION="${QEMU_VERSION:-9.2.0}"
QEMU_SRC_DIR="${QEMU_SRC_DIR:-$(pwd)/qemu-${QEMU_VERSION}}"
QEMU_BUILD_DIR="${QEMU_BUILD_DIR:-${QEMU_SRC_DIR}/build}"
QEMU_INSTALL_PREFIX="${QEMU_INSTALL_PREFIX:-${HOME}/.local/qemu-retro}"
QEMU_TARBALL="qemu-${QEMU_VERSION}.tar.xz"
QEMU_TARBALL_URL="https://download.qemu.org/${QEMU_TARBALL}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"
# Patches directory — .patch files are applied in lexicographic order
PATCHES_DIR="${PATCHES_DIR:-$(cd "$(dirname "$0")" && pwd)/patches}"
QEMU_X86_COMPAT_CFLAGS="${QEMU_X86_COMPAT_CFLAGS:--march=x86-64 -mtune=westmere -mno-avx -mno-avx2}"

# Default target list — retro-relevant system emulators
QEMU_SOFTMMU_TARGETS=(
    m68k-softmmu       # Motorola 68000 family (Amiga, Atari ST, Mac 68k)
    ppc-softmmu        # PowerPC 32-bit (MacOS 7.5–9.2.2 on Old World / New World)
    ppc64-softmmu      # PowerPC 64-bit
    i386-softmmu       # x86 32-bit (HaikuOS, DOS, early Windows)
    x86_64-softmmu     # x86 64-bit (HaikuOS, modern Linux)
    sparc-softmmu      # SPARC 32-bit (legacy Solaris where applicable)
    sparc64-softmmu    # SPARC 64-bit (Solaris / sun4u)
)

# User-mode emulation (Linux host only)
QEMU_LINUX_USER_TARGETS=(
    m68k-linux-user
    ppc-linux-user
    ppc64-linux-user
    i386-linux-user
    x86_64-linux-user
)

# Optional extra configure flags (append as needed)
EXTRA_CONFIG_FLAGS=(
    --enable-slirp          # built-in SLIRP networking
    --enable-vnc            # VNC display
    --enable-sdl            # SDL2 display
    --enable-gtk            # GTK display
    --enable-curses         # curses/text display
    --enable-audio-drv-list=alsa,pa,sdl,coreaudio,dsound
    --enable-bzip2
    --enable-lzo
    --enable-snappy
    --enable-libssh
    --enable-usb-redir
    --enable-smartcard
    --enable-opengl
    --enable-virtfs         # VirtFS / 9P host filesystem sharing
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
log()  { printf '\033[1;32m[build_qemu]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[build_qemu] WARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[build_qemu] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

host_is_x86() {
    case "$(uname -m)" in
        x86_64|amd64|i386|i486|i586|i686) return 0 ;;
        *) return 1 ;;
    esac
}

list_all_softmmu_targets() {
    local targets_dir="${QEMU_SRC_DIR}/configs/targets"
    [[ -d "${targets_dir}" ]] || return 1

    find "${targets_dir}" -maxdepth 1 -type f -name '*-softmmu.mak' \
        -exec sh -c 'for path do basename "$path" .mak; done' sh {} + \
        | sort
}

resolve_qemu_targets() {
    local targets=()

    if host_is_x86; then
        if mapfile -t targets < <(list_all_softmmu_targets) && [[ ${#targets[@]} -gt 0 ]]; then
            log "x86 host detected — enabling all qemu-system-* targets."
        else
            warn "Could not enumerate all softmmu targets from ${QEMU_SRC_DIR}; falling back to retro defaults."
            targets=("${QEMU_SOFTMMU_TARGETS[@]}")
        fi
    else
        targets=("${QEMU_SOFTMMU_TARGETS[@]}")
    fi

    if [[ "$(uname -s)" == "Linux" ]]; then
        targets+=("${QEMU_LINUX_USER_TARGETS[@]}")
    fi

    printf '%s\n' "${targets[@]}"
}

configure_x86_compat() {
    host_is_x86 || return 0
    [[ -n "${QEMU_X86_COMPAT_CFLAGS}" ]] || return 0

    export CFLAGS="${CFLAGS:+${CFLAGS} }${QEMU_X86_COMPAT_CFLAGS}"
    export CXXFLAGS="${CXXFLAGS:+${CXXFLAGS} }${QEMU_X86_COMPAT_CFLAGS}"
    log "Using x86 compatibility flags: ${QEMU_X86_COMPAT_CFLAGS}"
}

check_deps() {
    local missing=()
    local deps=(git curl tar make ninja pkg-config python3 gcc g++ flex bison)
    for d in "${deps[@]}"; do
        command -v "$d" &>/dev/null || missing+=("$d")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing build dependencies: ${missing[*]}"
        warn "On Debian/Ubuntu:  sudo apt-get install build-essential git ninja-build pkg-config python3-pip libglib2.0-dev libpixman-1-dev libsdl2-dev libgtk-3-dev libvte-2.91-dev libslirp-dev libbz2-dev liblzo2-dev libsnappy-dev libssh-dev libusbredirhost-dev libcacard-dev libepoxy-dev libvirglrenderer-dev libncurses-dev"
        warn "On macOS (Homebrew): brew install ninja pkg-config glib pixman sdl2 gtk+3 libslirp"
        warn "On Fedora/RHEL:    sudo dnf install @development-tools ninja-build glib2-devel pixman-devel SDL2-devel gtk3-devel slirp-devel bzip2-devel lzo-devel snappy-devel libssh-devel usbredir-devel openssl-devel"
        die "Install the missing dependencies before continuing."
    fi
}

download_qemu() {
    if [[ -d "${QEMU_SRC_DIR}" ]]; then
        # If it is a git submodule working tree, make sure it is initialised
        if [[ -f "${QEMU_SRC_DIR}/.git" || -d "${QEMU_SRC_DIR}/.git" ]]; then
            log "Source directory already exists (submodule): ${QEMU_SRC_DIR}"
            # Initialise submodule in case it was cloned without --recurse-submodules
            local repo_root
            repo_root="$(git -C "${QEMU_SRC_DIR}" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
            if [[ -n "${repo_root}" ]]; then
                log "Initialising git submodule …"
                git -C "${repo_root}" submodule update --init -- "${QEMU_SRC_DIR}"
            fi
        else
            log "Source directory already exists: ${QEMU_SRC_DIR}"
        fi
        return 0
    fi
    log "Downloading QEMU ${QEMU_VERSION} from ${QEMU_TARBALL_URL} …"
    curl -fL --progress-bar -o "/tmp/${QEMU_TARBALL}" "${QEMU_TARBALL_URL}"
    log "Extracting tarball …"
    tar -xf "/tmp/${QEMU_TARBALL}" -C "$(dirname "${QEMU_SRC_DIR}")"
    rm -f "/tmp/${QEMU_TARBALL}"
}

apply_patches() {
    [[ -d "${QEMU_SRC_DIR}" ]] || die "Source directory not found: ${QEMU_SRC_DIR}. Run '$(basename "$0") download' first."

    if [[ ! -d "${PATCHES_DIR}" ]]; then
        log "No patches directory found at ${PATCHES_DIR} — skipping patch step."
        return 0
    fi

    # Collect .patch files in deterministic order: general → m68k → ppc → sparc → root
    local subdirs=("general" "m68k" "ppc" "sparc")
    local all_patches=()
    for sub in "${subdirs[@]}"; do
        local dir="${PATCHES_DIR}/${sub}"
        [[ -d "${dir}" ]] || continue
        while IFS= read -r -d '' p; do
            all_patches+=("${p}")
        done < <(find "${dir}" -maxdepth 1 -name "*.patch" -print0 | sort -z)
    done
    # Also pick up any .patch files placed directly in PATCHES_DIR root
    while IFS= read -r -d '' p; do
        all_patches+=("${p}")
    done < <(find "${PATCHES_DIR}" -maxdepth 1 -name "*.patch" -print0 | sort -z)

    if [[ ${#all_patches[@]} -eq 0 ]]; then
        log "No .patch files found in ${PATCHES_DIR} — nothing to apply."
        return 0
    fi

    log "Applying ${#all_patches[@]} patch(es) to ${QEMU_SRC_DIR} …"
    local applied=0 skipped=0
    for patch in "${all_patches[@]}"; do
        local name
        name="$(basename "${patch}")"
        # Skip already-applied patches (idempotent re-runs)
        if git -C "${QEMU_SRC_DIR}" apply --check --reverse "${patch}" &>/dev/null; then
            log "  [already applied] ${name}"
            (( skipped++ )) || true
            continue
        fi
        if git -C "${QEMU_SRC_DIR}" apply --check "${patch}" &>/dev/null; then
            git -C "${QEMU_SRC_DIR}" apply "${patch}" \
                && log "  [applied] ${name}" \
                || die "Failed to apply patch: ${patch}"
            (( applied++ )) || true
        else
            warn "  [skipped — does not apply cleanly] ${name}"
            warn "  Run: git -C '${QEMU_SRC_DIR}' apply --reject '${patch}'"
            (( skipped++ )) || true
        fi
    done
    log "Patches: ${applied} applied, ${skipped} skipped."
}

configure_qemu() {
    log "Configuring QEMU …"
    [[ -d "${QEMU_SRC_DIR}" ]] || die "Source directory not found: ${QEMU_SRC_DIR}. Run '$(basename "$0") download' first."
    mkdir -p "${QEMU_BUILD_DIR}"
    cd "${QEMU_BUILD_DIR}"

    local target_list
    local resolved_targets=()
    mapfile -t resolved_targets < <(resolve_qemu_targets)
    target_list=$(printf '%s,' "${resolved_targets[@]}"); target_list="${target_list%,}"
    configure_x86_compat

    "${QEMU_SRC_DIR}/configure" \
        --prefix="${QEMU_INSTALL_PREFIX}" \
        --target-list="${target_list}" \
        "${EXTRA_CONFIG_FLAGS[@]}" \
        2>&1 | tee configure.log || {
            warn "Some optional features were not found; retrying with minimal flags …"
            "${QEMU_SRC_DIR}/configure" \
                --prefix="${QEMU_INSTALL_PREFIX}" \
                --target-list="${target_list}" \
                2>&1 | tee configure.log
        }
}

build_qemu() {
    log "Building QEMU with ${JOBS} parallel jobs …"
    cd "${QEMU_BUILD_DIR}"
    ninja -j"${JOBS}" 2>&1 | tee build.log
}

install_qemu() {
    log "Installing QEMU to ${QEMU_INSTALL_PREFIX} …"
    cd "${QEMU_BUILD_DIR}"
    ninja install 2>&1 | tee install.log
    log "Done. Add ${QEMU_INSTALL_PREFIX}/bin to your PATH:"
    log "  export PATH=\"${QEMU_INSTALL_PREFIX}/bin:\$PATH\""
}

show_help() {
    cat <<EOF
Usage: $(basename "$0") [COMMAND]

Commands:
  download    Download and extract QEMU ${QEMU_VERSION} source (no-op if submodule present)
  patch       Apply upstream backport patches from ${PATCHES_DIR}
  configure   Run ./configure with target-selection flags
  build       Compile QEMU
  install     Install QEMU to ${QEMU_INSTALL_PREFIX}
  all         download → patch → configure → build → install  (default)
  help        Show this help

Environment variables:
  QEMU_VERSION          QEMU version to build      (default: ${QEMU_VERSION})
  QEMU_SRC_DIR          Path to source tree        (default: ./qemu-\${QEMU_VERSION})
  QEMU_BUILD_DIR        Path to build directory    (default: \${QEMU_SRC_DIR}/build)
  QEMU_INSTALL_PREFIX   Installation prefix        (default: \${HOME}/.local/qemu-retro)
  PATCHES_DIR           Directory of .patch files  (default: ./patches)
  QEMU_X86_COMPAT_CFLAGS x86 host C/C++ flags      (default: ${QEMU_X86_COMPAT_CFLAGS})
  JOBS                  Parallel build jobs        (default: nproc)

Enabled targets:
  Retro softmmu defaults:
$(printf '    %s\n' "${QEMU_SOFTMMU_TARGETS[@]}")
  Linux-user targets on Linux:
$(printf '    %s\n' "${QEMU_LINUX_USER_TARGETS[@]}")
  On x86 hosts, configure auto-expands softmmu targets to every qemu-system-* target.

Extra configure flags:
$(printf '  %s\n' "${EXTRA_CONFIG_FLAGS[@]}")
EOF
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
    local cmd="${1:-all}"
    case "${cmd}" in
        download)  check_deps; download_qemu ;;
        patch)     apply_patches ;;
        configure) configure_qemu ;;
        build)     build_qemu ;;
        install)   install_qemu ;;
        all)
            check_deps
            download_qemu
            apply_patches
            configure_qemu
            build_qemu
            install_qemu
            ;;
        help|--help|-h) show_help ;;
        *) die "Unknown command '${cmd}'. Run '$(basename "$0") help' for usage." ;;
    esac
}

main "$@"
