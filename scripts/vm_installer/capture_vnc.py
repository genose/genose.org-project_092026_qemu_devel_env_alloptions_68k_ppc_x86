#!/usr/bin/env python3
# =============================================================================
# VNC Screenshot Capture Utility
# 
# Captures screenshots from a VNC server for VM installation automation.
# Uses the vncdo Python library (part of pyvnc) or falls back to subprocess.
# =============================================================================

import sys
import os
import time
import argparse
import subprocess
import tempfile


def capture_vnc_screenshot_vncdo(hostname, port, output_file):
    """
    Capture screenshot using vncdo (if available).
    """
    try:
        import vncdo
        
        # Connect to VNC server
        display = f"{hostname}:{port}"
        client = vncdo.Client(display, password='')
        
        # Capture screenshot
        screenshot = client.capture()
        
        # Save to file
        from PIL import Image
        img = Image.frombytes('RGB', screenshot.size, screenshot.rgb, 'raw')
        img.save(output_file, 'PNG')
        
        client.close()
        return True
        
    except ImportError:
        print("vncdo not available, trying alternative methods")
        return False
    except Exception as e:
        print(f"Error with vncdo: {e}")
        return False


def capture_vnc_screenshot_vncdotool(hostname, port, output_file):
    """
    Capture screenshot using vncdotool (command-line).
    """
    try:
        # vncdotool can capture screenshots
        cmd = [
            'vncdotool',
            f'{hostname}:{port}',
            'capture',
            output_file
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return result.returncode == 0
    except Exception as e:
        print(f"Error with vncdotool: {e}")
        return False


def capture_vnc_screenshot_vncviewer(hostname, port, output_file):
    """
    Capture screenshot using vncviewer in zlib mode.
    This is a fallback method.
    """
    try:
        # vncviewer with -zlib option can output to file
        # This is less reliable but works on some systems
        cmd = [
            'vncviewer',
            '-zlib',
            f'{hostname}:{port}',
            '-outline',
            '-passwd', '',
            '-quiet',
            '-viewonly',
            '-snapshot', output_file
        ]
        # This might not work as expected, vncviewer doesn't have -snapshot
        # Try alternative approach
        
        # Use vncviewer to connect and disconnect quickly
        # Not ideal but captures current frame
        cmd = [
            'vncviewer',
            '-passwd', '',
            f'{hostname}:{port}',
            '-geometry', '1024x768',
            '-depth', '24'
        ]
        
        # Run for a short time
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(2)  # Wait for connection
        proc.terminate()
        proc.wait(timeout=5)
        
        return False  # This method doesn't actually save screenshot
        
    except Exception as e:
        print(f"Error with vncviewer: {e}")
        return False


def capture_vnc_screenshot_pyvnc(hostname, port, output_file):
    """
    Capture screenshot using pyvnc library.
    """
    try:
        from pyvnc import VNCClient
        
        # Connect to VNC server
        client = VNCClient(f"{hostname}:{port}")
        
        # Capture framebuffer
        framebuffer = client.getFrameBuffer()
        
        # Save as PNG
        from PIL import Image
        img = Image.frombytes('RGB', (framebuffer.width, framebuffer.height), framebuffer.data)
        img.save(output_file, 'PNG')
        
        client.close()
        return True
        
    except ImportError:
        print("pyvnc not available")
        return False
    except Exception as e:
        print(f"Error with pyvnc: {e}")
        return False


def capture_vnc_screenshot_socat_pnm(hostname, port, output_file):
    """
    Capture screenshot using socat and PNM format.
    QEMU VNC can output in raw PNM format.
    """
    try:
        # QEMU VNC can output raw framebuffer in PNM format
        # We need to get the dimensions first
        
        # For now, assume 1024x768x24 (common MacOS resolution)
        width = 1024
        height = 768
        bytes_per_pixel = 4  # RGBA
        
        # Calculate total bytes
        total_bytes = width * height * bytes_per_pixel
        
        # Connect to VNC and request framebuffer
        # This is a simplified approach
        import socket
        
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect((hostname, port))
        
        # Send VNC protocol handshake (simplified)
        # This is just a placeholder - real implementation needs full VNC protocol
        
        # For now, return False to indicate this method isn't implemented
        sock.close()
        return False
        
    except Exception as e:
        print(f"Error with socat/pnm method: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description='Capture VNC Screenshot')
    parser.add_argument('hostname', help='VNC server hostname')
    parser.add_argument('port', type=int, help='VNC server port')
    parser.add_argument('output_file', help='Output PNG file path')
    parser.add_argument('--timeout', type=int, default=10, help='Connection timeout')
    parser.add_argument('--width', type=int, default=1024, help='Expected width')
    parser.add_argument('--height', type=int, default=768, help='Expected height')
    
    args = parser.parse_args()
    
    print(f"Capturing VNC screenshot from {args.hostname}:{args.port} to {args.output_file}")
    
    # Try different methods in order of preference
    methods = [
        ('vncdo', lambda: capture_vnc_screenshot_vncdo(args.hostname, args.port, args.output_file)),
        ('pyvnc', lambda: capture_vnc_screenshot_pyvnc(args.hostname, args.port, args.output_file)),
        ('vncdotool', lambda: capture_vnc_screenshot_vncdotool(args.hostname, args.port, args.output_file)),
        ('vncviewer', lambda: capture_vnc_screenshot_vncviewer(args.hostname, args.port, args.output_file)),
    ]
    
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
        f.write("VNC screenshot capture failed")
    
    return 1


if __name__ == '__main__':
    sys.exit(main())
