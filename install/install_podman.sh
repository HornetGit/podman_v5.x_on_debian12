#!/usr/bin/bash
# INSTALL PODMAN 5.x with all dependencies
# CREATED: 02JUL2025
# UPDATED: 20DEC2025
# CONTEXT: Debian 12/13 repositories have outdated podman packages preventing healthcheck support
# Run as: Admin user with sudo access (sudoer)
# Target: Installs Podman for specified user (default: podman_user)
# Usage: ./install_podman.sh [--user <username>]
# Repo: https://github.com/HornetGit/podman_v5.x_on_debian12


set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_RUNNER=$(echo ${SUDO_USER:-${USER}})


# Source library functions
source "$SCRIPT_DIR/../lib/constants.sh"
source "$SCRIPT_DIR/../lib/log_functions.sh"
source "$SCRIPT_DIR/../lib/validation_functions.sh"
source "$SCRIPT_DIR/../lib/utility_functions.sh"
source "$SCRIPT_DIR/../lib/ui_functions.sh"
source "$SCRIPT_DIR/../lib/podman_functions.sh"
source "$SCRIPT_DIR/../lib/file_functions.sh"

# Parse command-line flags using shared library function
declare -a flag_specs=(
    "--user|-u:value:Target user for Podman installation (default: podman_user)"
    "--help|-h:help:Show this help message"
)

# Parse flags and eval results
parsed=$(parse_script_flags "$(basename "$0")" \
    "Install Podman 5.3.1 with crun, pasta, conmon, and podman-compose for a target user" \
    "${flag_specs[@]}" -- "$@") || {
    case $? in
        2) exit 0 ;;  # Help was shown
        *) exit 1 ;;  # Parse error
    esac
}

eval "$parsed"
validate_flag_usage || exit 1

# Set default user if not specified
TARGET_USER="${user:-podman_user}"

# Validate target user exists
if ! id "$TARGET_USER" &>/dev/null; then
    log_error "User '$TARGET_USER' does not exist"
    log_info "Create user first: sudo useradd -m -s /bin/bash $TARGET_USER"
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

# Safe Guard: test the "check_not_root" function
if ! command -v check_not_root &> /dev/null; then
    log_error "Error: check_not_root function not found - library import failed"
    exit 1
fi

# prerequisite: run as non-root user, but as the podman user being a sudoers
check_not_root
# Check user requirements
if ! check_sudoer_with_home; then
    log_error "User requirements not met"
    exit 1
fi

# Start installation...
log_title  "=== STARTING PODMAN 5.x and tools INSTALLATION for user: $TARGET_USER (executed by: $(whoami)) ==="
log_info "Installing Podman FOR user: $TARGET_USER (UID: $TARGET_UID)"
log_info "Target home directory: $TARGET_HOME"
log_warning "This will completely remove and rebuild the container ecosystem (docker: ${RED}removed${NC})"
# continue_or_abort false  # Change to true to skip confirmation
continue_or_abort true  # Change to true to skip confirmation (testing)

log_info "=== PHASE 1: COMPLETE CLEANUP ==="
log_info "podman previous install wipe out (pls wait) ..."

# add "force reset" to wipe out all previous custom setups including crun
# Stop all containers and clean up everything for $TARGET_USER
# CC error: this resets this script runner, and not the  target user as expected
# sudo podman system reset --force &>/dev/null || true

if sudo [ -f "/run/user/$TARGET_UID" ]; then
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" podman system reset --force 2>/dev/null
    # echo "sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" podman system reset --force"
else
    log_info "podman system: ALREADY reset for $TARGET_USER"
fi


# NOTE: This ONLY works for the script runner CURRENT USER, NOT for TARGET_USER
# this is another CC massive error
if cleanup_podman; then
    log_success "podman previous install wiped out"
    log_warning "for user: $SCRIPT_RUNNER"
else
    log_error "podman previous install wiped out: FAILED"
fi

# Remove all container-related packages
log_info "Removing all container-related deb packages..."
sudo apt remove --purge -y \
  podman \
  buildah \
  crun \
  conmon \
  containernetworking-plugins \
  containers-common \
  golang-github-containers-common \
  golang-github-containers-image \
  catatonit \
  libsubid4 \
  libyajl2 \
  pigz \
  uidmap \
  passt \
  slirp4netns \
  docker-ce \
  docker-ce-cli \
  docker-buildx-plugin \
  docker-ce-rootless-extras \
  docker-compose-plugin \
  golang-go 2>/dev/null || true
