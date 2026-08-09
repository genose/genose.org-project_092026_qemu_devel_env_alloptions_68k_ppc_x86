# genose.org — Custom QEMU Retro Development Environment

Custom QEMU build and VM-assist launcher for retro programming.

**Supported target architectures:** Motorola 68k · PowerPC (32/64-bit) · x86 / x86_64 · SPARC / SPARC64

**Supported guest platforms:**
- Apple MacOS 7.1 – 9.2.2 (68k and PowerPC, Old World & New World)
- Atari ST / STE / TT / Falcon (68k)
- Commodore Amiga / AROS (68k)
- HaikuOS (i386 / x86_64)
- Solaris family (x86 and SPARC)
- Windows XP (i386)
- OpenStep (i386)

---

## Repository layout

```
build_qemu.sh        Custom QEMU build script (download → configure → build → install)
vm_assist.sh         Interactive VM-assist launcher with per-platform menus
vm-configs/
  macos-68k.env      MacOS 68k configuration reference (System 7.x / Mac OS 8.x)
  macos-ppc.env      MacOS PPC configuration reference (Mac OS 7.5.2 – 9.2.2)
  atari.env          Atari ST/STE/TT/Falcon configuration reference
  amiga.env          Amiga / AROS configuration reference
  haiku.env          HaikuOS i386/x86_64 configuration reference
  solaris-x86.env    Solaris x86 configuration reference
  solaris-sparc.env  Solaris SPARC configuration reference
  windows-xp.env     Windows XP i386 configuration reference
  openstep.env       OpenStep x86 configuration reference
```

---

## 1. Build QEMU

`build_qemu.sh` downloads, configures, and builds QEMU with all retro-relevant
targets enabled (`m68k`, `ppc`, `ppc64`, `i386`, `x86_64`, `sparc`, `sparc64`).

```bash
# Full build (download → configure → build → install)
bash build_qemu.sh

# Individual steps
bash build_qemu.sh download
bash build_qemu.sh configure
bash build_qemu.sh build
bash build_qemu.sh install
```

### Key environment variables

| Variable | Default | Description |
|---|---|---|
| `QEMU_VERSION` | `9.2.0` | QEMU version to build |
| `QEMU_INSTALL_PREFIX` | `~/.local/qemu-retro` | Installation prefix |
| `JOBS` | `nproc` | Parallel build jobs |

After installation, add the binary directory to your `PATH`:

```bash
export PATH="$HOME/.local/qemu-retro/bin:$PATH"
```

### Build dependencies

**Debian / Ubuntu:**
```bash
sudo apt-get install build-essential git ninja-build pkg-config python3-pip \
  libglib2.0-dev libpixman-1-dev libsdl2-dev libgtk-3-dev libvte-2.91-dev \
  libslirp-dev libbz2-dev liblzo2-dev libsnappy-dev libssh-dev \
  libusbredirhost-dev libcacard-dev libepoxy-dev libncurses-dev
```

**macOS (Homebrew):**
```bash
brew install ninja pkg-config glib pixman sdl2 gtk+3 libslirp
```

**Fedora / RHEL:**
```bash
sudo dnf install @development-tools ninja-build glib2-devel pixman-devel \
  SDL2-devel gtk3-devel slirp-devel bzip2-devel lzo-devel snappy-devel \
  libssh-devel usbredir-devel openssl-devel
```

---

## 2. Launch VMs with vm_assist.sh

`vm_assist.sh` provides an interactive menu for launching VMs and managing
disk images.

```bash
# Interactive menu
bash vm_assist.sh

# Direct platform launch (non-interactive)
bash vm_assist.sh macos-68k
bash vm_assist.sh macos-ppc
bash vm_assist.sh atari
bash vm_assist.sh amiga
bash vm_assist.sh haiku
bash vm_assist.sh solaris-x86
bash vm_assist.sh solaris-sparc
bash vm_assist.sh windows-xp
bash vm_assist.sh openstep
bash vm_assist.sh custom

# Disk image management
bash vm_assist.sh images
```

### Key environment variables

| Variable | Default | Description |
|---|---|---|
| `QEMU_PREFIX` | `~/.local/qemu-retro` | Custom QEMU installation |
| `VM_IMAGE_DIR` | `~/vm-images` | Root directory for disk images |
| `VM_SHARED_DIR` | `~/vm-shared` | Host directory shared with VMs (9P) |
| `VM_LOG_DIR` | `~/vm-logs` | Session log directory |
| `DEFAULT_DISPLAY` | `sdl` | Display backend (sdl/gtk/vnc/curses/none) |
| `DEFAULT_MACOS_SHARE_DIR` | `/tmp/volatile_hd` | Host export path prepared for classic Mac guests |
| `DEFAULT_GDB_BRIDGE_PORT` | `2345` | Default guest gdbserver bridge port |
| `DEFAULT_QEMU_GDB_PORT` | `1234` | Default QEMU GDB stub port |

