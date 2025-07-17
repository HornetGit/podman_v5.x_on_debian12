#!/bin/bash
# uninstall any crun installed 
# OWNER: XCS
# CREATED: 03JUL2025
# RUN AS : dockeruser
# TODO: replace rm commands by rm_secure once tested

set -e

# Remove from common system locations
sudo rm -f /usr/bin/crun
sudo rm -f /usr/local/bin/crun
sudo rm -f /usr/sbin/crun
sudo rm -f /usr/local/sbin/crun
sudo rm -f /sbin/crun
sudo rm -f /bin/crun
# Remove from user locations
rm -f ~/.local/bin/crun
rm -f ~/bin/crun
# Clean up build directories
rm -rf /tmp/crun*
rm -rf ~/crun*
# Clean up remaining artifacts first
rm -rf ~/.local/lib/libcrun*
rm -rf ~/.local/share/man/man1/crun.1
# Remove system-installed crun package
sudo apt remove --purge crun
# Check if it was installed via other package managers
sudo snap remove crun 2>/dev/null || true
flatpak uninstall crun 2>/dev/null || true
# Check (these should all return "not found")
crun --version 2>/dev/null || echo "✅ no more crun found"
which crun 2>/dev/null || echo "✅ no more crun in PATH"
find /usr -name "crun" 2>/dev/null || echo "✅ No more system crun"