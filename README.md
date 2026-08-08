# genose.org — Custom QEMU Retro Development Environment

Custom QEMU build and VM-assist launcher for retro programming.

**Supported target architectures:** Motorola 68k · PowerPC (32/64-bit) · x86 / x86_64

**Supported guest platforms:**
- Apple MacOS 7.1 – 9.2.2 (68k and PowerPC, Old World & New World)
- Atari ST / STE / TT / Falcon (68k)
- Commodore Amiga / AROS (68k)
- HaikuOS (i386 / x86_64)

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
```

---

## 1. Build QEMU

`build_qemu.sh` downloads, configures, and builds QEMU with all retro-relevant
targets enabled (`m68k`, `ppc`, `ppc64`, `i386`, `x86_64`).

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

---

## 3. Platform notes

### MacOS 68k (System 7.1 – Mac OS 8.1)

- **QEMU machine:** `q800` (Quadra 800 — Motorola 68040)
- **RAM:** up to 256 MiB
- Requires a MacOS 68k hard disk image (or installation CD-ROM).

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

```bash
qemu-system-ppc -machine mac99,via=pmu -cpu G4 -m 256 \
  -display sdl -audiodev sdl,id=snd0 \
  -device VGA,vgamem_mb=16 \
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

---

## 4. Disk image management

`vm_assist.sh` includes a built-in image management menu (option 7 or
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

## License

This project is provided as-is for educational and retro-computing purposes.
QEMU itself is distributed under the GNU GPL v2+.
Vintage operating system images, ROMs, and firmware are subject to their own
respective licenses — ensure you have the right to use them.
