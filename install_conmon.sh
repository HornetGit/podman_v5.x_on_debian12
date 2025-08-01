#!/bin/bash
# BUILD CONMON from sources for podman healthcheck support
# OWNER: XCS  
# CREATED: 01AUG2025
# UPDATED: __
# required LIB: glib-2.0:  sudo apt install -y libglib2.0-dev
# check: podman info | grep -A 5 conmon
# Run as: dockeruser

set -e

# echo "=== BUILD CONMON (for healthcheck support) ==="

# Remove any existing Debian conmon package
# sudo apt remove --purge -y conmon 2>/dev/null || true

cd /tmp
rm -rf conmon*
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

#echo "✅ Conmon installation completed"