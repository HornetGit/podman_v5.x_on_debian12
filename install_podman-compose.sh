#!/bin/bash
# Install podman-compose from GitHub (latest version)
# OWNER: XCS
# CREATED: 15JUL2025
# Run as: dockeruser (non-root user with sudo access)
# PURPOSE: Install latest podman-compose bypassing outdated Debian package

set -e

# Source shared functions
SCRIPT_DIR="$(dirname "$0")"
if [ -f "$SCRIPT_DIR/functions.sh" ]; then
    source "$SCRIPT_DIR/functions.sh"
else
    echo "Warning: functions.sh not found, using basic logging"
    log_info() { echo "ℹ️  $1"; }
    log_success() { echo "✅ $1"; }
    log_warning() { echo "⚠️  $1"; }
    log_error() { echo "❌ $1"; }
    check_not_root() { 
        if [ "$EUID" -eq 0 ]; then
            log_error "This script should NOT be run as root"
            exit 1
        fi
    }
fi

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
rm -f ~/.local/bin/podman-compose
rm -f ~/bin/podman-compose
sudo rm -f /usr/local/bin/podman-compose

# Check what was removed
if command_exists podman-compose; then
    log_warning "podman-compose still found in PATH: $(which podman-compose)"
else
    log_success "Previous podman-compose installations removed"
fi

echo "=== PHASE 2: INSTALL FROM GITHUB ==="

# Create bin directory if needed
log_info "Creating ~/bin directory..."
mkdir -p ~/bin

# Download latest version from GitHub
log_info "Downloading latest podman-compose from GitHub..."
curl -L https://raw.githubusercontent.com/containers/podman-compose/main/podman_compose.py -o ~/bin/podman-compose

# Verify download
if [ ! -f ~/bin/podman-compose ]; then
    log_error "Failed to download podman-compose"
    exit 1
fi

# Make executable
log_info "Making podman-compose executable..."
chmod +x ~/bin/podman-compose

# Create system-wide symlink for all users
log_info "Creating system-wide symlink..."
sudo ln -sf ~/bin/podman-compose /usr/local/bin/podman-compose

# Add ~/bin to PATH if not already present
if ! echo "$PATH" | grep -q "$HOME/bin"; then
    log_info "Adding ~/bin to PATH in ~/.bashrc..."
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/bin:$PATH"
else
    log_info "~/bin already in PATH"
fi

echo "=== PHASE 3: VERIFICATION ==="

# Source updated bashrc for current session
source ~/.bashrc 2>/dev/null || true

# Verify installation
log_info "Verifying podman-compose installation..."

# Check if command exists
if command_exists podman-compose; then
    log_success "podman-compose found in PATH: $(which podman-compose)"
else
    log_error "podman-compose not found in PATH"
    exit 1
fi

# Check version
log_info "Checking podman-compose version..."
if version_output=$(podman-compose --version 2>&1); then
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
if podman-compose --help | head -3 >/dev/null 2>&1; then
    log_success "podman-compose help command works"
else
    log_error "podman-compose help command failed"
    exit 1
fi

# Test built-in podman compose as well
log_info "Testing built-in 'podman compose' functionality..."
if podman compose --help | head -3 >/dev/null 2>&1; then
    log_success "Built-in 'podman compose' also available"
else
    log_warning "Built-in 'podman compose' not available (expected in Podman 5.x)"
fi

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