#!/bin/bash
# PODMAN 5.x UPGRADE SEQUENCE: build crun from sources for dockeruser only
# OWNER: XCS  
# CREATED: 03JUL2025
# Run as: dockeruser
# uninstall previous crun versions before : ./uninstall_crun.sh
# caveats: actually build the latest crun version instead of the required version

set -e

version=1.19.2
echo "=== BUILD CRUN $version (before podman build) ==="

cd /tmp
rm -rf crun*
git clone https://github.com/containers/crun.git
cd crun
git checkout $version

# Build crun specifically for the rootless (dockeruser)
./autogen.sh
./configure --prefix=$HOME/.local
make
make install

# Level 1: Check binary exists
if [ ! -f "$HOME/.local/bin/crun" ]; then
    log_error "crun binary not found at $HOME/.local/bin/crun"
    exit 1
fi

# Level 2: Check it's executable
if [ ! -x "$HOME/.local/bin/crun" ]; then
    log_error "crun binary exists but is not executable"
    exit 1
fi

# Level 3: Check it runs and returns version
if checkit=$($HOME/.local/bin/crun --version 2>/dev/null); then
    log_success "crun installation verified: $checkit"
else
    log_error "crun binary exists but fails to run"
    exit 1
fi


# Remove any other crun matching lines from PATH
sed -i '/export.*crun/d' ~/.bashrc

# Add to PATH (if not already)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Set podman rootless runtime OCI
# ~/.config/containers/containers.conf
dest_path=$HOME/.config/containers/
crun_filename=containers.conf
mkdir -p "$dest_path"
cat > "$dest_path$crun_filename" << 'EOF'
runtime = "crun"
compose_warning_logs=false
[engine.runtimes]
crun = ["$HOME/.local/bin/crun"]
[engine]
compose_provider = "$HOME/bin/podman-compose"
[network]
network_backend = "netavark"
EOF

# restart the podman socket
systemctl --user restart podman.socket


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
