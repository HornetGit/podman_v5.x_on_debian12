#!/bin/bash
# PODMAN 5.x UPGRADE SEQUENCE: build crun from sources for target user
# OWNER: XCS
# CREATED: 03JUL2025
# UPDATED: 03DEC2025
# Run as: Admin user with sudo (installs FOR specified user)
# Usage: ./install_crun.sh [--user <username>]
# uninstall previous crun versions before : ./uninstall_crun.sh
# caveats: actually build the latest crun version instead of the required version

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")
source "$SCRIPT_DIR/../lib/log_functions.sh"
source "$SCRIPT_DIR/../lib/validation_functions.sh"
source "$SCRIPT_DIR/../lib/ui_functions.sh"
source "$SCRIPT_DIR/../lib/podman_functions.sh"

# Parse command-line flags
declare -a flag_specs=(
    "--user|-u:value:Target user for crun installation (default: current user)"
    "--help|-h:help:Show this help message"
)

parsed=$(parse_script_flags "$(basename "$0")" \
    "Build and install crun runtime for target user" \
    "${flag_specs[@]}" -- "$@") || {
    case $? in
        2) exit 0 ;;  # Help was shown
        *) exit 1 ;;  # Parse error
    esac
}

eval "$parsed"
validate_flag_usage || exit 1

# Set default to current user if not specified (allows calling from install_podman.sh)
TARGET_USER="${user:-$(whoami)}"

# Validate target user exists
if ! id "$TARGET_USER" &>/dev/null; then
    log_error "$SCRIPT_NAME User '$TARGET_USER' does not exist"
    exit 1
fi

# Get target user details
TARGET_HOME=$(eval echo ~$TARGET_USER)
TARGET_UID=$(id -u "$TARGET_USER")
TARGET_GID=$(id -g "$TARGET_USER")

# Validate TARGET_HOME exists
if sudo [ ! -d "$TARGET_HOME" ]; then
    log_error "$SCRIPT_NAME Target user home directory does not exist: $TARGET_HOME"
    log_info "$SCRIPT_NAME : Create home directory first: sudo mkdir -p $TARGET_HOME && sudo chown $TARGET_USER:$TARGET_USER $TARGET_HOME"
    exit 1
fi

log_info "$SCRIPT_NAME : Building crun FOR user: $TARGET_USER (UID: $TARGET_UID)"
log_info "$SCRIPT_NAME : Target home directory: $TARGET_HOME"

version=1.22
echo "=== BUILD CRUN ^$version (before podman build) ==="

cd /tmp
[[ -d "/tmp/crun" ]] && rm -rf /tmp/crun*
git clone https://github.com/containers/crun.git
cd crun
git checkout $version

# Build crun specifically for the target user
./autogen.sh
./configure --prefix=$TARGET_HOME/.local
make

# Ensure target directories exist before install
sudo mkdir -p "$TARGET_HOME/.local/bin"
sudo mkdir -p "$TARGET_HOME/.local/lib"
sudo mkdir -p "$TARGET_HOME/.local/share/man/man1"

sudo make
sudo make install

# Fix ownership immediately after install (BEFORE checks)
# This allows file checks to work when admin user installs for different target user
log_info "$SCRIPT_NAME : Setting ownership for target user directories..."
sudo chown -R $TARGET_USER:$TARGET_USER "$TARGET_HOME/.local/"

# Level 1: Check binary exists
# note: sudo is required in case $TARGET_HOME is not owned by the script user
if sudo [ ! -f "$TARGET_HOME/.local/bin/crun" ]; then
    log_error "$SCRIPT_NAME crun binary not found at $TARGET_HOME/.local/bin/crun"
    log_error "$SCRIPT_NAME Checking what was installed:"
    sudo find "$TARGET_HOME/.local" -name "crun" -type f 2>/dev/null || log_error "$SCRIPT_NAME No crun binary found anywhere in $TARGET_HOME/.local"
    exit 1
fi

