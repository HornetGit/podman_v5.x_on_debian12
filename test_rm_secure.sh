#!/bin/bash
# Test script for rm_secure function
# This creates safe test files/directories and tests the rm_secure function

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[38;5;208m'
BLUE='\033[0;34m'
NC='\033[0m'

# continue or abort by the user
# Usage: continue_or_abort [condition]
continue_or_abort() {
    local condition="$1"
    if [ "$condition" = false ]; then
        read -n1 -p "Press y/Y to continue, any other key to abort: " key
        echo    # move to a new line
        if [[ "$key" =~ [yY] ]]; then
            log_success "Continuing..."
        else
            log_error "Aborted by user."
            exit 1
        fi
    fi
}

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# The rm_secure function to test
rm_secure() {
    local use_sudo=false
    local item
    
    # Check if first argument is "sudo"
    if [ "$1" = "sudo" ]; then
        use_sudo=true
        shift  # Remove "sudo" from arguments
    fi
    
    # Process each argument
    for item in "$@"; do
        # Expand wildcards and user variables
        local expanded_path=$(eval echo "$item")
        
        # Safety check - prevent dangerous paths
        # rm_secure "/usr/*" → blocked (dangerous wildcard)
        # rm_secure "/usr/local/bin/podman" → allowed (specific file)

        # Check first the original argument before expansion
        case "$item" in
            "/*" | "/bin/*" | "/usr/*" | "/etc/*" | "/var/*" | "/home/*")
                log_error "Refusing dangerous wildcard pattern: $item"
                continue
                ;;
        esac
        # Then check expanded path for exact dangerous directories
        case "$expanded_path" in
            "/" | "/bin" | "/usr" | "/etc" | "/var" | "/home" | "" | " ")
                log_error "Refusing to remove dangerous path: $expanded_path"
                continue
                ;;
        esac
        
        # Check if item exists
        if [ -e "$expanded_path" ] || [ -L "$expanded_path" ]; then
            if [ -d "$expanded_path" ]; then
                log_info "Removing directory: $expanded_path"
                if [ "$use_sudo" = true ]; then
                    echo "WOULD RUN: sudo rm -rf \"$expanded_path\""
                else
                    rm -rf "$expanded_path"
                fi
            else
                log_info "Removing file: $expanded_path"
                if [ "$use_sudo" = true ]; then
                    echo "WOULD RUN: sudo rm -f \"$expanded_path\""
                else
                    rm -f "$expanded_path"
                fi
            fi
        else
            log_info "Not found (skipping): $expanded_path"
        fi
    done
}

# Create test directory structure
TEST_DIR="/tmp/rm_secure_test"
log_info "Creating test environment in $TEST_DIR"

# Clean up any existing test
rm -rf "$TEST_DIR"

# Create test structure
mkdir -p "$TEST_DIR"/{dir1,dir2/subdir,empty_dir}
touch "$TEST_DIR"/{file1.txt,file2.log,dir2/nested_file.txt}
echo "test content" > "$TEST_DIR/file_with_content.txt"

# Create test files with wildcards
touch "$TEST_DIR"/{test_a.tmp,test_b.tmp,other.backup}

log_success "Test environment created:"
ls -la "$TEST_DIR"

echo
log_info "=== TEST 1: Remove single file ($TEST_DIR/file1.txt)==="
continue_or_abort false
rm_secure "$TEST_DIR/file1.txt"

echo
log_info "=== TEST 2: Remove single directory ($TEST_DIR/empty_dir) ==="
continue_or_abort false
rm_secure "$TEST_DIR/empty_dir"

echo
log_info "=== TEST 3: Remove multiple items : file2.log, dir1, nonexistent.txt ==="
continue_or_abort false
rm_secure "$TEST_DIR/file2.log" "$TEST_DIR/dir1" "$TEST_DIR/nonexistent.txt"

echo
log_info "=== TEST 4: Remove with wildcards ($TEST_DIR/*.tmp)==="
continue_or_abort false
rm_secure "$TEST_DIR"/*.tmp

echo
log_info "=== TEST 5: Test simulating 'sudo' mode  on 'file_with_content.txt' and /dir2 (DRY RUN - no actual sudo) ==="
continue_or_abort false
rm_secure sudo "$TEST_DIR/file_with_content.txt" "$TEST_DIR/dir2"

echo
log_info "=== TEST 6: Test dangerous path protection (/, /bin, /usr) ==="
# rm_secure "/usr/*" → blocked (dangerous wildcard)
continue_or_abort false
rm_secure "/" "/usr" "/bin" "" " "

echo
log_info "=== TEST 6bis: Allow specific directories /usr/local/bin/podman  ==="
# rm_secure "/usr/local/bin/podman" → allowed (specific file)
continue_or_abort false
rm_secure "/usr/local/bin/podman"

echo
log_info "=== TEST 7: Test array usage ==="
continue_or_abort false
test_array=(
    "$TEST_DIR/other.backup"
    "$TEST_DIR/nonexistent_file.txt"
    "$TEST_DIR"
)
rm_secure "${test_array[@]}"

echo
log_info "=== TEST RESULTS ==="
if [ -d "$TEST_DIR" ]; then
    log_warning "Remaining files/directories:"
    ls -la "$TEST_DIR" 2>/dev/null || log_info "Test directory is empty"
else
    log_success "All test files cleaned up successfully"
fi

echo
log_info "=== CLEANUP ==="
if [ -d "$TEST_DIR" ]; then
    log_info "Cleaning up test environment..."
    rm_secure "$TEST_DIR"
    log_success "Test environment cleaned up safely"
else
    log_info "Test directory already cleaned up"
fi

echo
log_success "All tests completed! The rm_secure function is ready to use."
log_warning "Note: sudo commands were simulated (not actually run)"