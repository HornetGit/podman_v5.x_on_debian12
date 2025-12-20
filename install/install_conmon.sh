#!/bin/bash
# BUILD CONMON from sources for podman healthcheck support
# OWNER: XCS
# CREATED: 01AUG2025
# UPDATED: 03DEC2025
# Run as: Admin user with sudo (installs system-wide FOR all users)
# Usage: ./install_conmon.sh [--user <username>]
# required LIB: glib-2.0:  sudo apt install -y libglib2.0-dev
# check: podman info | grep -A 5 conmon

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log_functions.sh"
source "$SCRIPT_DIR/../lib/validation_functions.sh"
source "$SCRIPT_DIR/../lib/ui_functions.sh"

# Parse command-line flags
declare -a flag_specs=(
    "--user|-u:value:Target user (for future use, currently installs system-wide)"
    "--help|-h:help:Show this help message"
)

parsed=$(parse_script_flags "$(basename "$0")" \
    "Build and install conmon from source (system-wide installation)" \
    "${flag_specs[@]}" -- "$@") || {
    case $? in
        2) exit 0 ;;  # Help was shown
        *) exit 1 ;;  # Parse error
    esac
}

eval "$parsed"
validate_flag_usage || exit 1

# Note: conmon is installed system-wide to /usr/local/bin (for all users)
# The --user flag is accepted for consistency but not used in this script
TARGET_USER="${user:-$(whoami)}"
log_info "Building conmon (system-wide installation, usable by: $TARGET_USER and all users)"

# Prerequisites check
check_not_root

log_info "=== BUILD CONMON (for healthcheck support) ==="

# Remove any existing Debian conmon package
# sudo apt remove --purge -y conmon 2>/dev/null || true

cd /tmp
[[ -d "/tmp/conmon" ]] && rm -rf /tmp/conmon*
git clone https://github.com/containers/conmon.git
cd conmon

# Use latest main branch for most recent healthcheck support
# git checkout v2.1.12  # or use latest main

# Build conmon
make clean
make

# Install to system location
sudo make install

# Verify installation
echo "Conmon version:"
/usr/local/bin/conmon --version || /usr/bin/conmon --version

# Copy to standard location if needed
if [ -f /usr/local/bin/conmon ] && [ ! -f /usr/bin/conmon ]; then
    sudo cp /usr/local/bin/conmon /usr/bin/conmon
fi

log_success "conmon installed system-wide (usable by all users including: $TARGET_USER)"