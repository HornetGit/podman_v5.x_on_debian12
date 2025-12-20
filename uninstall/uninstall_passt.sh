#!/bin/bash
# Uninstall passt/pasta binaries
# OWNER: XCS
# CREATED: 03DEC2025
# Run as: Admin user with sudo (uninstalls FOR specified user)
# Usage: ./uninstall_passt.sh [--user <username>]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log_functions.sh"
source "$SCRIPT_DIR/../lib/validation_functions.sh"
source "$SCRIPT_DIR/../lib/ui_functions.sh"

# Parse command-line flags
declare -a flag_specs=(
    "--user|-u:value:Target user for passt uninstallation (default: current user)"
    "--help|-h:help:Show this help message"
)

parsed=$(parse_script_flags "$(basename "$0")" \
    "Uninstall passt/pasta for target user" \
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

log_info "Uninstalling passt/pasta FOR user: $TARGET_USER (UID: $TARGET_UID)"
log_info "Target home directory: $TARGET_HOME"

# Prerequisites check
check_not_root

log_info "=== UNINSTALLING PASST/PASTA ==="

# Remove user-specific binaries
log_info "Removing passt/pasta from user locations: $TARGET_HOME"
sudo [ -f "$TARGET_HOME/.local/bin/passt" ] && sudo rm -f "$TARGET_HOME/.local/bin/passt"
sudo [ -f "$TARGET_HOME/.local/bin/pasta" ] && sudo rm -f "$TARGET_HOME/.local/bin/pasta"

# Clean up build directories (safe guards)
log_info "Cleaning up build directories..."
[[ -d /tmp/passt ]] && rm -rf /tmp/passt*

# Remove PODMAN_PASST environment variable from .bashrc
if sudo grep -q "export PODMAN_PASST=" "$TARGET_HOME/.bashrc" 2>/dev/null; then
    log_info "Removing PODMAN_PASST from $TARGET_HOME/.bashrc..."
    sudo sed -i '/export PODMAN_PASST=/d' "$TARGET_HOME/.bashrc"
fi

# Remove Debian package if installed
log_info "Removing Debian passt package (if any)..."
sudo apt-get remove --purge -y passt 2>/dev/null || true

# Verification
log_info "Verifying passt/pasta removal..."
if command -v passt &>/dev/null; then
    log_warning "passt still found in PATH: $(which passt)"
else
    log_success "✅ passt no longer in PATH"
fi

if command -v pasta &>/dev/null; then
    log_warning "pasta still found in PATH: $(which pasta)"
else
    log_success "✅ pasta no longer in PATH"
fi

log_success "passt/pasta uninstalled for user: $TARGET_USER"
