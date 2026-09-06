#!/bin/bash
# Test Suite - Test all modular scripts
# This script verifies that all scripts in the scripts/ directory have correct structure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
TOTAL=0
SKIP_PATTERNS=("common.sh" "generate_wrapper.sh" "gui_scripts_menu.sh" "test_all_scripts.sh" "debug_vm_xdialog.sh" "platform_select_xdialog.sh" "vm_create_xdialog.sh" "vm_create_gui.sh" "vm_manage_xdialog.sh" "config_management_xdialog.sh" "build_configure.sh" "build_compile.sh" "build_install.sh" "build_patch.sh" "vm_create_template.sh")

echo "Testing VM Manager Scripts"
echo "=========================="
echo ""

# Function to check if script should be skipped
should_skip() {
    local script="$1"
    local name=$(basename "$script")
    for pattern in "${SKIP_PATTERNS[@]}"; do
        if [[ "$name" == "$pattern" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to test a single script
test_script() {
    local script="$1"
    local name=$(basename "$script" .sh)
    
    TOTAL=$((TOTAL + 1))
    
    # Skip certain scripts
    if should_skip "$script"; then
        echo "SKIP: $name"
        return 0
    fi
    
    # Test if script is executable
    if [[ ! -x "$script" ]]; then
        echo "FAIL: $name - Not executable"
        FAIL=$((FAIL + 1))
        return 1
    fi
    
    # Test if script has valid syntax
    if ! bash -n "$script" 2>/dev/null; then
        echo "FAIL: $name - Syntax error"
        FAIL=$((FAIL + 1))
        return 1
    fi
    
    # Test if script has proper shebang
    first_line=$(head -1 "$script")
    if [[ "$first_line" != "#!/bin/bash" ]]; then
        echo "FAIL: $name - Missing or incorrect shebang"
        FAIL=$((FAIL + 1))
        return 1
    fi
    
    # Test if script has description comments
    if ! head -5 "$script" | grep -q -E "(Group:|Action:)" 2>/dev/null; then
        echo "FAIL: $name - Missing group/action description"
        FAIL=$((FAIL + 1))
        return 1
    fi
    
    # Test if script has some functional content (not just comments and exec)
    content_lines=$(wc -l < "$script")
    if [[ $content_lines -lt 5 ]]; then
        echo "FAIL: $name - Script too short"
        FAIL=$((FAIL + 1))
        return 1
    fi
    
    echo "PASS: $name"
    PASS=$((PASS + 1))
}

# Find all scripts and test them
echo "Testing scripts..."
echo ""

# Use simple glob pattern that works on all systems
for script in "${SCRIPT_DIR}"/*.sh; do
    [ -f "$script" ] && test_script "$script"
done

echo ""
echo "=========================="
echo "Test Results:"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $TOTAL"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed. Please review the failures above."
    exit 1
fi