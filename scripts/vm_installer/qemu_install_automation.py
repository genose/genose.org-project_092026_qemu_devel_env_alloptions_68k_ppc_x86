#!/usr/bin/env python3
# =============================================================================
# QEMU Installation Automation with QMP
# 
# This script uses QEMU's QMP (QEMU Machine Protocol) for reliable
# VM control and monitoring. It's more robust than VNC/SPICE approaches.
# =============================================================================

import sys
import os
import json
import time
import socket
import subprocess
import base64
import tempfile
import hashlib
from PIL import Image
import io


class QMPClient:
    """QEMU Machine Protocol client for VM control."""
    
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
        # QMP format: length (4 bytes big-endian) + command
        header = cmd_len.to_bytes(4, 'big')
        self.sock.sendall(header + cmd_json)
    
    def _recv_message(self):
        """Receive a QMP message."""
        # Read 4 bytes for length
        header = self._recv_all(4)
        if not header:
            return None
        msg_len = int.from_bytes(header, 'big')
        
        # Read message
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
            raise QMPError(response.get("error", {}).get("desc", "Unknown error"))
        
        return response.get("return", {})
    
    def screenshot(self, filename):
        """Capture a screenshot via QMP screendump command."""
        try:
            # Use screendump command
            temp_file = f"/tmp/qemu_screenshot_{int(time.time())}.ppm"
            result = self.execute("screendump", filename=temp_file)
            
            # Wait for file to be written
            time.sleep(0.5)
            
            if os.path.exists(temp_file):
                # Convert PPM to PNG
                with open(temp_file, 'rb') as f:
                    ppm_data = f.read()
                
                # Convert PPM to PNG
                img = self._ppm_to_png(ppm_data, temp_file)
                if img:
                    img.save(filename, 'PNG')
                    os.remove(temp_file)
                    return True
            
            return False
        except Exception as e:
            print(f"Screenshot error: {e}")
            return False
    
    def _ppm_to_png(self, ppm_data, filename):
        """Convert PPM data to PIL Image."""
        try:
            with open(filename, 'rb') as f:
                # Try to open as PPM
                return Image.open(f)
        except:
            return None
    
    def mouse_move(self, x, y):
        """Move mouse to coordinates (x, y)."""
        try:
            self.execute("input-move", x=x, y=y)
            return True
        except QMPError as e:
            print(f"Mouse move error: {e}")
            return False
    
    def mouse_click(self, button='left'):
        """Click mouse button."""
        try:
            # QMP doesn't have direct mouse click, use HMP via qmp
            # We'll use the monitor command via QMP
            buttons = {'left': 1, 'right': 2, 'middle': 3}
            if button not in buttons:
                button = 'left'
            
            # Use human-monitor-command
            self.execute("human-monitor-command", 
                       command_line=f"mouse_button {buttons[button]}")
            return True
        except QMPError as e:
            print(f"Mouse click error: {e}")
            return False
    
    def send_key(self, key):
        """Send a key press."""
        try:
            self.execute("input-send-event", events=[
                {"type": "key", "data": {"key": key, "down": True}},
                {"type": "key", "data": {"key": key, "down": False}}
            ])
            return True
        except QMPError as e:
            print(f"Send key error: {e}")
            return False
    
    def get_vm_status(self):
        """Get VM status."""
        try:
            return self.execute("query-status")
        except QMPError as e:
            return {"status": "error", "message": str(e)}
    
    def quit(self):
        """Quit QEMU."""
        try:
            self.execute("quit")
            return True
        except QMPError as e:
            return False


class QMPError(Exception):
    pass


