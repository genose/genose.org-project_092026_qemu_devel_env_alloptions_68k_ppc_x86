#!/usr/bin/env python3
# =============================================================================
# VM Control and Monitoring Utility
# 
# Provides comprehensive control over QEMU VMs via QMP:
# - Start, stop, pause, resume VMs
# - Monitor VM status and statistics
# - Capture screenshots
# - Inject input
# - Manage devices (CD-ROM, etc.)
# =============================================================================

import sys
import os
import json
import time
import socket
import subprocess
import argparse
import atexit
import signal


class QMPClient:
    """QEMU Machine Protocol client."""
    
    def __init__(self, socket_path=None, host=None, port=None):
        self.socket_path = socket_path
        self.host = host
        self.port = port
        self.sock = None
        self.greeting = None
    
    def connect(self):
        """Connect to QMP socket."""
        try:
            if self.socket_path:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(self.socket_path)
            else:
                self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.sock.connect((self.host, self.port))
            
            # Receive greeting
            self.greeting = self._recv_message()
            
            # Enable QMP capabilities
            self._send_command({"execute": "qmp_capabilities"})
            response = self._recv_message()
            
            return True
        except Exception as e:
            print(f"QMP connection error: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from QMP socket."""
        if self.sock:
            try:
                self.sock.close()
            except:
                pass
            self.sock = None
    
    def _send_command(self, cmd):
        """Send a QMP command."""
        cmd_json = json.dumps(cmd).encode()
        cmd_len = len(cmd_json)
        header = cmd_len.to_bytes(4, 'big')
        self.sock.sendall(header + cmd_json)
    
    def _recv_message(self):
        """Receive a QMP message."""
        header = self._recv_all(4)
        if not header:
            return None
        msg_len = int.from_bytes(header, 'big')
        msg_data = self._recv_all(msg_len)
        if not msg_data:
            return None
        return json.loads(msg_data.decode())
    
    def _recv_all(self, n):
        """Receive exactly n bytes."""
        data = b''
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                return None
            data += chunk
        return data
    
    def execute(self, cmd_name, **kwargs):
        """Execute a QMP command."""
        cmd = {"execute": cmd_name}
        if kwargs:
            cmd["arguments"] = kwargs
        
        self._send_command(cmd)
        response = self._recv_message()
        
        if "error" in response:
            error_desc = response.get("error", {}).get("desc", "Unknown error")
            raise QMPError(error_desc)
        
        return response.get("return", {})
    
    def get_status(self):
        """Get VM status."""
        return self.execute("query-status")
    
    def get_info(self):
        """Get comprehensive VM info."""
        info = {}
        info["status"] = self.get_status()
        info["version"] = self.execute("query-version")
        info["cpu"] = self.execute("query-cpus")
        info["memory"] = self.execute("query-memory-size-summary")
        info["balloon"] = self.execute("query-balloon")
        return info
    
    def stop(self):
        """Stop VM."""
        return self.execute("stop")
    
    def cont(self):
        """Continue VM execution."""
        return self.execute("cont")
    
    def pause(self):
        """Pause VM."""
        return self.execute("stop")
    
    def resume(self):
        """Resume paused VM."""
        return self.execute("cont")
    
    def reset(self):
        """Reset VM."""
        return self.execute("system_reset")
    
    def powerdown(self):
        """Power down VM."""
        return self.execute("system_powerdown")
    
    def quit(self):
        """Quit QEMU."""
        return self.execute("quit")
    
    def screenshot(self, filename):
        """Capture screenshot."""
        import tempfile
        import os
        from PIL import Image
        
        temp_ppm = tempfile.mktemp(suffix='.ppm')
        try:
            self.execute("screendump", filename=temp_ppm)
            time.sleep(0.5)
            
            if os.path.exists(temp_ppm):
                try:
                    img = Image.open(temp_ppm)
                    img.save(filename, 'PNG')
                    os.remove(temp_ppm)
                    return True
                except Exception as e:
                    print(f"Failed to convert PPM: {e}")
                    return False
            return False
        except Exception as e:
            print(f"Screenshot error: {e}")
            return False
    
    def mouse_move(self, x, y):
        """Move mouse."""
        return self.execute("input-move", x=x, y=y)
    
    def mouse_click(self, button='left'):
        """Click mouse button."""
        buttons = {'left': 1, 'right': 2, 'middle': 3}
        button_num = buttons.get(button, 1)
        return self.execute("human-monitor-command", 
                          command_line=f"mouse_button {button_num}")
    
    def send_key(self, key):
        """Send key press."""
        return self.execute("input-send-event", events=[
            {"type": "key", "data": {"key": key, "down": True}},
            {"type": "key", "data": {"key": key, "down": False}}
        ])
    
    def eject_cdrom(self):
        """Eject CD-ROM."""
        return self.execute("eject-cdrom", device="ide0-cd0")
    
    def change_cdrom(self, iso_file):
        """Change CD-ROM."""
        return self.execute("change-cdrom", device="ide0-cd0", target=iso_file)
    
    def get_block_stats(self):
        """Get block device statistics."""
        return self.execute("query-blockstats")
    
    def get_block_jobs(self):
        """Get block job status."""
        return self.execute("query-block-jobs")
    
    def get_pci_devices(self):
        """Get PCI device information."""
        return self.execute("query-pci")
    
    def get_usb_devices(self):
        """Get USB device information."""
        return self.execute("query-usb")
    
    def set_link(self, netdev, up=True):
        """Set network link status."""
        status = "up" if up else "down"
        return self.execute("set_link", name=netdev, up=up)


class QMPError(Exception):
    pass


def find_qmp_socket(vm_name=None):
    """Find QMP socket for a running VM."""
    if vm_name:
        candidate = f"/tmp/qmp-{vm_name}.sock"
        if os.path.exists(candidate):
            return candidate
    
    # Search for any QMP socket
    for filename in os.listdir('/tmp'):
        if filename.startswith('qmp-') and filename.endswith('.sock'):
            return f"/tmp/{filename}"
    
    return None


def start_vm(vm_name, cpus=2, mem=2048, iso=None, hda=None, bios=None, headless=True):
    """Start a VM with QMP socket."""
    qmp_socket = f"/tmp/qmp-{vm_name}.sock"
    monitor_socket = f"/tmp/monitor-{vm_name}.sock"
    
    # Clean up old sockets
    for sock in [qmp_socket, monitor_socket]:
        if os.path.exists(sock):
            os.remove(sock)
    
    cmd = [
        os.path.expanduser("~/Documents/github/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86/qemu-9.2.0/build/qemu-system-ppc64"),
        "-name", vm_name,
        "-machine", "mac99,via=pmu",
        "-cpu", "970fx",
        "-m", str(mem),
        "-smp", str(cpus),
        "-bios", bios or os.path.expanduser("~/vm_assistant/vms/macos-106-ppc_ppc64/rom/mac99.rom"),
        "-hda", hda or os.path.expanduser("~/vm_assistant/vms/macos-106-ppc_ppc64/qcow2/macos-106-ppc.qcow2"),
        "-device", "VGA,vgamem_mb=64",
        "-device", "secondary-vga,vgamem_mb=32",
        "-device", "usb-kbd",
        "-device", "usb-mouse",
        "-nic", "user,model=sungem",
        "-rtc", "base=localtime",
        "-audiodev", "coreaudio,id=snd0",
        "-qmp", f"unix:{qmp_socket},server,nowait",
        "-monitor", f"unix:{monitor_socket},server,nowait"
    ]
    
    if iso:
        cmd.extend(["-cdrom", iso, "-boot", "d"])
    
    if headless:
        cmd.extend(["-display", "none", "-serial", "null", "-nographic"])
    else:
        cmd.extend(["-display", "cocoa"])
    
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Wait for QMP socket
    for _ in range(20):
        if os.path.exists(qmp_socket):
            return proc, qmp_socket
        time.sleep(0.5)
    
    # Cleanup
    proc.terminate()
    proc.wait(timeout=5)
    return None, None


def main():
    parser = argparse.ArgumentParser(description='VM Control and Monitoring')
    subparsers = parser.add_subparsers(dest='command')
    
    # Start command
    start_parser = subparsers.add_parser('start', help='Start a VM')
    start_parser.add_argument('--name', required=True, help='VM name')
    start_parser.add_argument('--cpus', type=int, default=2, help='Number of CPUs')
    start_parser.add_argument('--mem', type=int, default=2048, help='Memory in MB')
    start_parser.add_argument('--iso', help='ISO file path')
    start_parser.add_argument('--hda', help='Disk file path')
    start_parser.add_argument('--bios', help='BIOS/ROM file path')
    start_parser.add_argument('--headless', action='store_true', help='Run in headless mode')
    
    # Stop command
    stop_parser = subparsers.add_parser('stop', help='Stop a VM')
    stop_parser.add_argument('--name', help='VM name')
    stop_parser.add_argument('--socket', help='QMP socket path')
    
    # Info command
    info_parser = subparsers.add_parser('info', help='Get VM information')
    info_parser.add_argument('--name', help='VM name')
    info_parser.add_argument('--socket', help='QMP socket path')
    
    # Screenshot command
    screenshot_parser = subparsers.add_parser('screenshot', help='Capture screenshot')
    screenshot_parser.add_argument('--name', help='VM name')
    screenshot_parser.add_argument('--socket', help='QMP socket path')
    screenshot_parser.add_argument('--output', default='/tmp/vm_screenshot.png', help='Output file')
    
    # Monitor command
    monitor_parser = subparsers.add_parser('monitor', help='Monitor VM continuously')
    monitor_parser.add_argument('--name', help='VM name')
    monitor_parser.add_argument('--socket', help='QMP socket path')
    monitor_parser.add_argument('--interval', type=int, default=5, help='Update interval in seconds')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    # Handle commands
    if args.command == 'start':
        proc, qmp_socket = start_vm(
            args.name, args.cpus, args.mem, args.iso, args.hda, args.bios, args.headless
        )
        
        if not proc:
            print("Failed to start VM")
            return 1
        
        print(f"VM '{args.name}' started with PID {proc.pid}")
        print(f"QMP socket: {qmp_socket}")
        
        # Wait for user to stop
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("Stopping VM...")
            proc.terminate()
            proc.wait(timeout=10)
        
    elif args.command in ['stop', 'info', 'screenshot']:
        # Find QMP socket
        qmp_socket = args.socket or find_qmp_socket(args.name)
        
        if not qmp_socket:
            print(f"Could not find QMP socket for VM: {args.name}")
            return 1
        
        # Connect to QMP
        qmp = QMPClient(socket_path=qmp_socket)
        if not qmp.connect():
            print(f"Failed to connect to QMP socket: {qmp_socket}")
            return 1
        
        try:
            if args.command == 'stop':
                print("Stopping VM...")
                qmp.quit()
                print("VM stopped")
            
            elif args.command == 'info':
                info = qmp.get_info()
                print(json.dumps(info, indent=2))
            
            elif args.command == 'screenshot':
                if qmp.screenshot(args.output):
                    print(f"Screenshot saved to: {args.output}")
                else:
                    print("Failed to capture screenshot")
                    return 1
        
        finally:
            qmp.disconnect()
    
    elif args.command == 'monitor':
        # Find QMP socket
        qmp_socket = args.socket or find_qmp_socket(args.name)
        
        if not qmp_socket:
            print(f"Could not find QMP socket for VM: {args.name}")
            return 1
        
        # Connect to QMP
        qmp = QMPClient(socket_path=qmp_socket)
        if not qmp.connect():
            print(f"Failed to connect to QMP socket: {qmp_socket}")
            return 1
        
        try:
            print(f"Monitoring VM (Ctrl+C to stop, update every {args.interval}s)...")
            
            while True:
                try:
                    status = qmp.get_status()
                    info = qmp.get_info()
                    
                    os.write(sys.stdout.fileno(), b"\033[2J\033[H")  # Clear screen
                    
                    print("=" * 60)
                    print(f"VM: {args.name or 'unknown'}")
                    print("=" * 60)
                    print(f"Status: {status.get('status', 'unknown')}")
                    print(f"Singlestep: {status.get('singlestep', False)}")
                    print(f"Running: {status.get('running', False)}")
                    print()
                    
                    version = info.get('version', {})
                    print(f"QEMU Version: {version.get('qemu', {}).get('version', 'unknown')}")
                    print()
                    
                    cpu_info = info.get('cpu', [])
                    print(f"CPUs: {len(cpu_info) if cpu_info else 0}")
                    for i, cpu in enumerate(cpu_info):
                        print(f"  CPU {i}: {cpu.get('arch', 'unknown')} - {cpu.get('target', 'unknown')}")
                    print()
                    
                    memory = info.get('memory', {})
                    print(f"Memory: {memory.get('base-memory', 0)} bytes")
                    
                    time.sleep(args.interval)
                except KeyboardInterrupt:
                    break
                except Exception as e:
                    print(f"Error: {e}")
                    break
        
        finally:
            qmp.disconnect()
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
