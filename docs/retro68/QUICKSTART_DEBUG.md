# Quick Start: Debug MacOS71_GDB_ICMP_Test from Host

## Prerequisites
- Retro68 installed (see RETRO68/README.md)
- gdb-multiarch installed
- QEMU with PowerPC support
- ROM file in ~/vm_assistant/roms/MacROMan/TestImages/
- ppc-ndrvloader in ~/vm_assistant/shares/
- Disk image at ~/vm_assistant/vms/macos71.qcow2

## Step 1: Compile the Application

```bash
cd ~/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test
make -f Makefile.retro68 clean
make -f Makefile.retro68
```

Output: `build/MacOS71_GDB_ICMP_Test`

## Step 2: Copy to Shared Directory

```bash
cp build/MacOS71_GDB_ICMP_Test ~/vm_assistant/
```

## Step 3: Start QEMU with GDB Support

**Terminal 1:**
```bash
qemu-system-ppc \
    -M mac99 \
    -m 512M \
    -cpu 68040 \
    -bios ~/vm_assistant/MacROMan/TestImages/68040.ROM \
    -drive file=~/vm_assistant/disks/macos71.qcow2,format=qcow2 \
    -gdb tcp::1234 \
    -S \
    -device loader,addr=0x4000000,file=~/vm_assistant/ppc-ndrvloader \
    -fsdev local,path=~/vm_assistant,id=fsdev0 \
    -device virtio-9p-pci,id=fsdev0,fsdev=fsdev0,mount_tag=hostshare \
    -prom-env "auto-boot?=true"
```

## Step 4: Connect GDB

**Terminal 2:**
```bash
gdb-multiarch
(gdb) target remote localhost:1234
(gdb) file ~/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test/build/MacOS71_GDB_ICMP_Test
(gdb) break main
(gdb) break test_gdb_function
(gdb) break test_icmp_function
(gdb) continue
```

## Step 5: Run in VM

1. QEMU boots Mac OS 7.1
2. Open the shared folder "hostshare" 
3. Copy MacOS71_GDB_ICMP_Test to desktop
4. Double-click to launch
5. Click buttons to test GDB and ICMP

## Essential GDB Commands

```
# Breakpoints
break test_gdb_function
break test_icmp_function
break *0xADDRESS

# Execution
continue      # Resume execution
stepi          # Single instruction
nexti          # Next instruction
step           # Next source line (enter functions)
next           # Next source line (skip functions)

# Registers (68k)
info registers d0 d1 d2 d3 d4 d5 d6 d7
info registers a0 a1 a2 a3 a4 a5 a6 a7
print/x $d0
print/x $pc

# Memory
x/16xw 0xADDRESS     # 16 words in hex
x/16xb 0xADDRESS     # 16 bytes in hex
x/8xw gGDBTestBlock  # Examine variable

# Stack
backtrace         # Show call stack
backtrace full    # With locals
frame 1           # Select frame
info args        # Function arguments
info locals       # Local variables
```

## One-Line Commands

**Compile, copy, and debug:**
```bash
cd ~/vm_assistant/vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test && \
make -f Makefile.retro68 && \
cp build/MacOS71_GDB_ICMP_Test ~/vm_assistant/
```

**GDB connect and debug:**
```bash
echo -e "target remote localhost:1234\nfile build/MacOS71_GDB_ICMP_Test\nbreak main\ncontinue" | gdb-multiarch
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| QEMU hangs on BIOS | Add `-prom-env "auto-boot?=true"` |
| GDB can't connect | Verify QEMU started with `-gdb tcp::1234 -S` |
| No symbols | Use `file` command in GDB to load symbols |
| Breakpoints not hit | Verify application path matches GDB file path |
| Black screen | Remove `-vga none` or use `-display cocoa` |

## Reference

- Full debugging guide: vm_clients_3rdparty/macos/RETRO68/DEBUG_GUIDE.md
- Application source: vm_clients_3rdparty/macos/MacOS71_GDB_ICMP_Test/
- Retro68 compiler: vm_clients_3rdparty/macos/RETRO68/