log_success "Removed all container-related deb packages"

# Clean up directories and files
log_info  "Cleaning up directories..."
sudo rm -rf /var/lib/docker || true
sudo rm -rf /usr/local/bin/podman || true
sudo rm -rf "$TARGET_HOME"/.local/bin/podman || true
sudo rm -rf /usr/local/bin/crun  || true
sudo rm -rf "$TARGET_HOME"/.local/bin/crun || true
sudo rm -rf /usr/local/go  || true

# Remove target user's container directories with safety checks
sudo [ -d "$TARGET_HOME/.config/containers" ] && sudo rm -rf "$TARGET_HOME/.config/containers/"
sudo [ -d "$TARGET_HOME/.local/share/containers" ] && sudo rm -rf "$TARGET_HOME/.local/share/containers/"
sudo [ -d "/run/user/$TARGET_UID/containers" ] && sudo rm -rf "/run/user/$TARGET_UID/containers/"
sudo rm -rf /tmp/podman*
sudo rm -rf /tmp/crun*
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
log_success  "File and directories cleaned up"

# Remove Go, PASST, podman socket from PATH for target user .bashrc
log_info "Removing GO, PASST, SOCKET, XDG_RUNTIME_DIR exports from .bashrc ..."
sudo sed -i '/\/usr\/local\/go\/bin/d' "$TARGET_HOME/.bashrc" 2>/dev/null || true
sudo sed -i '/^export PODMAN_PASST=/d' "$TARGET_HOME/.bashrc" 2>/dev/null || true
sudo sed -i '/^export XDG_RUNTIME_DIR=/d' "$TARGET_HOME/.bashrc" 2>/dev/null || true
log_success  "GO, PASST, SOCKET, XDG_RUNTIME_DIR exports PATH from .bashrc : removed"

# Ensure target user owns their home directories
log_info "Setting ownership for target user directories..."
sudo chown -R $TARGET_USER:$TARGET_USER "$TARGET_HOME/.config/" 2>/dev/null || true
sudo chown -R $TARGET_USER:$TARGET_USER "$TARGET_HOME/.local/" 2>/dev/null || true
log_success  "Ownership for target user directories : reset to $TARGET_USER"

echo ""
log_info "=== PHASE 2: SYSTEM UPDATES AND BUILD DEPENDENCIES ==="
log_info "Install build dependencies ..."
sudo apt update

# Upgrade essential system packages first
echo "Upgrading essential system packages..."
sudo apt upgrade -y \
  ca-certificates \
  openssl \
  curl \
  wget \
  gnupg \
  apt-transport-https

# Install build dependencies
echo "Installing build dependencies..."
# "autoreconf" : autotools-dev autoconf automake libtool
sudo apt install -y \
  git \
  make \
  gcc \
  build-essential \
  pkg-config \
  pkgconf \
  libsystemd-dev \
  libgpgme-dev \
  libseccomp-dev \
  libbtrfs-dev \
  libdevmapper-dev \
  libyajl-dev \
  libcap-dev \
  autotools-dev \
  autoconf \
  automake \
  libtool \
  go-md2man \
  libglib2.0-dev \
  uidmap          
 # notes:
 # glib-2.0: required for 'conmon' build 
 # uidmap: newuidmap and newgidmap are REQUIRED for rootless Podman
log_success  "build dependencies installed"


log_info "=== PHASE 3: INSTALL GO 1.23.4 ==="

# remove previous install tarball if any, for this version
cd /tmp
# [ -f "go1.23.4.linux-amd64.tar.gz*" ] && rm -f go1.23.4.linux-amd64.tar.gz*
rm -f go1.23.4.linux-amd64.tar.gz* 2>/dev/null || true
sleep 1
wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
sleep 1
sudo tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz

# Update PATH for target user
sudo bash -c "echo 'export PATH=\$PATH:/usr/local/go/bin' >> \"$TARGET_HOME/.bashrc\""
export PATH=$PATH:/usr/local/go/bin

# debug
# echo "check .bashrc PATH"
# exit

# Create symlinks for sudo
sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go
sudo ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# Verify Go installation
gv=$(go version)
log_info "Installed Go version: $gv"
echo ""

