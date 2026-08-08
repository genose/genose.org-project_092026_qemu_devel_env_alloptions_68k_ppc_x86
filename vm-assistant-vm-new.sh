#!/bin/bash
# =============================================================================
# VM Assistant - Minimal version with multi-screen support
# PowerPC/Mac OS 9 multi-screen methods
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.vm-assistant"
VM_DIR="$CONFIG_DIR/vms"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Function to test if a QEMU device exists
qemu_device_exists() {
    local device="$1"
    qemu-system-ppc -device help 2>/dev/null | grep -q "$device" && return 0 || return 1
}

start_qemu_vm() {
    local vm_name=$1
    local vm_dir="$VM_DIR/$vm_name"
    local vm_config="$vm_dir/config"

    if [ ! -d "$vm_dir" ]; then
        log_error "VM not found: $vm_name"
        return 1
    fi

    if [ ! -f "$vm_config" ]; then
        log_error "VM config not found: $vm_config"
        return 1
    fi

    source "$vm_config" || return 1

    log_info "Starting VM QEMU: $vm_name"

    # Default values
    local arch="${arch:-G4}"
    local machine="${machine:-mac99}"
    local cpu_type="${cpu_type:-7455}"
    local ram="${ram:-768}"
    local cpu="${cpu:-1}"
    local display="${display:-cocoa}"
    local num_screens="${num_screens:-1}"
    local disk="${disk:-}"
    local iso="${iso:-}"
    local share_dir="${share_dir:-/tmp/volatile_hd}"
    local network_mode="${network_mode:-nat}"
    local via="${via:-cuda}"
    local multi_screen_method="${multi_screen_method:-auto}"

    # Build QEMU args
    local qemu_args=()
    qemu_args+=("qemu-system-ppc")
    qemu_args+=("-L" "/Users/xenon/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu")
    qemu_args+=("-m" "${ram}M")
    qemu_args+=("-smp" "$cpu")

    # Network
    case "$network_mode" in
        "nat"|"")
            qemu_args+=("-device" "sungem,mac=$(openssl rand -hex 6),netdev=net0")
            qemu_args+=("-netdev" "vmnet-shared,id=net0")
            ;;
    esac

    # Display
    case "$display" in
        "cocoa")
            qemu_args+=("-display" "cocoa")
            ;;
        "none")
            qemu_args+=("-nographic")
            ;;
        *)
            qemu_args+=("-display" "cocoa")
            ;;
    esac

    # File sharing
    if [ -d "$share_dir" ]; then
        qemu_args+=("-fsdev" "local,security_model=mapped,id=fsdev0,path=$share_dir")
    fi

    # PowerPC specific
    case "$arch" in
        "G4"|"604ev"|"ppc")
            local ppc_machine="${machine:-mac99}"
            if [ "$arch" = "604ev" ] || [ "$arch" = "ppc" ]; then
                ppc_machine="g3beige"
            fi
            qemu_args+=("-machine" "${ppc_machine},via=${via}")
            qemu_args+=("-cpu" "${cpu_type}")
            qemu_args+=("-accel" "tcg,tb-size=128")

            # Multi-screen methods for PowerPC/Mac OS 9
            if [ "$num_screens" -gt 1 ]; then
                case "$multi_screen_method" in
                    "graphic-engine")
                        qemu_args+=("-device" "graphic-drawing-engine,heads=${num_screens}")
                        log_info "Multi-screen: graphic-drawing-engine method (heads=${num_screens})"
                        ;;
                    "dual-pci-vga")
                        qemu_args+=("-prom-env" "vga-ndrv?=true")
                        qemu_args+=("-g" "1024x768x32")
                        qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video0,xres=1024,yres=768")
                        for (( screen_num=1; screen_num<num_screens; screen_num++ )); do
                            local screen_id="video$screen_num"
                            qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=$screen_id,xres=1024,yres=768")
                        done
                        log_info "Multi-screen: Dual-PCI VGA method (${num_screens} screens)"
                        ;;
                    "auto"|"")
                        if qemu_device_exists "graphic-drawing-engine"; then
                            qemu_args+=("-device" "graphic-drawing-engine,heads=${num_screens}")
                            log_info "Multi-screen: graphic-drawing-engine detected (heads=${num_screens})"
                        else
                            qemu_args+=("-prom-env" "vga-ndrv?=true")
                            qemu_args+=("-g" "1024x768x32")
                            qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=video0,xres=1024,yres=768")
                            for (( screen_num=1; screen_num<num_screens; screen_num++ )); do
                                local screen_id="video$screen_num"
                                qemu_args+=("-device" "VGA,edid=on,vgamem_mb=64,id=$screen_id,xres=1024,yres=768")
                            done
                            log_info "Multi-screen: Dual-PCI VGA method (graphic-drawing-engine not available)"
                        fi
                        ;;
                esac
            else
                qemu_args+=("-device" "VGA,vgamem_mb=16,edid=on")
            fi

            # Storage
            if [ -n "$disk" ] && [ -f "$disk" ]; then
                qemu_args+=("-drive" "if=none,media=disk,id=drive0,file=$disk,format=qcow2")
                qemu_args+=("-device" "ide-hd,bus=ide.0,unit=0,drive=drive0,bootindex=1")
            fi
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                qemu_args+=("-drive" "if=none,media=cdrom,id=drive1,file=$iso,readonly=on")
                qemu_args+=("-device" "ide-cd,bus=ide.0,unit=1,drive=drive1,bootindex=0")
            fi

            # Boot
            qemu_args+=("-prom-env" "boot-args=-v")
            qemu_args+=("-prom-env" "vga-ndrv?=true")
            qemu_args+=("-prom-env" "boot-command=init-program go")

            # NDRV loader
            local ndrv_loader=""
            for path in \
                "/usr/local/share/qemu/ppc-ndrvloader" \
                "/usr/share/qemu/ppc-ndrvloader" \
                "/opt/local/share/qemu/ppc-ndrvloader" \
                "$HOME/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu/ppc-ndrvloader" \
                "/Library/Application Support/UTM/qemu/ppc-ndrvloader"; do
                if [ -f "$path" ]; then
                    ndrv_loader="$path"
                    break
                fi
            done
            if [ -n "$ndrv_loader" ]; then
                qemu_args+=("-device" "loader,addr=0x4000000,file=$ndrv_loader")
            fi
            ;;
    esac

    # Build and execute command
    log_info "Starting VM with command:"
    echo "  ${qemu_args[*]}"
    
    # Write PID
    mkdir -p "$vm_dir"
    
    # Execute
    "${qemu_args[@]}" &
    local qemu_pid=$!
    echo "$qemu_pid" > "$vm_dir/pid"
    log_info "VM $vm_name started with PID: $qemu_pid"
    log_info "To stop VM: kill $qemu_pid"
}

# If script is called directly with start command
if [ "$0" = "/tmp/volatile_hd/vm-assistant/vm-assistant-vm-new.sh" ] || [ "$0" = "./vm-assistant-vm-new.sh" ]; then
    if [ "$1" = "start" ]; then
        start_qemu_vm "$2" "$VM_DIR/$2" "$VM_DIR/$2/config"
    fi
fi
