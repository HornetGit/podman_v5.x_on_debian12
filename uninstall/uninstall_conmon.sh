#!/bin/bash
# Uninstall conmon (system-wide)
# OWNER: XCS
# CREATED: 03DEC2025
# Run as: Admin user with sudo (uninstalls system-wide)
# Usage: ./uninstall_conmon.sh [--user <username>]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log_functions.sh"
source "$SCRIPT_DIR/../lib/validation_functions.sh"
source "$SCRIPT_DIR/../lib/ui_functions.sh"

# Parse command-line flags
declare -a flag_specs=(
    "--user|-u:value:Target user (for consistency, conmon is system-wide)"
    "--help|-h:help:Show this help message"
)

parsed=$(parse_script_flags "$(basename "$0")" \
    "Uninstall conmon from system (system-wide uninstallation)" \
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

# Validate target user exists (for consistency with other scripts)
if ! id "$TARGET_USER" &>/dev/null; then
    log_error "User '$TARGET_USER' does not exist"
    exit 1
fi

# Note: conmon is uninstalled system-wide from /usr/local/bin
# The --user flag is accepted for consistency but not used in this script
log_info "Uninstalling conmon (system-wide, affects all users including: $TARGET_USER)"

# Prerequisites check
check_not_root

log_info "=== UNINSTALLING CONMON ==="

# Remove from system locations
log_info "Removing conmon from system locations..."
[[ -f /usr/local/bin/conmon ]] && sudo rm -f /usr/local/bin/conmon
[[ -f /usr/bin/conmon ]] && sudo rm -f /usr/bin/conmon

# Clean up build directories (safe guards)
log_info "Cleaning up build directories..."
[[ -d /tmp/conmon ]] && rm -rf /tmp/conmon*

# Remove Debian package if installed
log_info "Removing Debian conmon package (if any)..."
sudo apt remove --purge -y conmon 2>/dev/null || true

# Verification
log_info "Verifying conmon removal..."
if command -v conmon &>/dev/null; then
    log_warning "conmon still found in PATH: $(which conmon)"
else
    log_success "✅ conmon no longer in PATH"
fi

if find /usr -name "conmon" 2>/dev/null | grep -q .; then
    log_warning "conmon still found in /usr"
else
    log_success "✅ No more system conmon"
fi

log_success "conmon uninstalled system-wide"
