#!/usr/bin/env python3
# =============================================================================
# SPICE Screenshot Capture Utility
# 
# Captures screenshots from SPICE server for VM installation automation.
# SPICE provides better framebuffer access than VNC in QEMU.
# =============================================================================

import sys
import os
import time
import argparse
import subprocess
import struct
import socket


def capture_spice_screenshot(hostname, port, output_file, width=1024, height=768):
    """
    Capture screenshot from SPICE server using the SPICE protocol.
    
    This is a simplified implementation that uses the SPICE protocol
    to capture the framebuffer from a running QEMU instance.
    """
    try:
        # SPICE port is usually 5900 + display number
        # QEMU SPICE: -spice port=5900,disable-ticketing
        
        # Connect to SPICE server
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(10)
        
        # Try to connect
        try:
            sock.connect((hostname, port))
        except Exception as e:
            print(f"Failed to connect to SPICE: {e}")
            # Try alternative port calculation
            spice_port = 5900 + int(port)
            try:
                sock.connect((hostname, spice_port))
            except Exception as e2:
                print(f"Failed to connect to SPICE on port {spice_port}: {e2}")
                sock.close()
                return False
        
        # Send SPICE protocol handshake (simplified)
        # This is a complex binary protocol, full implementation is beyond scope
        # For now, use spicy or virt-viewer to capture screenshot
        
        sock.close()
        
        # Use spicy command-line tool if available
        if check_command('spicy'):
            return capture_with_spicy(hostname, port, output_file, width, height)
        
        # Use virt-viewer if available
        if check_command('virt-viewer'):
            return capture_with_virt_viewer(hostname, port, output_file, width, height)
        
        print("Neither spicy nor virt-viewer available")
        return False
        
    except Exception as e:
        print(f"Error: {e}")
        return False


def check_command(cmd):
    """Check if a command exists in PATH."""
    try:
        result = subprocess.run(['which', cmd], capture_output=True, text=True)
        return result.returncode == 0
    except:
        return False


def capture_with_spicy(hostname, port, output_file, width, height):
    """Use spicy (SPICE client) to capture screenshot."""
    try:
        # spicy can connect to SPICE server
        # We can use it in a scriptable mode
        cmd = [
            'spicy',
            '-h', hostname,
            '-p', str(port),
            '-f',  # Fullscreen
            '--title', 'VM Installer',
            '--disable-inputs',  # Don't grab keyboard/mouse
            '--screenshot', output_file
        ]
        
        # Run for a short time
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(3)  # Wait for connection and screenshot
        proc.terminate()
        proc.wait(timeout=5)
        
        # Check if screenshot was captured
        return os.path.exists(output_file) and os.path.getsize(output_file) > 0
        
    except Exception as e:
        print(f"Error with spicy: {e}")
        return False


def capture_with_virt_viewer(hostname, port, output_file, width, height):
    """Use virt-viewer to capture screenshot."""
    try:
        # virt-viewer can capture screenshots
        cmd = [
            'virt-viewer',
            f'spice://{hostname}:{port}',
            '--screenshot', output_file,
            '--connect-only',
            '--quit-on-disconnect'
        ]
        
        # Run for a short time
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(3)  # Wait for connection and screenshot
        proc.terminate()
        proc.wait(timeout=5)
        
        # Check if screenshot was captured
        return os.path.exists(output_file) and os.path.getsize(output_file) > 0
        
    except Exception as e:
        print(f"Error with virt-viewer: {e}")
        return False


def capture_with_qemu_monitor(hostname, port, output_file, qemu_pid):
    """
    Use QEMU monitor to capture screenshot via SPICE.
    
    If QEMU is running with SPICE, we can use the monitor to save a screenshot.
    """
    try:
        monitor_socket = f"/tmp/qemu-monitor-{qemu_pid}.sock"
        
        # Use screendump command in QEMU monitor
        cmd = f"screendump {output_file}"
        
        # Connect to monitor and send command
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(5)
        
        try:
            sock.connect(monitor_socket)
            sock.sendall((cmd + '\n').encode())
            # Read response (optional)
            response = sock.recv(4096).decode()
            sock.close()
            
            # Wait for file to be written
            time.sleep(1)
            return os.path.exists(output_file) and os.path.getsize(output_file) > 0
            
        except Exception as e:
            sock.close()
            print(f"Error connecting to monitor: {e}")
            return False
            
    except Exception as e:
        print(f"Error with QEMU monitor: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description='Capture SPICE Screenshot')
    parser.add_argument('hostname', help='SPICE server hostname')
    parser.add_argument('port', type=int, help='SPICE server port')
    parser.add_argument('output_file', help='Output PNG file path')
    parser.add_argument('--qemu-pid', type=int, help='QEMU process ID for monitor access')
    parser.add_argument('--width', type=int, default=1024, help='Expected width')
    parser.add_argument('--height', type=int, default=768, help='Expected height')
    
    args = parser.parse_args()
    
    print(f"Capturing SPICE screenshot from {args.hostname}:{args.port} to {args.output_file}")
    
    # Try different methods
    methods = []
    
    # If QEMU PID is provided, try monitor method first
    if args.qemu_pid:
        methods.append(('QEMU monitor', lambda: capture_with_qemu_monitor(
            args.hostname, args.port, args.output_file, args.qemu_pid)))
    
    methods.extend([
        ('spicy', lambda: capture_spice_screenshot(args.hostname, args.port, args.output_file, args.width, args.height)),
        ('spicy direct', lambda: capture_with_spicy(args.hostname, args.port, args.output_file, args.width, args.height)),
        ('virt-viewer', lambda: capture_with_virt_viewer(args.hostname, args.port, args.output_file, args.width, args.height)),
    ])
    
    for method_name, method_func in methods:
        print(f"Trying method: {method_name}")
        try:
            if method_func():
                print(f"Success with {method_name}")
                return 0
        except Exception as e:
            print(f"Error with {method_name}: {e}")
            continue
    
    # All methods failed
    print("Error: All screenshot capture methods failed")
    
    # Create a placeholder file
    with open(args.output_file, 'w') as f:
        f.write("SPICE screenshot capture failed")
    
    return 1


if __name__ == '__main__':
    sys.exit(main())