---

## 3. Platform notes

### MacOS 68k (System 7.1 – Mac OS 8.1)

- **QEMU machine:** `q800` (Quadra 800 — Motorola 68040)
- **RAM:** up to 256 MiB
- Requires a MacOS 68k hard disk image (or installation CD-ROM).
- `vm_assist.sh` can prepare dual-display, clipboard exchange, `/tmp/volatile_hd`
  host-share notes, Netatalk/AFP and TLS proxy endpoints, and guest GDB bridging.
- The launcher now lets you pick across the common 68k family CPU models
  (`m68000` → `m68060`) when you need a different target profile.

```bash
qemu-system-m68k -machine q800 -cpu m68040 -m 128 \
  -display sdl -audiodev sdl,id=snd0 \
  -device nubus-macfb \
  -nic user,model=dp83932 \
  -rtc base=localtime \
  -hda ~/vm-images/macos-68k/macos-hdd.qcow2
```

### MacOS PPC (Mac OS 7.5.2 – 9.2.2)

- **QEMU machine:** `mac99,via=pmu` (PowerMac G3/G4)
- Uses OpenBIOS by default; Old World ROMs require a physical ROM dump.
- The launcher now exposes `601`, `604`, and `7455` (`G4`) CPU selections.
- `vm-configs/macos-ppc.env` documents the default host integration endpoints:
  AFP/Netatalk on `10.0.2.2:548`, TLS proxy on `10.0.2.2:8443`,
  clipboard exchange via `/tmp/volatile_hd/clipboard`, and host-side setup notes
  for both MacPorts and Homebrew.

```bash
qemu-system-ppc -machine mac99,via=pmu -cpu G4 -m 256 \
  -display sdl -audiodev sdl,id=snd0 \
  -device VGA,vgamem_mb=16 \
  -device secondary-vga,vgamem_mb=16 \
  -device usb-kbd -device usb-mouse \
  -nic user,model=sungem \
  -rtc base=localtime \
  -hda ~/vm-images/macos-ppc/macos-hdd.qcow2
```

### Atari ST / STE / TT / Falcon (68k)

For the most accurate Atari emulation use **Hatari** (`sudo apt install hatari`).
`vm_assist.sh` auto-detects and prefers Hatari when it is installed.

A free TOS ROM replacement (**EmuTOS**) is available at
<https://emutos.sourceforge.io/> — no proprietary firmware required.

```bash
hatari --machine ste --tos ~/vm-images/atari/emutos.img \
       --harddrive ~/vm-images/atari/harddrive
```

### Amiga / AROS (68k)

QEMU does not emulate Amiga custom chips. Two options are supported:

1. **AROS** (open-source AmigaOS-compatible) via `qemu-system-m68k`
2. **FS-UAE** (`sudo apt install fs-uae`) — most accurate, requires Kickstart ROMs

The QEMU-backed 68k launchers now expose the common CPU family options from
`m68000` through `m68060`.

```bash
# AROS via QEMU
qemu-system-m68k -machine virt -cpu m68040 -m 128 \
  -display sdl -audiodev sdl,id=snd0 \
  -nic user -rtc base=localtime \
  -hda ~/vm-images/amiga-aros/aros-disk.qcow2
```

### HaikuOS (i386 / x86_64)

Download from <https://www.haiku-os.org/get-haiku>.
KVM acceleration is used automatically when `/dev/kvm` is available.

```bash
qemu-system-x86_64 -machine q35 -cpu host -m 1024 -smp 2 \
  -enable-kvm -display sdl -audiodev sdl,id=snd0 \
  -device VGA,vgamem_mb=32 \
  -device usb-ehci -device usb-kbd -device usb-mouse \
  -nic user,model=e1000 -rtc base=localtime \
  -virtfs local,path=~/vm-shared,mount_tag=shared,security_model=mapped-xattr \
  -hda ~/vm-images/haiku-x86_64/haiku-hdd.qcow2
```

### Solaris family

- **x86 preset:** `bash vm_assist.sh solaris-x86`
- **SPARC preset:** `bash vm_assist.sh solaris-sparc`
- SPARC guests require a QEMU build that includes `qemu-system-sparc64`.
- Supply your own installation media and target disk images under
  `~/vm-images/solaris-x86/` or `~/vm-images/solaris-sparc/`.

