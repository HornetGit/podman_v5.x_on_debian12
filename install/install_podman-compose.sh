#!/bin/bash
# Install podman-compose from GitHub (latest version)
# OWNER: XCS
# CREATED: 15JUL2025
# UPDATED: 03DEC2025
# Run as: Admin user with sudo (installs FOR specified user)
# Usage: ./install_podman-compose.sh [--user <username>]
# PURPOSE: Install latest podman-compose bypassing outdated Debian package

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log_functions.sh"
source "$SCRIPT_DIR/../lib/validation_functions.sh"
source "$SCRIPT_DIR/../lib/ui_functions.sh"

# Parse command-line flags
declare -a flag_specs=(
    "--user|-u:value:Target user for podman-compose installation (default: current user)"
    "--help|-h:help:Show this help message"
)

parsed=$(parse_script_flags "$(basename "$0")" \
    "Install podman-compose from GitHub for target user" \
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

# prerequisite
sudo loginctl enable-linger "$TARGET_UID"

# Validate TARGET_HOME exists
if sudo [ ! -d "$TARGET_HOME" ]; then
    log_error "Target user home directory does not exist: $TARGET_HOME"
    log_info "Create home directory first: sudo mkdir -p $TARGET_HOME && sudo chown $TARGET_USER:$TARGET_USER $TARGET_HOME"
    exit 1
fi

log_info "Installing podman-compose FOR user: $TARGET_USER (UID: $TARGET_UID)"
log_info "Target home directory: $TARGET_HOME"

# Prerequisites check
check_not_root

echo "=== INSTALLING PODMAN-COMPOSE FROM GITHUB ==="
log_info "Installing latest podman-compose from upstream source"
log_warning "This will replace any existing Debian podman-compose package"
echo ""
log_info "📝 Note: Podman 5.x includes built-in 'podman compose' (without dash)"
log_info "   - Built-in: 'podman compose up -d' (Docker Compose compatibility)"
log_info "   - This script: 'podman-compose up -d' (Python-based, more features)"
log_info "   - Both can coexist and serve different purposes"
echo ""

# Check if podman is installed
if ! command_exists podman; then
    log_error "Podman is not installed. Please install Podman first."
    log_info "Run: ./install_podman.sh"
    exit 1
fi

echo "=== PHASE 1: CLEANUP EXISTING INSTALLATIONS ==="

# Remove Debian package if installed
log_info "Removing Debian podman-compose package (if any)..."
sudo apt remove --purge -y podman-compose 2>/dev/null || true

# Remove existing installations
log_info "Cleaning up existing podman-compose installations..."
# [[ -f "$TARGET_HOME/.local/bin/podman-compose" ]] && sudo rm -f "$TARGET_HOME/.local/bin/podman-compose"
# [[ -f "$TARGET_HOME/bin/podman-compose" ]] && sudo rm -f "$TARGET_HOME/bin/podman-compose"
sudo [ -f "$TARGET_HOME/.local/bin/podman-compose" ] && sudo rm -f "$TARGET_HOME/.local/bin/podman-compose"
sudo [ -f "$TARGET_HOME/bin/podman-compose" ] && sudo rm -f "$TARGET_HOME/bin/podman-compose"
sudo rm -f /usr/local/bin/podman-compose

# Check what was removed
if command_exists podman-compose; then
    log_warning "podman-compose still found in PATH: $(which podman-compose)"
else
    log_success "Previous podman-compose installations removed"
fi

echo "=== PHASE 2: INSTALL FROM GITHUB ==="

# Create bin directory if needed
log_info "Creating $TARGET_HOME/bin directory..."
sudo mkdir -p "$TARGET_HOME/bin"
sudo chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/bin"

# Download latest version from GitHub
log_info "Downloading latest podman-compose from GitHub..."
curl -L https://raw.githubusercontent.com/containers/podman-compose/main/podman_compose.py -o /tmp/podman-compose
sudo cp /tmp/podman-compose "$TARGET_HOME/bin/podman-compose"
rm -f /tmp/podman-compose

# Verify download
if sudo [ ! -f "$TARGET_HOME/bin/podman-compose" ]; then
    log_error "Failed to download podman-compose"
    exit 1
fi

# Set ownership IMMEDIATELY after copy (before any other operations)
log_info "Setting ownership to $TARGET_USER..."
sudo chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/bin/podman-compose"

# Make executable
log_info "Making podman-compose executable..."
sudo chmod +x "$TARGET_HOME/bin/podman-compose"

# Create system-wide symlink for all users
log_info "Creating system-wide symlink..."
sudo ln -sf "$TARGET_HOME/bin/podman-compose" /usr/local/bin/podman-compose

# COMMENTED OUT - will be handled by install_podman.sh Phase 12 - start
# Add ~/bin to PATH if not already present
#if ! sudo grep -q 'export PATH="\$HOME/bin:\$PATH"' "$TARGET_HOME/.bashrc" 2>/dev/null; then
#    log_info "Adding ~/bin to PATH in $TARGET_HOME/.bashrc..."
#    sudo bash -c "echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> \"$TARGET_HOME/.bashrc\""
#else
#    log_info "~/bin already in PATH"
#fi
# COMMENTED OUT - will be handled by install_podman.sh Phase 12 - end

echo "=== PHASE 2.1: INSTALL PYTHON DEPENDENCIES ==="

# Install required Python packages via apt (Debian externally-managed environment)
log_info "Installing required Python dependencies..."
sudo apt install -y python3-dotenv python3-yaml python3-requests 2>&1 | grep -E "Setting up|already" || true
log_success "Python dependencies installed"

echo "=== PHASE 3: VERIFICATION ==="

# Verify installation
log_info "Verifying podman-compose installation..."

# Check if binary exists
if sudo [ ! -f "$TARGET_HOME/bin/podman-compose" ]; then
    log_error "podman-compose binary not found at $TARGET_HOME/bin/podman-compose"
    exit 1
fi

# Check if symlink exists
if [ ! -L "/usr/local/bin/podman-compose" ]; then
    log_warning "System-wide symlink not found at /usr/local/bin/podman-compose"
fi

# # Ensure .local/bin is in PATH for podman access
# if ! sudo grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' "$TARGET_HOME/.bashrc" 2>/dev/null; then
#     sudo bash -c "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> \"$TARGET_HOME/.bashrc\""
# fi

# Ensure /usr/local/bin is in PATH for system-wide binaries (podman, conmon)
# if ! sudo grep -q 'export PATH="/usr/local/bin:\$PATH"' "$TARGET_HOME/.bashrc" 2>/dev/null; then
#     log_info "Adding /usr/local/bin to PATH in $TARGET_HOME/.bashrc..."
#     sudo bash -c "echo 'export PATH=\"/usr/local/bin:\$PATH\"' >> \"$TARGET_HOME/.bashrc\""
# else
#     log_info "/usr/local/bin already in PATH"
# fi

# COMMENTED OUT - duplicate of install_podman.sh Phase 12 - start
# Remove old individual PATH exports (cleanup from previous runs)
#sudo sed -i '/export PATH="$HOME\/bin:$PATH"/d' "$TARGET_HOME/.bashrc"
#sudo sed -i '/export PATH="\$HOME\/.local\/bin:\$PATH"/d' "$TARGET_HOME/.bashrc"
#sudo sed -i '/export PATH="\/usr\/local\/bin:\$PATH"/d' "$TARGET_HOME/.bashrc"
#
# Add single consolidated PATH export if not present
#if ! sudo grep -q 'export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/bin:$PATH"' "$TARGET_HOME/.bashrc" 2>/dev/null; then
#    log_info "Adding consolidated PATH to $TARGET_HOME/.bashrc..."
#    sudo bash -c "echo 'export PATH=\"/usr/local/bin:\$HOME/.local/bin:\$HOME/bin:\$PATH\"' >> \"$TARGET_HOME/.bashrc\""
#else
#    log_info "Consolidated PATH already in .bashrc"
#fi
# COMMENTED OUT - duplicate of install_podman.sh Phase 12 - end

# Check version
log_info "Checking podman-compose version..."
# if version_output=$(PATH="$TARGET_HOME/bin:$TARGET_HOME/.local/bin:$PATH" "$TARGET_HOME/bin/podman-compose" --version 2>&1); then
# if version_output=$(sudo -u "$TARGET_USER" PATH="$TARGET_HOME/bin:$TARGET_HOME/.local/bin:$PATH" "$TARGET_HOME/bin/podman-compose" --version 2>&1); then
# if version_output=$(sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" PATH="$TARGET_HOME/bin:$TARGET_HOME/.local/bin:$PATH" "$TARGET_HOME/bin/podman-compose" --version 2>&1); then
if version_output=$(sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" PATH="/usr/local/bin:$TARGET_HOME/bin:$TARGET_HOME/.local/bin:$PATH" "$TARGET_HOME/bin/podman-compose" --version 2>&1); then
    log_success "podman-compose version: $version_output"
else
    log_error "Failed to get podman-compose version"
    exit 1
fi

# Check Python dependencies
log_info "Checking Python dependencies..."
if python3 -c "import yaml, requests" 2>/dev/null; then
    log_success "Required Python dependencies available"
else
    log_warning "Some Python dependencies might be missing"
    log_info "Install with: sudo apt install python3-yaml python3-requests"
fi

echo "=== PHASE 4: BASIC FUNCTIONALITY TEST ==="

# Test basic functionality
log_info "Testing basic podman-compose functionality..."
# if PATH="$TARGET_HOME/bin:$TARGET_HOME/.local/bin:$PATH" "$TARGET_HOME/bin/podman-compose" --help | head -3 >/dev/null 2>&1; then
# if sudo -u "$TARGET_USER" PATH="$TARGET_HOME/bin:$TARGET_HOME/.local/bin:$PATH" "$TARGET_HOME/bin/podman-compose" --help | head -3 >/dev/null 2>&1; then
# if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" PATH="$TARGET_HOME/bin:$TARGET_HOME/.local/bin:$PATH" "$TARGET_HOME/bin/podman-compose" --help | head -3 >/dev/null 2>&1; then
if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" PATH="/usr/local/bin:$TARGET_HOME/bin:$TARGET_HOME/.local/bin:$PATH" "$TARGET_HOME/bin/podman-compose" --help | head -3 >/dev/null 2>&1; then
    log_success "podman-compose help command works"
else
    log_error "podman-compose help command failed"
    exit 1
fi

# Test built-in podman compose as well (if podman is installed)
if command -v podman &>/dev/null; then
    log_info "Testing built-in 'podman compose' functionality..."
    # if podman compose --help | head -3 >/dev/null 2>&1; then
    # if sudo -u "$TARGET_USER" podman compose --help | head -3 >/dev/null 2>&1; then
    if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" podman compose --help | head -3 >/dev/null 2>&1; then
        log_success "Built-in 'podman compose' also available"
    else
        log_warning "Built-in 'podman compose' not available (expected in Podman 5.x)"
    fi
fi

# Set ownership for target user
log_info "Setting ownership for target user directories..."
# COMMENTED OUT - redundant ownership already done on line 125
#sudo chown -R $TARGET_USER:$TARGET_USER "$TARGET_HOME/bin/"
sudo chown $TARGET_USER:$TARGET_USER "$TARGET_HOME/.bashrc"

log_success "podman-compose installed and configured for user: $TARGET_USER"

echo "=== INSTALLATION COMPLETED SUCCESSFULLY ==="
log_success "podman-compose installation completed!"
echo ""
echo "📍 Installation details:"
echo "   Binary: ~/bin/podman-compose"
echo "   Symlink: /usr/local/bin/podman-compose"
echo "   Version: $version_output"
echo ""
echo "🧪 Usage examples:"
echo "   # Using podman-compose (RECOMMENDED ; Python-based, more features, actively developped):"
echo "   podman-compose --version"
echo "   podman-compose -f docker-compose.yml up -d"
echo "   podman-compose -f docker-compose.yml down"
echo ""
echo "   # Using built-in 'podman compose' command (i.e. built-in by podmanv5.x, with a full 'Docker Compose' compatibility):"
echo "   podman compose version"
echo "   podman compose -f docker-compose.yml up -d"
echo "   podman compose -f docker-compose.yml down"
echo ""
echo "🔄 Both commands coexist and can be used interchangeably for most tasks"
echo "📚 podman-compose docs: https://github.com/containers/podman-compose"
echo "📚 podman compose docs: https://docs.podman.io/en/latest/markdown/podman-compose.1.html"
echo ""