#!/bin/bash
# uninstall any crun installed
# OWNER: XCS
# CREATED: 03JUL2025
# UPDATED: 03DEC2025
# Run as: Admin user with sudo (uninstalls FOR specified user)
# Usage: ./uninstall_crun.sh [--user <username>]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log_functions.sh"
source "$SCRIPT_DIR/../lib/validation_functions.sh"
source "$SCRIPT_DIR/../lib/ui_functions.sh"

# Parse command-line flags
declare -a flag_specs=(
    "--user|-u:value:Target user for crun uninstallation (default: current user)"
    "--help|-h:help:Show this help message"
)

parsed=$(parse_script_flags "$(basename "$0")" \
    "Uninstall crun runtime for target user" \
    "${flag_specs[@]}" -- "$@") || {
    case $? in
        2) exit 0 ;;  # Help was shown
        *) exit 1 ;;  # Parse error
    esac
}

eval "$parsed"
validate_flag_usage || exit 1

# Set default to current user if not specified
TARGET_USER="${user:-$(whoami)}"

# Validate target user exists
if ! id "$TARGET_USER" &>/dev/null; then
    log_error "User '$TARGET_USER' does not exist"
    exit 1
fi

# Get target user details
TARGET_HOME=$(eval echo ~$TARGET_USER)
TARGET_UID=$(id -u "$TARGET_USER")
TARGET_GID=$(id -g "$TARGET_USER")

# Validate TARGET_HOME exists
if sudo [ ! -d "$TARGET_HOME" ]; then
    log_error "Target user home directory does not exist: $TARGET_HOME"
    log_info "Create home directory first: sudo mkdir -p $TARGET_HOME && sudo chown $TARGET_USER:$TARGET_USER $TARGET_HOME"
    exit 1
else
    log_info "$TARGET_HOME: exists"
fi

log_info "Uninstalling crun FOR user: $TARGET_USER (UID: $TARGET_UID)"
log_info "Target home directory: $TARGET_HOME"

# Prerequisites check
check_not_root

log_info "=== UNINSTALLING CRUN ==="

# Remove from common system locations
log_info "Removing crun from system locations..."
[[ -f /usr/bin/crun ]] && sudo rm -f /usr/bin/crun
[[ -f /usr/local/bin/crun ]] && sudo rm -f /usr/local/bin/crun
[[ -f /usr/sbin/crun ]] && sudo rm -f /usr/sbin/crun
[[ -f /usr/local/sbin/crun ]] && sudo rm -f /usr/local/sbin/crun
[[ -f /sbin/crun ]] && sudo rm -f /sbin/crun
[[ -f /bin/crun ]] && sudo rm -f /bin/crun

# Remove from user locations
log_info "Removing crun from user locations: $TARGET_HOME"
sudo [ -f "$TARGET_HOME/.local/bin/crun" ] && sudo rm -f "$TARGET_HOME/.local/bin/crun"
sudo [ -f "$TARGET_HOME/bin/crun" ] && sudo rm -f "$TARGET_HOME/bin/crun"
sudo find "$TARGET_HOME/.local/lib" -type f -name "libcrun*" -delete && \
    log_info "Removed libcrun library files" || \
    log_info "No libcrun library files found to remove"

# Clean up build directories (safe guards)
log_info "Cleaning up build directories..."
[[ -d /tmp/crun ]] && rm -rf /tmp/crun*
# [[ sudo -d "$TARGET_HOME/crun" ]] && sudo rm -rf "$TARGET_HOME/crun"*
sudo [ -d "$TARGET_HOME/crun" ] && sudo rm -rf "$TARGET_HOME/crun"*

# Clean up remaining artifacts
log_info "Cleaning up remaining artifacts..."
#[[ -d "$TARGET_HOME/.local/lib" ]] && sudo rm -rf "$TARGET_HOME/.local/lib/libcrun"*
#[[ -f "$TARGET_HOME/.local/share/man/man1/crun.1" ]] && sudo rm -f "$TARGET_HOME/.local/share/man/man1/crun.1"
sudo [ -d "$TARGET_HOME/.local/lib" ] && sudo rm -rf "$TARGET_HOME/.local/lib/libcrun"*
sudo [ -f "$TARGET_HOME/.local/share/man/man1/crun.1" ] && sudo rm -f "$TARGET_HOME/.local/share/man/man1/crun.1"

# Remove system-installed crun package
log_info "Removing crun packages..."
sudo apt remove --purge -y crun 2>/dev/null || true

# Check if it was installed via other package managers
sudo snap remove crun 2>/dev/null || true
flatpak uninstall crun 2>/dev/null || true

# Verification
log_info "Verifying crun removal..."
if command -v crun &>/dev/null; then
    log_warning "crun still found in PATH: $(which crun)"
else
    log_success "no more crun in PATH"
fi

if find /usr -name "crun" 2>/dev/null | grep -q .; then
    log_warning "crun still found in /usr"
else
    log_success "No more system crun"
fi

log_success "crun uninstalled for user: $TARGET_USER"
