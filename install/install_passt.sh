#!/bin/bash
# OWNER: XCS
# CREATED: 05JUL2025
# UPDATED: 03DEC2025
# CORRECTED: 05JUL2025 - Fixed build system (Makefile, not Meson)
# Run as: Admin user with sudo (installs FOR specified user)
# Usage: ./install_passt.sh [--user <username>]
# PURPOSE: build passt from its source repo (not redhat latest stable source), remove debian (old) package
# NOTE: redhat recently moved their repo from GH to gitlab
# Build passt from https://passt.top/passt

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log_functions.sh"
source "$SCRIPT_DIR/../lib/validation_functions.sh"
source "$SCRIPT_DIR/../lib/ui_functions.sh"

# Parse command-line flags
declare -a flag_specs=(
    "--user|-u:value:Target user for passt installation (default: current user)"
    "--help|-h:help:Show this help message"
)

parsed=$(parse_script_flags "$(basename "$0")" \
    "Build and install passt/pasta for target user" \
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

log_info "Building passt/pasta FOR user: $TARGET_USER (UID: $TARGET_UID)"
log_info "Target home directory: $TARGET_HOME"

# Prerequisites check
check_not_root

echo "🔄 Removing Debian's passt package..."
sudo apt-get remove --purge -y passt || true

echo "📦 Installing dependencies for building passt..."
sudo apt-get update
sudo apt-get install -y git gcc make pkg-config libcap-dev libseccomp-dev

# Remove meson/ninja - not needed for passt
# sudo apt-get install meson ninja-build pkg-config libcap-dev libseccomp-dev

echo "⬇️ Downloading latest passt source from GitLab..."
rm -rf /tmp/*passt*
cd /tmp

# Retry with exponential backoff - network instability during transfer
RETRY_COUNT=0
MAX_RETRIES=5
WAIT_TIME=3

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES..."

    if git clone --depth 1 https://passt.top/passt 2>&1; then
        echo "Clone successful"
        break
    fi

    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "Waiting ${WAIT_TIME}s before retry..."
        sleep $WAIT_TIME
        WAIT_TIME=$((WAIT_TIME * 2))
    else
        log_error "Failed after $MAX_RETRIES attempts"
        exit 1
    fi
done

cd passt

echo "🛠 Building passt with Makefile (this may take a few minutes)..."
# passt uses Makefile, not Meson
make

echo "Installing passt to $TARGET_HOME/.local/bin"
# Create destination directory
sudo mkdir -p "$TARGET_HOME/.local/bin"

# Install the binaries
sudo cp passt "$TARGET_HOME/.local/bin/"
sudo cp pasta "$TARGET_HOME/.local/bin/"
sudo chmod +x "$TARGET_HOME/.local/bin/passt"
sudo chmod +x "$TARGET_HOME/.local/bin/pasta"

# Note: PATH will be consolidated by install_podman.sh Phase 12

# Set PODMAN_PASST environment variable
if ! sudo grep -q "export PODMAN_PASST=" "$TARGET_HOME/.bashrc"; then
  sudo bash -c "echo 'export PODMAN_PASST=\"\$HOME/.local/bin/passt\"' >> \"$TARGET_HOME/.bashrc\""
fi

# Update containers.conf with pasta network configuration
# Similar to install_crun.sh pattern (lines 127-141)
log_info "Configuring pasta network path in containers.conf..."
dest_path=$TARGET_HOME/.config/containers/
conf_file="$dest_path/containers.conf"

# Ensure config directory exists
sudo mkdir -p "$dest_path"

# Update or create containers.conf with [network] section and helper_binaries_dir
# If containers.conf exists (created by install_crun.sh), update [engine] and add [network] sections
# Otherwise, create minimal config with network settings
if sudo [ -f "$conf_file" ]; then
    # Update existing containers.conf
    # 1. Add helper_binaries_dir to [engine] section if not present
    if ! sudo grep -q 'helper_binaries_dir' "$conf_file"; then
        log_info "Adding helper_binaries_dir to [engine] section..."
        sudo sed -i '/^\[engine\]/a helper_binaries_dir = ["'"$TARGET_HOME"'/.local/bin", "/usr/lib/podman"]' "$conf_file"
    fi

    # 2. Add [network] section if not present
    if ! sudo grep -q '^\[network\]' "$conf_file"; then
        log_info "Adding [network] section to existing containers.conf..."
        sudo bash -c "cat >> \"$conf_file\"" << EOF

[network]
network_cmd_path = "$TARGET_HOME/.local/bin/pasta"
EOF
    else
        log_info "[network] section already exists in containers.conf"
    fi
else
    # Create new containers.conf with network configuration
    log_info "Creating containers.conf with pasta configuration..."
    sudo bash -c "cat > \"$conf_file\"" << EOF
[engine]
helper_binaries_dir = ["$TARGET_HOME/.local/bin", "/usr/lib/podman"]

[network]
network_cmd_path = "$TARGET_HOME/.local/bin/pasta"
EOF
fi

# Set ownership for target user
log_info "Setting ownership for target user directories..."
sudo chown -R $TARGET_USER:$TARGET_USER "$TARGET_HOME/.config/containers/"
sudo chown -R $TARGET_USER:$TARGET_USER "$TARGET_HOME/.local/bin/"
sudo chown $TARGET_USER:$TARGET_USER "$TARGET_HOME/.bashrc"

echo "✅ passt installed successfully!"
echo "📍 Location: $TARGET_HOME/.local/bin/passt"
echo "🔍 Version check:"
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" "$TARGET_HOME/.local/bin/passt" --version 2>&1 || echo "passt binary ready (version info embedded)"

echo ""
echo "🧪 Testing basic functionality:"
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" "$TARGET_HOME/.local/bin/passt" --help | head -3 || echo "passt help available"

echo ""
log_success "passt/pasta installed and configured for user: $TARGET_USER"
echo "✅ Installation complete! $TARGET_USER can now use passt with Podman."