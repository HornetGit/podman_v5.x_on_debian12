#!/bin/bash
# Shared functions library
# Source this file in other scripts with: source functions.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW2='\033[1;33m' # bright yellow (for dark backgrounds)
YELLOW1='\033[38;5;208m'  # Dark orange - better for white backgrounds
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NOK="\e[31mNOK\e[0m"    # bright red
OK="\e[32mOK\e[0m"      # bright green
WARN="\e[33mWARN\e[0m"  # yellow

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW1}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root
check_not_root() {
    if [ "$EUID" -eq 0 ]; then
        log_error "This script should NOT be run as root"
        exit 1
    fi
}

# Check if user is in sudoers group and has home directory
# Check if user is in sudoers group and has home directory
check_sudoer_with_home() {
    local current_user=$(whoami)
    local user_id=$(id -u)
    local home_dir="$HOME"
    
    # Check if user has a proper home directory
    if [ ! -d "$home_dir" ] || [ "$home_dir" = "/" ]; then
        log_error "User $current_user does not have a valid home directory"
        log_error "Expected: /home/$current_user, Found: $home_dir"
        return 1
    fi
    
    # Check if user is in sudo group (without actually running sudo)
    if ! groups "$current_user" | grep -q '\bsudo\b'; then
        log_error "User $current_user is not in the sudo group"
        log_error "Add user to sudo group: sudo usermod -aG sudo $current_user"
        return 1
    fi
    
    # Check if user ID is not 0 (additional root check)
    if [ "$user_id" -eq 0 ]; then
        log_error "Running as root user (UID 0) - use a regular user with sudo access"
        return 1
    fi
    
    log_success "User validation passed:"
    log_info "  User: $current_user (UID: $user_id)"
    log_info "  Home: $home_dir"
    log_info "  Sudo: User is in sudo group (password required)"
    
    return 0
}

# Check if service is running
service_is_running() {
    local service="$1"
    systemctl --user is-active --quiet "$service" 2>/dev/null
}

# Clean up podman containers
# note that podman system reset --force
# will entirely WIPE OUT your setup if any,
# including crun manually installed binaries
cleanup_podman() {
    log_info "Cleaning up podman containers and networks..."
    podman stop --all 2>/dev/null || true
    podman kill --all --force 2>/dev/null || true
    podman rm --all --force 2>/dev/null || true
    podman rmi --all --force 2>/dev/null || true
    podman system prune -af 2>/dev/null || true
    podman network prune -f 2>/dev/null || true
    podman system reset --force 2>/dev/null || true
}

# Backup file with timestamp
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        log_info "Backed up $file to $backup"
    fi
}

# Secure removal function - handles files, directories, and arrays
# scripting in progress, test soon, see test_rm_secure.sh