log_info "=== PHASE 4: BUILD CRUN 1.23.4 or latest (before installing podman) ==="
"$SCRIPT_DIR/uninstall_crun.sh" --user "$TARGET_USER" 
"$SCRIPT_DIR/install_crun.sh" --user "$TARGET_USER"

# Fix .bashrc for TARGET_UID to define the TARGET_USER RUN DIRECTORY
sudo loginctl enable-linger $TARGET_USER  # Note: duplicates Phase 8 linger OP, this one for tests
# for debug only: sudo bash -c "echo '# Set XDG_RUNTIME_DIR for rootless podman/crun' >> \"$TARGET_HOME/.bashrc\""
sudo bash -c "echo 'export XDG_RUNTIME_DIR=\"/run/user/\$(id -u)\"' >> \"$TARGET_HOME/.bashrc\""
sudo chown "$TARGET_UID:$TARGET_GID" "$TARGET_HOME/.bashrc"

# check crun version
crun_version=$(sudo $TARGET_HOME/.local/bin/crun --version | head -n 1)
log_info "checked crun_version: $crun_version"

# install passt
log_info "=== PHASE 5: BUILD latest PASST from its source (pasta is a part of PASST)==="
# ./install_passt.sh
"$SCRIPT_DIR/install_passt.sh" --user "$TARGET_USER"

log_info "=== PHASE 5.1: BUILDING CONMON FROM SOURCE ==="
# if ! ./install_conmon.sh; then
if ! "$SCRIPT_DIR/install_conmon.sh" --user "$TARGET_USER"; then
    log_error "Failed to build conmon"
    exit 1
fi

log_info "=== PHASE 6: BUILD PODMAN 5.3.1 (AFTER crun) ==="

if sudo [ -d "$TARGET_HOME/podman" ]; then
    log_info "Removing existing podman directory..."
    sudo rm -rf "$TARGET_HOME/podman"
else
    log_info "No podman directory to remove"
fi

cd /tmp
git clone https://github.com/containers/podman.git
cd podman
git checkout v5.3.1

# Build with OFFICIAL recommended tags from podman.io
# systemd: included for enabling healthchecks
 log_info "Building Podman with official build tags..."
make BUILDTAGS='seccomp apparmor systemd pasta'  # add pasta instead of netavark

# Install system-wide
sudo env "PATH=$PATH" make install


log_info "=== PHASE 7: VERIFICATION ==="
# Update PATH to include user-specific binaries for verification
export PATH="$TARGET_HOME/.local/bin:$TARGET_HOME/bin:$PATH"

# reset podman socket
if ! reset_socket; then
    log_error "Failed to reset podman socket"
    exit 1
fi

# Verify installations
echo "=== Verification Results ==="
echo "Podman version:"
podman --version
echo "Podman location:"
which podman
echo "conmon installed version:"
conmon --version
echo "podman using conmon (might require a socket reset to enable)"
# podman info | grep -A 5 conmon | grep version
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" podman info 2>/dev/null | grep -A 5 conmon | grep version || echo "conmon check skipped (requires podman socket)"
echo "crun version:"
# crun --version
sudo -u "$TARGET_USER" "$TARGET_HOME/.local/bin/crun" --version 2>/dev/null || echo "crun not found for $TARGET_USER"
echo "crun location:"
# which crun
sudo -u "$TARGET_USER" bash -c "which crun" 2>/dev/null || echo "$TARGET_HOME/.local/bin/crun"
echo "Go version:"
go version
echo "Passt version:"
# which passt
# passt --version
sudo -u "$TARGET_USER" bash -c "which passt" 2>/dev/null || echo "$TARGET_HOME/.local/bin/passt"
sudo -u "$TARGET_USER" "$TARGET_HOME/.local/bin/passt" --version 2>&1 | head -3 || echo "passt not found for $TARGET_USER"


log_info "=== PHASE 8: ENABLE SYSTEMD USER LINGER ==="
log_info "Enabling systemd user linger for $TARGET_USER (UID: $TARGET_UID)..."
if sudo loginctl enable-linger $TARGET_UID 2>/dev/null; then
    log_success "Systemd user linger enabled"
else
    log_warning "Could not enable linger (may require systemd or root access)"
fi

# Wait for runtime directory to be created
sleep 2
if [ ! -d "/run/user/$TARGET_UID" ]; then
    log_warning "Runtime directory /run/user/$TARGET_UID not created, creating manually..."
    sudo mkdir -p "/run/user/$TARGET_UID"
    sudo chown $TARGET_USER:$TARGET_USER "/run/user/$TARGET_UID"
    sudo chmod 700 "/run/user/$TARGET_UID"
