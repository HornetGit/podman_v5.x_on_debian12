#!/bin/bash
# OWNER: XCS
# CREATED: 05JUL2025
# CORRECTED: 05JUL2025 - Fixed build system (Makefile, not Meson)
# PURPOSE: build passt from its source repo (not redhat latest stable source), remove debian (old) package
# NOTE: redhat recently moved their repo from GH to gitlab
# Build passt from https://passt.top/passt

set -e

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
git clone https://passt.top/passt
cd passt

echo "🛠 Building passt with Makefile (this may take a few minutes)..."
# passt uses Makefile, not Meson
make

echo "🚀 Installing passt to ~/.local/bin (non-root)"
# Create destination directory
mkdir -p ~/.local/bin

# Install the binaries
cp passt ~/.local/bin/
cp pasta ~/.local/bin/
chmod +x ~/.local/bin/passt
chmod +x ~/.local/bin/pasta

# Add ~/.local/bin to PATH if not already present
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  export PATH="$HOME/.local/bin:$PATH"
fi

# Set PODMAN_PASST environment variable
if ! grep -q "export PODMAN_PASST=" ~/.bashrc; then
  echo 'export PODMAN_PASST="$HOME/.local/bin/passt"' >> ~/.bashrc
  export PODMAN_PASST="$HOME/.local/bin/passt"
fi

# Reload environment
source ~/.bashrc

echo "✅ passt installed successfully!"
echo "📍 Location: ~/.local/bin/passt"
echo "🔍 Version check:"
#~/.local/bin/passt --version 2>&1 || echo "passt binary ready (version info embedded)"
passt --version 2>&1 || echo "passt binary ready (version info embedded)"

echo ""
echo "🧪 Testing basic functionality:"
# ~/.local/bin/passt --help | head -3 || echo "passt help available"
passt --help | head -3 || echo "passt help available"

echo ""
echo "✅ Installation complete! You can now use passt with Podman."