```bash
qemu-system-i386 -machine pc -cpu pentium3 -m 1024 -smp 2 \
  -display sdl -audiodev sdl,id=snd0 \
  -device VGA,vgamem_mb=16 \
  -device usb-kbd -device usb-mouse \
  -nic user,model=e1000 \
  -rtc base=localtime \
  -hda ~/vm-images/solaris-x86/solaris-hdd.qcow2
```

```bash
qemu-system-sparc64 -machine sun4u -cpu "TI UltraSparc IIi" -m 1024 \
  -display sdl -audiodev sdl,id=snd0 \
  -device VGA,vgamem_mb=16 \
  -nic user,model=sunhme \
  -rtc base=localtime \
  -hda ~/vm-images/solaris-sparc/solaris-sparc-hdd.qcow2
```

### Windows XP (i386)

- **Preset:** `bash vm_assist.sh windows-xp`
- Uses a conservative `pentium3` + `rtl8139` profile for broad guest-driver support.
- The launcher can optionally expose a host SMB share and guest-facing GDB bridge.
- Supply your own install media and disk images under `~/vm-images/windows-xp/`.

```bash
qemu-system-i386 -machine pc -cpu pentium3 -m 1024 -smp 2 \
  -display sdl -audiodev sdl,id=snd0 \
  -device VGA,vgamem_mb=16 \
  -device usb-ehci -device usb-kbd -device usb-mouse \
  -nic user,model=rtl8139,smb=~/vm-shared \
  -rtc base=localtime \
  -hda ~/vm-images/windows-xp/windows-xp-hdd.qcow2
```

### OpenStep (i386)

- **Preset:** `bash vm_assist.sh openstep`
- Uses a conservative `pentium` + `ne2k_pci` profile for older x86 compatibility.
- Supply your own install media and disk images under `~/vm-images/openstep/`.

```bash
qemu-system-i386 -machine pc -cpu pentium -m 256 \
  -display sdl -audiodev sdl,id=snd0 \
  -device VGA,vgamem_mb=8 \
  -nic user,model=ne2k_pci \
  -rtc base=localtime \
  -hda ~/vm-images/openstep/openstep-hdd.qcow2
```

---

## 4. Debugging, forwarding, and host integration

`vm_assist.sh` now exposes runtime options across the relevant presets for:

- guest GDB/gdbserver TCP bridging for in-guest deployment debugging
- QEMU GDB stub exposure on a dedicated host port
- TCP service forwards for guest services
- optional SMB host exports for compatible x86 guests
- optional 9P/VirtFS sharing for guests that support it
- optional second display adapters in the presets that can use them

For classic Mac guests:

- host share default: `/tmp/volatile_hd`
- clipboard exchange path: `/tmp/volatile_hd/clipboard`
- default AFP/Netatalk endpoint: `10.0.2.2:548`
- default TLS proxy endpoint: `10.0.2.2:8443`

Classic Mac OS does **not** natively consume QEMU 9P sharing, so host-side
Netatalk/AFP or similar network services remain the preferred file-exchange path.

---

## 5. Disk image management

`vm_assist.sh` includes a built-in image management menu (option 11 or
`bash vm_assist.sh images`), providing:

- Create new blank qcow2 image
- Convert between formats (raw ↔ qcow2 ↔ vmdk ↔ vdi)
- Resize existing images
- Show image info

You can also use `qemu-img` directly:

```bash
# Create a new 2 GiB qcow2 image
qemu-img create -f qcow2 ~/vm-images/macos-ppc/macos-hdd.qcow2 2G

# Convert from raw to qcow2
qemu-img convert -p -O qcow2 disk.img disk.qcow2

# Resize (add 1 GiB)
qemu-img resize disk.qcow2 +1G
```

---

## 6. Guest media / firmware constraints

- **MacOS 68k / PPC:** bring your own legally obtained hard disk images,
  install CDs, and any required ROM dumps; Old World ROMs are not redistributable.
- **Solaris x86 / SPARC:** bring your own Solaris or illumos-family install media
  and target disk images; SPARC installs require the SPARC system emulator target.
- **Windows XP:** bring your own ISO/media and license; this repository does not
  ship guest drivers, service packs, or product keys.
- **OpenStep:** bring your own install media and disk image; best compatibility is
  usually with conservative emulated devices and modest RAM.

---

## License

This project is provided as-is for educational and retro-computing purposes.
QEMU itself is distributed under the GNU GPL v2+.
Vintage operating system images, ROMs, and firmware are subject to their own
respective licenses — ensure you have the right to use them.
