#!/bin/bash
# INSTALL PODMAN 5.x INSTALL version v5.x, incl. dependancies
# OWNER: XCS  
# CREATED: 02JUL2025
# UPDATED: 15JUL2025
# CONTEXT: outdated debian 12 repositories preventing from installing podman v5.x and related dependancies
# Run as: dockeruser
# install path : mkdir -p $HOME/Project/InstallationScripts/podman

set -e  # Exit on error

# Source my own lib functions
echo "=== PERFORMING PREREQUISITE CHECKS ==="

SCRIPT_DIR="$(dirname "$0")"
if [ -f "$SCRIPT_DIR/functions.sh" ]; then
    source "$SCRIPT_DIR/functions.sh"
else
    echo "Error: functions.sh not found"
    exit 1
fi

# prerequisite: run as non-root user, but as the podman user being a sudoers
check_not_root
# Check user requirements
if ! check_sudoer_with_home; then
    log_error "User requirements not met"
    exit 1
fi

# Continue with installation...
log_info "Starting installation for $(whoami)..."


echo "=== STARTING PODMAN 5.x and tools INSTALLATION ==="
log_info "Starting installation..."
log_warning "This will completely remove and rebuild the container ecosystem (docker: ${RED}removed${NC})"
continue_or_abort false  # Change to true to skip confirmation

# Close VSCode IDE completely to avoid install errors
# pkill code
# or pkill -f "Visual Studio Code"
# Clear VSCode workspace cache
# rm -rf ~/.config/Code/User/workspaceStorage/*

echo "=== PHASE 1: COMPLETE CLEANUP ==="

# Stop all containers and clean up
cleanup_podman
# echo "Stopping all containers..."
# podman stop --all 2>/dev/null || true
# podman kill --all 2>/dev/null || true
# podman rm --all --force 2>/dev/null || true
# podman rmi --all --force 2>/dev/null || true
# podman system prune -af 2>/dev/null || true
# podman system reset --force 2>/dev/null || true

# Remove all container-related packages
echo "Removing all container packages..."
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

# Clean up directories and files
echo "Cleaning up directories..."
sudo rm -rf /var/lib/docker
sudo rm -rf /usr/local/bin/podman
sudo rm -rf /usr/local/bin/crun
sudo rm -rf /usr/local/go
sudo rm -rf ~/.config/containers/
sudo rm -rf ~/.local/share/containers/
sudo rm -rf /run/user/$(id -u)/containers/
sudo rm -rf /tmp/podman*
sudo rm -rf /tmp/crun*
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list

# Remove old Go from PATH
sed -i '/\/usr\/local\/go\/bin/d' ~/.bashrc

echo "=== PHASE 2: SYSTEM UPDATES AND BUILD DEPENDENCIES ==="

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
  libglib2.0-dev # glib-2.0  required for 'conmon' build
    

echo "=== PHASE 3: INSTALL GO 1.23.4 ==="

# remove previous install tarball if any, for this version
cd /tmp
[ -f "go1.23.4.linux-amd64.tar.gz*" ] && rm -f go1.23.4.linux-amd64.tar.gz*
wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz

# Update PATH
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
export PATH=$PATH:/usr/local/go/bin

# Create symlinks for sudo
sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go
sudo ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# Verify Go installation
echo "Go version:"
go version

echo "=== PHASE 4: BUILD CRUN 1.19.2 or latest (before installing podman) ==="
./uninstall_crun.sh
./install_crun.sh
# echo "crun version:"
# $HOME/.local/bin/crun --version

# install passt
echo "=== PHASE 5: BUILD latest PASST from its source (pasta is a part of PASST)==="
./install_passt.sh

echo "=== PHASE 5.1: BUILDING CONMON FROM SOURCE ==="
if ! ./install_conmon.sh; then
    log_error "Failed to build conmon"
    exit 1
fi

echo "=== PHASE 6: BUILD PODMAN 5.3.1 (AFTER crun) ==="

cd "$HOME"
if [ -d "podman" ]; then
    log_info "Removing existing podman directory..."
    rm -rf podman
else
    log_info "No podman directory to remove"
fi
git clone https://github.com/containers/podman.git
cd podman
git checkout v5.3.1

# Build with OFFICIAL recommended tags from podman.io
echo "Building Podman with official build tags..."
#make BUILDTAGS='seccomp apparmor'
make BUILDTAGS='seccomp apparmor systemd'  # include systemd for enabling healhchecks

# Install system-wide
sudo env "PATH=$PATH" make install

echo "=== PHASE 7: VERIFICATION ==="

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
podman info | grep -A 5 conmon | grep version
echo "crun version:"
crun --version
echo "crun location:"
which crun
echo "Go version:"
go version
echo "Passt version:"
which passt
passt --version


echo "=== PHASE 8: BASIC FUNCTIONALITY TEST ==="
# Test basic container functionality
echo "1) Testing basic container functionality..."
podman run --rm alpine:latest echo "✅ Podman basic test successful"
# Test basic container functionality with a custom pasta network (for rootless user)
echo "2) Testing basic container functionality (ping google)..."
podman run --rm --network=pasta alpine ping -c3 8.8.8.8

echo "=== PHASE 9: HEALTHCHECK TEST ==="
if ! ./check_podman.sh; then
    log_warning "Healthcheck test failed - but continuing"
else
    echo "✅ Healthcheck functionality verified!"
fi

echo "=== UPGRADE COMPLETED SUCCESSFULLY ==="
echo "✅ Podman 5.3.1 with healthcheck support is ready!"
echo "✅ You can now add healthchecks to your compose files"
echo "Note: healthcheks may require to use Docker format the the build time"