class InstallationAutomator:
    """Automates OS installation in a VM."""
    
    def __init__(self, vm_name, qmp_socket=None, vnc_port=None):
        self.vm_name = vm_name
        self.qmp_socket = qmp_socket or f"/tmp/qmp-{vm_name}.sock"
        self.vnc_port = vnc_port or 1
        self.qmp = None
        self.state = "unknown"
        self.start_time = time.time()
        self.timeout = 3600  # 1 hour
    
    def connect(self):
        """Connect to QMP socket."""
        self.qmp = QMPClient(socket_path=self.qmp_socket)
        if not self.qmp.connect():
            return False
        return True
    
    def disconnect(self):
        """Disconnect from QMP."""
        if self.qmp:
            self.qmp.disconnect()
    
    def capture_screenshot(self):
        """Capture screenshot from VM."""
        filename = f"/tmp/vm_screenshot_{self.vm_name}_{int(time.time())}.png"
        if self.qmp and self.qmp.screenshot(filename):
            return filename
        return None
    
    def detect_installer_state(self, screenshot_file):
        """Use OCR to detect installer state."""
        try:
            from PIL import Image
            import pytesseract
            
            # Open screenshot
            img = Image.open(screenshot_file)
            
            # Extract text
            text = pytesseract.image_to_string(img).lower()
            
            # Detect state
            if any(word in text for word in ['language', 'select your language', 'langue', 'idioma']):
                return "language_selection"
            elif any(word in text for word in ['license', 'agreement', 'eula', 'terms', 'accept']):
                return "license_agreement"
            elif any(word in text for word in ['disk', 'select disk', 'destination', 'where do']):
                return "disk_selection"
            elif any(word in text for word in ['install', 'installation', 'copying', 'progress']):
                return "installing"
            elif any(word in text for word in ['complete', 'finished', 'success', 'restart', 'reboot']):
                return "installation_complete"
            elif any(word in text for word in ['mac os', 'macos', 'snow leopard', 'welcome']):
                return "os_booting"
            else:
                return "unknown"
        except ImportError:
            print("Tesseract not available, using placeholder detection")
            return "unknown"
        except Exception as e:
            print(f"OCR error: {e}")
            return "unknown"
    
    def click_button(self, x, y):
        """Click at a specific coordinate."""
        if not self.qmp:
            return False
        
        # Move mouse
        if not self.qmp.mouse_move(x, y):
            return False
        
        time.sleep(0.2)
        
        # Click
        if not self.qmp.mouse_click('left'):
            return False
        
        time.sleep(0.5)
        return True
    
    def press_key(self, key):
        """Press a key."""
        if not self.qmp:
            return False
        return self.qmp.send_key(key)
    
    def run_installation(self):
        """Run the complete installation automation."""
        if not self.connect():
            print("Failed to connect to QMP socket")
            return False
        
        try:
            print("Starting installation automation...")
            
            while time.time() - self.start_time < self.timeout:
                # Capture screenshot
                screenshot = self.capture_screenshot()
                
                if not screenshot:
                    print("Failed to capture screenshot, retrying...")
                    time.sleep(2)
                    continue
                
                # Detect state
                self.state = self.detect_installer_state(screenshot)
                print(f"Detected state: {self.state}")
                
                # Handle each state
                if self.state == "language_selection":
                    print("Handling language selection...")
                    self.click_button(300, 200)  # Click English
                
                elif self.state == "license_agreement":
                    print("Handling license agreement...")
                    self.click_button(400, 350)  # Click Agree
                
                elif self.state == "disk_selection":
                    print("Handling disk selection...")
                    self.click_button(300, 250)  # Select first disk
                    time.sleep(1)
                    self.click_button(400, 400)  # Click Continue
                
                elif self.state == "installing":
                    print("Installation in progress, monitoring...")
                    time.sleep(5)
                
                elif self.state == "installation_complete":
                    print("Installation complete!")
                    # Eject CD and reboot
                    self.press_key("eject-cdrom")
                    time.sleep(1)
                    self.press_key("reboot")
                    return True
                
                elif self.state == "os_booting":
                    print("OS is booting...")
                    time.sleep(5)
                
                else:
                    print(f"Unknown state, waiting... (elapsed: {time.time() - self.start_time:.0f}s)")
                    time.sleep(3)
            
            print("Installation timed out")
            return False
            
        finally:
            self.disconnect()
    
    def get_vm_status(self):
        """Get VM status."""
        if not self.qmp:
            return {"status": "disconnected"}
        return self.qmp.get_vm_status()