# Level 2: Check it's executable
if sudo [ ! -x "$TARGET_HOME/.local/bin/crun" ]; then
    log_error "$SCRIPT_NAME crun binary exists but is not executable"
    exit 1
fi

# Ensure runtime directory exists before testing crun
if sudo [ ! -d "/run/user/$TARGET_UID" ]; then
    log_info "$SCRIPT_NAME : Creating runtime directory for $TARGET_USER..."
    sudo mkdir -p "/run/user/$TARGET_UID"
    sudo chown "$TARGET_USER:$TARGET_USER" "/run/user/$TARGET_UID"
    sudo chmod 700 "/run/user/$TARGET_UID"
fi

# Level 3: Check it runs and returns version
if checkit=$(sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" "$TARGET_HOME/.local/bin/crun" --version 2>/dev/null); then
    log_success "crun installation verified: $checkit"
else
    log_error "$SCRIPT_NAME crun binary exists but fails to run"
    echo "expanded command for manual debugging:"
    echo "sudo -u \"$TARGET_USER\" XDG_RUNTIME_DIR=\"/run/user/$TARGET_UID\" \"$TARGET_HOME/.local/bin/crun\" --version"
    exit 1
fi


# Remove any other crun matching lines from PATH for target user
sudo sed -i '/export.*crun/d' "$TARGET_HOME/.bashrc" 2>/dev/null || true
# Note: PATH will be consolidated by install_podman.sh Phase 12

# Set podman rootless runtime OCI
# ~/.config/containers/containers.conf
dest_path=$TARGET_HOME/.config/containers/
crun_filename=containers.conf
sudo mkdir -p "$dest_path"
# cat > "$dest_path$crun_filename" << EOF
sudo bash -c "cat > \"$dest_path$crun_filename\"" << EOF
runtime = "crun"
compose_warning_logs=false
cgroup_manager = "cgroupfs"
[engine.runtimes]
crun = ["$TARGET_HOME/.local/bin/crun"]
[engine]
compose_provider = "$TARGET_HOME/bin/podman-compose"
EOF

# Create registries.conf for image resolution
sudo bash -c "cat > \"$dest_path/registries.conf\"" << EOF
[registries.search]
registries = ['docker.io']
EOF

# Create policy.json for image verification
sudo bash -c "cat > \"$dest_path/policy.json\"" << EOF
{"default": [{"type": "insecureAcceptAnything"}]}
EOF

# Set ownership for target user config files (created above)
# Note: .local/ ownership already set earlier (line 86) after make install
sudo chown -R $TARGET_USER:$TARGET_USER "$TARGET_HOME/.config/containers/"
sudo chown $TARGET_USER:$TARGET_USER "$TARGET_HOME/.bashrc"

# restart the podman socket
# RUNTIME ERR: "Failed to restart podman.socket: Unit podman.socket not found."
# root cause: crun  installation comes first before podman installation if a first full installation
# fix: add a non-fatal exit clause
# Run as target user if different from current user
if [[ "$TARGET_USER" != "$(whoami)" ]]; then
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" systemctl --user restart podman.socket 2>/dev/null || true
else
    systemctl --user restart podman.socket 2>/dev/null || true
fi

log_success "crun installed and configured for user: $TARGET_USER"


# check podman is now reset to crun
# podman info | grep -A10 -i runtime

# Check it with a container, this should show 'crun' as the runtime engine
# podman run --rm alpine echo "test"
# podman info --format="{{.Host.OCIRuntime.Name}}"

# NOTES:
# about podman config: set the crun path into ~/.config/containers/containers.conf
# since :
# Container engines will read containers.conf files in up to three locations in the following order:
# 1. /usr/share/containers/containers.conf
# 2. /etc/containers/containers.conf
# 3. $HOME/.config/containers/containers.conf (Rootless containers ONLY)

# also set or check :
# cat ~/.local/share/containers/storage/ \
# overlay-containers/*/userdata/config.json | \
# jq .ociVersion
