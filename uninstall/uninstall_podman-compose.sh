#!/bin/bash
# Uninstall podman-compose for target user
# OWNER: XCS
# CREATED: 03DEC2025
# Run as: Admin user with sudo (uninstalls FOR specified user)
# Usage: ./uninstall_podman-compose.sh [--user <username>]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log_functions.sh"
source "$SCRIPT_DIR/../lib/validation_functions.sh"
source "$SCRIPT_DIR/../lib/ui_functions.sh"

# Parse command-line flags
declare -a flag_specs=(
    "--user|-u:value:Target user for podman-compose uninstallation (default: current user)"
    "--help|-h:help:Show this help message"
)

parsed=$(parse_script_flags "$(basename "$0")" \
    "Uninstall podman-compose for target user" \
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
fi

log_info "Uninstalling podman-compose FOR user: $TARGET_USER (UID: $TARGET_UID)"
log_info "Target home directory: $TARGET_HOME"

# Prerequisites check
check_not_root

log_info "=== UNINSTALLING PODMAN-COMPOSE ==="

# Remove from user locations
log_info "Removing podman-compose from user locations: $TARGET_HOME"
sudo [ -f "$TARGET_HOME/.local/bin/podman-compose" ] && sudo rm -f "$TARGET_HOME/.local/bin/podman-compose"
sudo [ -f "$TARGET_HOME/bin/podman-compose" ] && sudo rm -f "$TARGET_HOME/bin/podman-compose"

# Remove system-wide symlink
log_info "Removing system-wide symlink..."
[[ -L /usr/local/bin/podman-compose ]] && sudo rm -f /usr/local/bin/podman-compose

# Remove Debian package if installed
log_info "Removing Debian podman-compose package (if any)..."
sudo apt remove --purge -y podman-compose 2>/dev/null || true

# Verification
log_info "Verifying podman-compose removal..."
if command -v podman-compose &>/dev/null; then
    log_warning "podman-compose still found in PATH: $(which podman-compose)"
else
    log_success "✅ podman-compose no longer in PATH"
fi

# Note about built-in podman compose
if command -v podman &>/dev/null; then
    if podman compose --help &>/dev/null 2>&1; then
        log_info "Note: Built-in 'podman compose' (without dash) is still available from Podman 5.x"
    fi
fi

log_success "podman-compose uninstalled for user: $TARGET_USER"