def start_qemu_with_qmp(vm_name, iso_file, disk_file, rom_file, cpus=2):
    """Start QEMU with QMP socket enabled."""
    qmp_socket = f"/tmp/qmp-{vm_name}.sock"
    
    # Remove old socket if it exists
    if os.path.exists(qmp_socket):
        os.remove(qmp_socket)
    
    cmd = [
        os.path.expanduser("~/Documents/github/genose.org-project_092026_qemu_devel_env_alloptions_68k_ppc_x86/qemu-9.2.0/build/qemu-system-ppc64"),
        "-name", f"{vm_name}-install",
        "-machine", "mac99,via=pmu",
        "-cpu", "970fx",
        "-m", "2048",
        "-smp", str(cpus),
        "-bios", rom_file,
        "-hda", disk_file,
        "-cdrom", iso_file,
        "-boot", "d",
        "-device", "VGA,vgamem_mb=64",
        "-device", "secondary-vga,vgamem_mb=32",
        "-device", "usb-kbd",
        "-device", "usb-mouse",
        "-nic", "user,model=sungem",
        "-rtc", "base=localtime",
        "-audiodev", "coreaudio,id=snd0",
        "-display", "none",
        "-serial", "null",
        "-nographic",
        "-qmp", f"unix:{qmp_socket},server,nowait",
        "-monitor", f"unix:/tmp/monitor-{vm_name}.sock,server,nowait"
    ]
    
    print(f"Starting QEMU: {' '.join(cmd)}")
    
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Wait for QMP socket to be created
    for _ in range(10):
        if os.path.exists(qmp_socket):
            return proc, qmp_socket
        time.sleep(0.5)
    
    # Cleanup if failed
    proc.terminate()
    proc.wait(timeout=5)
    return None, None


def main():
    parser = argparse.ArgumentParser(description='QEMU Installation Automation')
    parser.add_argument('vm_name', help='VM name')
    parser.add_argument('--iso', help='ISO file path')
    parser.add_argument('--disk', help='Disk file path')
    parser.add_argument('--rom', help='ROM file path')
    parser.add_argument('--cpus', type=int, default=2, help='Number of CPUs')
    parser.add_argument('--timeout', type=int, default=3600, help='Timeout in seconds')
    
    args = parser.parse_args()
    
    # Set default paths if not provided
    if not args.iso:
        args.iso = os.path.expanduser("~/vm_assistant/images/Mac_OS_X_10.6_Snow_Leopard_Retail.iso")
    if not args.disk:
        args.disk = os.path.expanduser(f"~/vm_assistant/vms/{args.vm_name}/qcow2/{args.vm_name}.qcow2")
    if not args.rom:
        args.rom = os.path.expanduser(f"~/vm_assistant/vms/{args.vm_name}/rom/mac99.rom")
    
    # Start QEMU with QMP
    print(f"Starting VM: {args.vm_name}")
    proc, qmp_socket = start_qemu_with_qmp(
        args.vm_name, args.iso, args.disk, args.rom, args.cpus
    )
    
    if not proc:
        print("Failed to start QEMU")
        return 1
    
    try:
        # Wait for QEMU to fully initialize
        time.sleep(5)
        
        # Create and run automator
        automator = InstallationAutomator(args.vm_name, qmp_socket, args.cpus)
        automator.timeout = args.timeout
        
        success = automator.run_installation()
        
        if success:
            print("Installation completed successfully!")
            return 0
        else:
            print("Installation failed or timed out")
            return 1
    
    except KeyboardInterrupt:
        print("Installation interrupted")
        return 1
    finally:
        if proc:
            proc.terminate()
            proc.wait(timeout=10)


if __name__ == '__main__':
    sys.exit(main())