fi

echo ""
log_info "=== PHASE 8.5: START AND ENABLE PODMAN SOCKET ==="
log_info "Starting and enabling podman socket for $TARGET_USER..."
if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" systemctl --user enable podman.socket 2>/dev/null; then
    log_success "Podman socket enabled"
else
    log_warning "Could not enable podman socket"
fi

if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" systemctl --user start --now podman.socket 2>/dev/null; then
    log_success "Podman socket started"
else
    log_warning "Could not start podman socket (may auto-start on first use)"
fi

# Verify socket is active
if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" systemctl --user is-active --quiet podman.socket; then
    log_success "Podman socket is active"
else
    log_warning "Podman socket may not be active yet"
fi

log_info "=== PHASE 9: BASIC FUNCTIONALITY TEST ==="
# Test basic container functionality
echo "1) Testing basic container functionality..."
# podman run --rm alpine:latest echo "✅ Podman basic test successful"
# sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" podman run --rm alpine:latest echo "✅ Podman basic test successful"
sudo -u "$TARGET_USER" PATH="$TARGET_HOME/.local/bin:$PATH" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" podman run --rm alpine:latest echo "✅ Podman basic test successful"
# Test basic container functionality with a custom pasta network (for rootless user)
echo "2) Testing basic container functionality (ping google)..."
# podman run --rm --network=pasta alpine ping -c3 8.8.8.8
# podman run --rm --cap-add=NET_RAW --network=pasta alpine ping -c3 8.8.8.8
# sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" podman run --rm --cap-add=NET_RAW --network=pasta alpine ping -c3 8.8.8.8
sudo -u "$TARGET_USER" PATH="$TARGET_HOME/.local/bin:$PATH" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" podman run --rm --cap-add=NET_RAW --network=pasta alpine ping -c3 8.8.8.8

log_info "=== PHASE 10: INSTALL PODMAN-COMPOSE ==="
if ! "$SCRIPT_DIR/install_podman-compose.sh" --user "$TARGET_USER"; then
    log_error "Failed to install podman-compose"
    exit 1
fi

log_info "=== PHASE 11: SECURITY VALIDATION ==="
log_success "Podman installation completed!"
echo ""
log_info "For security validation, run podman-security-bench:"
echo "  https://github.com/containers/podman-security-bench"
echo ""
echo "Quick start:"
echo "  git clone https://github.com/containers/podman-security-bench.git"
echo "  cd podman-security-bench"
echo "  sudo ./podman-security-bench.sh"
echo ""

log_info "=== PHASE 12: CONSOLIDATE PATH EXPORTS ==="
# Remove old individual PATH exports to avoid collisions
log_info "Cleaning up old PATH exports from .bashrc..."
sudo sed -i '/export PATH=\"\$HOME\/bin:\$PATH\"/d' "$TARGET_HOME/.bashrc" 2>/dev/null || true
sudo sed -i '/export PATH=\"\$HOME\/.local\/bin:\$PATH\"/d' "$TARGET_HOME/.bashrc" 2>/dev/null || true
sudo sed -i '/export PATH=\"\/usr\/local\/bin:\$PATH\"/d' "$TARGET_HOME/.bashrc" 2>/dev/null || true
sudo sed -i '/export PATH=\"\/usr\/local\/bin:\$HOME\/.local\/bin:\$HOME\/bin:\$PATH:\/usr\/local\/go\/bin\"/d' "$TARGET_HOME/.bashrc" 2>/dev/null || true

# Add single consolidated PATH export if not present (including Go path)
log_info "Adding consolidated PATH to .bashrc..."
sudo bash -c "echo 'export PATH=\"/usr/local/bin:\$HOME/.local/bin:\$HOME/bin:\$PATH:/usr/local/go/bin\"' >> \"$TARGET_HOME/.bashrc\""
sudo chown "$TARGET_UID:$TARGET_GID" "$TARGET_HOME/.bashrc"
log_success "Consolidated PATH added to .bashrc"

log_success "UPGRADE COMPLETED SUCCESSFULLY"
log_success "Podman 5.3.1+ with healthcheck support is ready!"
echo "Healthchecks can now be added to compose files"
echo "Note: healthchecks may require to use Docker format at the build time , 2 steps required: build and run"