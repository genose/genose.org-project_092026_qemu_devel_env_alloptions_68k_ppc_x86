#!/bin/bash
/***************************************************************************
 * Custom Bootloader - Cross-Compiler Setup Script
 * 
 * This script installs the cross-compilation tools needed to build
 * the universal FATBIN bootloader for 68k and PowerPC targets.
 * 
 * Required tools:
 * - m68k-elf-gcc / m68k-elf-as / m68k-elf-ld (for 68k)
 * - powerpc-elf-gcc / powerpc-elf-as / powerpc-elf-ld (for PPC)
 * 
 * On macOS, these can be installed via:
 * - Homebrew (recommended)
 * - MacPorts
 * - Manual compilation
 * 
 * Usage: ./setup-cross-compilers.sh [--macports|--homebrew|--manual]
 ***************************************************************************/

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}=== Custom Bootloader - Cross-Compiler Setup ===${NC}"
echo ""

# Detect platform
PLATFORM="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macos"
elif [[ "$OSTYPE" == "linux"* ]]; then
    PLATFORM="linux"
else
    echo -e "${RED}Unsupported platform: $OSTYPE${NC}"
    exit 1
fi

echo "Detected platform: $PLATFORM"
echo ""

# Check which method to use
METHOD="auto"
if [ $# -gt 0 ]; then
    METHOD="$1"
fi

install_macos() {
    echo -e "${YELLOW}=== Installing cross-compilers on macOS ===${NC}"
    echo ""
    
    # Check if Homebrew is available
    if command -v brew &> /dev/null; then
        echo "Homebrew detected. Installing via Homebrew..."
        
        # Tap for cross-compilation tools
        brew tap homebrew/versions
        
        # Install m68k-elf toolchain
        if ! command -v m68k-elf-gcc &> /dev/null; then
            echo "Installing m68k-elf toolchain..."
            brew install --ignore-dependencies m68k-elf-gcc || true
            # If the above fails, try alternative
            if ! command -v m68k-elf-gcc &> /dev/null; then
                echo "Trying alternative m68k toolchain..."
                brew install --ignore-dependencies m68k-elf-binutils || true
                brew install --ignore-dependencies m68k-elf-gcc@12 || true
            fi
        fi
        
        # Install PowerPC toolchain
        if ! command -v powerpc-elf-gcc &> /dev/null; then
            echo "Installing PowerPC toolchain..."
            # Note: powerpc-elf may not be directly available, might need powerpc-cross
            brew install --ignore-dependencies powerpc-cross || true
            if ! command -v powerpc-elf-gcc &> /dev/null; then
                echo "Trying alternative PowerPC toolchain..."
                brew install --ignore-dependencies powerpc64le-elf-gcc || true
            fi
        fi
        
    elif command -v port &> /dev/null; then
        echo "MacPorts detected. Installing via MacPorts..."
        
        # Install m68k-elf toolchain
        if ! command -v m68k-elf-gcc &> /dev/null; then
            echo "Installing m68k-elf toolchain..."
            sudo port install m68k-elf-gcc || true
            sudo port install m68k-elf-binutils || true
        fi
        
        # Install PowerPC toolchain
        if ! command -v powerpc-elf-gcc &> /dev/null; then
            echo "Installing PowerPC toolchain..."
            # MacPorts might have these
            sudo port install powerpc-elf-gcc || true
            sudo port install powerpc-elf-binutils || true
        fi
        
    else
        echo -e "${RED}Neither Homebrew nor MacPorts found.${NC}"
        echo "Please install one of them first:"
        echo "  Homebrew: https://brew.sh"
        echo "  MacPorts: https://www.macports.org"
        exit 1
    fi
    
    echo ""
    echo "Checking installations..."
    verify_install
}

install_linux() {
    echo -e "${YELLOW}=== Installing cross-compilers on Linux ===${NC}"
    echo ""
    
    # Try apt-get
    if command -v apt-get &> /dev/null; then
        echo "Using apt-get..."
        sudo apt-get update
        sudo apt-get install -y gcc-m68k-elf || true
        sudo apt-get install -y gcc-powerpc-elf || true
        sudo apt-get install -y gcc-powerpc64le-elf || true
        sudo apt-get install -y binutils-m68k-elf || true
        sudo apt-get install -y binutils-powerpc-elf || true
        
    # Try yum/dnf
    elif command -v dnf &> /dev/null; then
        echo "Using dnf..."
        sudo dnf install -y m68k-elf-gcc m68k-elf-binutils || true
        sudo dnf install -y powerpc-elf-gcc powerpc-elf-binutils || true
        
    elif command -v yum &> /dev/null; then
        echo "Using yum..."
        sudo yum install -y m68k-elf-gcc m68k-elf-binutils || true
        sudo yum install -y powerpc-elf-gcc powerpc-elf-binutils || true
        
    else
        echo -e "${RED}No supported package manager found.${NC}"
        exit 1
    fi
    
    echo ""
    echo "Checking installations..."
    verify_install
}

verify_install() {
    echo ""
    echo -e "${YELLOW}Verifying cross-compiler installations...${NC}"
    
    # Check m68k tools
    if command -v m68k-elf-gcc &> /dev/null; then
        echo -e "${GREEN}✓ m68k-elf-gcc found${NC}: $(which m68k-elf-gcc)"
    else
        echo -e "${RED}✗ m68k-elf-gcc not found${NC}"
    fi
    
    if command -v m68k-elf-as &> /dev/null; then
        echo -e "${GREEN}✓ m68k-elf-as found${NC}: $(which m68k-elf-as)"
    else
        echo -e "${RED}✗ m68k-elf-as not found${NC}"
    fi
    
    if command -v m68k-elf-ld &> /dev/null; then
        echo -e "${GREEN}✓ m68k-elf-ld found${NC}: $(which m68k-elf-ld)"
    else
        echo -e "${RED}✗ m68k-elf-ld not found${NC}"
    fi
    
    # Check PPC tools
    if command -v powerpc-elf-gcc &> /dev/null; then
        echo -e "${GREEN}✓ powerpc-elf-gcc found${NC}: $(which powerpc-elf-gcc)"
    else
        echo -e "${RED}✗ powerpc-elf-gcc not found${NC}"
    fi
    
    if command -v powerpc-elf-as &> /dev/null; then
        echo -e "${GREEN}✓ powerpc-elf-as found${NC}: $(which powerpc-elf-as)"
    else
        echo -e "${RED}✗ powerpc-elf-as not found${NC}"
    fi
    
    if command -v powerpc-elf-ld &> /dev/null; then
        echo -e "${GREEN}✓ powerpc-elf-ld found${NC}: $(which powerpc-elf-ld)"
    else
        echo -e "${RED}✗ powerpc-elf-ld not found${NC}"
    fi
    
    echo ""
}

show_manual_instructions() {
    echo ""
    echo -e "${YELLOW}=== Manual Installation Instructions ===${NC}"
    echo ""
    echo "Option 1: Using Homebrew (macOS)"
    echo "  1. Install Homebrew: https://brew.sh"
    echo "  2. brew tap homebrew/versions"
    echo "  3. brew install m68k-elf-gcc m68k-elf-binutils"
    echo "  4. brew install powerpc-cross"
    echo ""
    echo "Option 2: Using MacPorts (macOS)"
    echo "  1. Install MacPorts: https://www.macports.org"
    echo "  2. sudo port install m68k-elf-gcc m68k-elf-binutils"
    echo "  3. sudo port install powerpc-elf-gcc powerpc-elf-binutils"
    echo ""
    echo "Option 3: Using apt-get (Debian/Ubuntu)"
    echo "  sudo apt-get install gcc-m68k-elf binutils-m68k-elf"
    echo "  sudo apt-get install gcc-powerpc-elf binutils-powerpc-elf"
    echo ""
    echo "Option 4: Manual Compilation"
    echo "  Download and compile binutils and gcc for each target."
    echo "  See: https://www.gnu.org/software/binutils/"
    echo "       https://gcc.gnu.org/"
    echo ""
}

# Main logic
case "$METHOD" in
    --homebrew)
        install_macos
        ;;
    --macports)
        install_macos
        ;;
    --linux)
        install_linux
        ;;
    --manual|--help|-h|help)
        show_manual_instructions
        ;;
    *)
        echo "Detected platform: $PLATFORM"
        echo "Selected method: $METHOD (auto)"
        echo ""
        
        if [ "$PLATFORM" = "macos" ]; then
            install_macos
        elif [ "$PLATFORM" = "linux" ]; then
            install_linux
        else
n            echo -e "${RED}Unsupported platform${NC}"
            show_manual_instructions
        fi
        ;;
esac

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "To build the bootloader, run:"
echo "  cd $SCRIPT_DIR"
echo "  make"
echo ""
echo "Or with custom tools:"
echo "  make CC_68K=m68k-elf-gcc AS_68K=m68k-elf-as LD_68K=m68k-elf-ld"
echo "  make CC_PPC=powerpc-elf-gcc AS_PPC=powerpc-elf-as LD_PPC=powerpc-elf-ld"
