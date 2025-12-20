#!/bin/bash
# Uninstall Podman 5.x and all related components for target user
# OWNER: XCS HornetGit
# CREATED: 03DEC2025
# Run as: admin user without sudo (uninstalls FOR specified user), while "sudo" are in-script embedded
# Usage: ./uninstall_podman.sh [--user <username>]
# PURPOSE: Complete removal of custom Podman installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log_functions.sh"
source "$SCRIPT_DIR/../lib/validation_functions.sh"
source "$SCRIPT_DIR/../lib/ui_functions.sh"
source "$SCRIPT_DIR/../lib/podman_functions.sh"

# Parse command-line flags
declare -a flag_specs=(
    "--user|-u:value:Target user for Podman uninstallation (default: current user)"
    "--help|-h:help:Show this help message"
)

parsed=$(parse_script_flags "$(basename "$0")" \
    "Uninstall Podman 5.x and all components for target user" \
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
    log_warning "Target user home directory does not exist: $TARGET_HOME"
    log_info "Proceeding with system-wide cleanup only"
fi

log_title "Uninstalling Podman 5.x FOR user: $TARGET_USER (UID: $TARGET_UID)"
log_info "Target home directory: $TARGET_HOME"

# Prerequisites check
check_not_root

echo ""
log_warning "⚠️  This will remove:"
echo "   - Podman binary and system files"
echo "   - crun runtime"
echo "   - passt/pasta networking"
echo "   - conmon (system-wide)"
echo "   - podman-compose"
echo "   - User configuration files"
echo "   - Containers, images, and volumes for $TARGET_USER"
echo ""

#read -p "Continue? (y/N): " -n 1 -r
REPLY="Y"

echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Uninstallation cancelled"
    exit 0
fi

echo ""
log_info "=== PHASE 1: STOP PODMAN SERVICES ==="

# Stop podman services for target user
log_info "Stopping Podman services for $TARGET_USER..."
if [[ "$TARGET_USER" == "$(whoami)" ]]; then
    systemctl --user stop podman.socket 2>/dev/null || true
    systemctl --user stop podman 2>/dev/null || true
    systemctl --user disable podman* 2>/dev/null || true
    systemctl --user daemon-reload
else
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" systemctl --user stop podman.socket 2>/dev/null || true
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" systemctl --user stop podman 2>/dev/null || true
fi

# Disable linger
log_info "Disabling systemd linger for $TARGET_USER..."
sudo loginctl disable-linger "$TARGET_UID" 2>/dev/null || true

echo ""
log_info "=== PHASE 2: REMOVE USER-SPECIFIC COMPONENTS ==="

# Uninstall podman-compose
log_info "Uninstalling podman-compose..."
"$SCRIPT_DIR/uninstall_podman-compose.sh" --user "$TARGET_USER" || true

# Uninstall crun
log_info "Uninstalling crun..."
"$SCRIPT_DIR/uninstall_crun.sh" --user "$TARGET_USER" || true

# Uninstall passt
log_info "Uninstalling passt/pasta..."
"$SCRIPT_DIR/uninstall_passt.sh" --user "$TARGET_USER" || true

echo ""
log_info "=== PHASE 3: REMOVE SYSTEM-WIDE COMPONENTS (OPTIONAL) ==="

log_warning "System-wide components (Podman binary, conmon, Go) are shared by all users."
#read -p "Remove system-wide components? This affects ALL users! (y/N): " -n 1 -r
REPLY="Y"
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Uninstall conmon (system-wide)
    log_info "Uninstalling conmon (system-wide)..."
    "$SCRIPT_DIR/uninstall_conmon.sh" --user "$TARGET_USER" || true

    # Remove Podman binary
    log_info "Removing Podman binary (system-wide)..."
    [[ -f /usr/local/bin/podman ]] && sudo rm -f /usr/local/bin/podman

    # Remove Go if it was installed by our script
    if [[ -d /usr/local/go ]]; then
        log_info "Removing Go installation (system-wide)..."
        sudo rm -rf /usr/local/go
    fi

    log_success "System-wide components removed"
else
    log_info "Skipping system-wide component removal"
    log_info "System-wide components remain available for other users"
fi

echo ""
log_info "=== PHASE 3.5: CLEAN UP PODMAN STORAGE (PROPER UNMOUNT) ==="


# Run cleanup_podman() as target user to properly unmount overlayfs
log_info "Running podman storage cleanup for $TARGET_USER..."
if [[ "$TARGET_USER" == "$(whoami)" ]]; then
    # Running as target user directly
    cleanup_podman || log_warning "cleanup_podman() failed, continuing with manual cleanup"
else
#     # Running as different user via sudo
#     sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" PATH="/usr/local/bin:$TARGET_HOME/.local/bin:$TARGET_HOME/bin:/usr/bin:/bin" bash -c "
#         source '$SCRIPT_DIR/../lib/log_functions.sh'
#         source '$SCRIPT_DIR/../lib/podman_functions.sh'
#         cleanup_podman
#     " || log_warning "cleanup_podman() failed, continuing with manual cleanup"
# fi

    # Running as different user via sudo
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" PATH="/usr/local/bin:$TARGET_HOME/.local/bin:$TARGET_HOME/bin:/usr/bin:/bin" bash -c "
        source '$SCRIPT_DIR/../lib/podman_functions.sh'
        cleanup_podman" || \
        log_warning "cleanup_podman() failed, continuing with manual cleanup"
fi

log_success "Podman storage properly cleaned up"

echo ""
log_info "=== PHASE 4: CLEAN UP USER DATA ==="

if sudo [ -d "$TARGET_HOME" ]; then

    # force podman reset
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" PATH="/usr/local/bin:$TARGET_HOME/.local/bin:$TARGET_HOME/bin:/usr/bin:/bin" bash -c "
        podman system reset --force
    " || log_warning "podman reset: inoperant redundancy (already uninstalled), keeping trying umount the overlays for a manual cleanup"

    # # Kill any podman processes holding locks
    # sudo pkill -9 -u "$TARGET_UID" podman 2>/dev/null || true
    # sleep 2

    # echo ""
    # log_info "--- PHASE 4.1: KILL REMAINING PODMAN PROCESSES ==="

    # # Kill any lingering podman/conmon/crun processes for target user
    # log_info "Killing any remaining podman-related processes for $TARGET_USER..."
    # if [[ "$TARGET_USER" == "$(whoami)" ]]; then
    #     # Kill own processes
    #     pkill -9 -u $(id -u) podman 2>/dev/null || true
    #     pkill -9 -u $(id -u) conmon 2>/dev/null || true
    #     pkill -9 -u $(id -u) crun 2>/dev/null || true
    # else
    #     # Kill target user's processes
    #     sudo pkill -9 -u "$TARGET_UID" podman 2>/dev/null || true
    #     sudo pkill -9 -u "$TARGET_UID" conmon 2>/dev/null || true
    #     sudo pkill -9 -u "$TARGET_UID" crun 2>/dev/null || true
    # fi

    # # Give kernel time to release file handles
    # sleep 2

    # log_success "All podman processes terminated"

    # Unmount overlays
    log_info "Umounting overlays ..."
    while mount | grep -q "$TARGET_HOME/.local/share/containers/storage"; do
        m=$(mount | grep "$TARGET_HOME/.local/share/containers/storage" | awk '{print $3}')
        sudo umount -l "$m"
    done

    # Fix ownership of stubborn overlay directories (they're owned by root from container mounts)
    log_info "Fixing ownership of overlay directories..."
    if [[ -d "$TARGET_HOME/.local/share/containers/storage/overlay" ]]; then
        sudo chown -R $TARGET_UID:$TARGET_GID "$TARGET_HOME/.local/share/containers/storage/" 2>/dev/null || true
        # Make directories writable before deletion (overlay diff dirs are read-only)
        sudo chmod -R u+w "$TARGET_HOME/.local/share/containers/storage/" 2>/dev/null || true
    fi

    # Remove user-specific Podman data
    log_info "Removing Podman user data for $TARGET_USER..."
    sudo [ -d "$TARGET_HOME/.config/containers" ] && sudo rm -rf "$TARGET_HOME/.config/containers"
    sudo [ -d "$TARGET_HOME/.local/share/containers" ] && sudo rm -rf "$TARGET_HOME/.local/share/containers"
    [[ -d "/run/user/$TARGET_UID/containers" ]] && sudo rm -rf "/run/user/$TARGET_UID/containers"
    [[ -d "/run/user/$TARGET_UID/podman" ]] && sudo rm -rf "/run/user/$TARGET_UID/podman"

    # Clean up .bashrc entries
    log_info "Cleaning up $TARGET_HOME/.bashrc..."
    if sudo [ -f "$TARGET_HOME/.bashrc" ]; then
        # Remove PATH modifications
        sudo sed -i '/export PATH.*\.local\/bin/d' "$TARGET_HOME/.bashrc"
        sudo sed -i '/export PATH.*\/bin/d' "$TARGET_HOME/.bashrc"
        sudo sed -i '/export PATH.*go\/bin/d' "$TARGET_HOME/.bashrc"
        # Remove PODMAN_PASST
        sudo sed -i '/export PODMAN_PASST=/d' "$TARGET_HOME/.bashrc"
    fi

    # Remove empty directories
    log_info "Deleting empty dirs"
    sudo [ -d "$TARGET_HOME/.local/bin" ] && sudo rmdir "$TARGET_HOME/.local/bin" 2>/dev/null || true
    sudo [ -d "$TARGET_HOME/.local" ] && sudo rmdir "$TARGET_HOME/.local" 2>/dev/null || true
    sudo [ -d "$TARGET_HOME/bin" ] && sudo rmdir "$TARGET_HOME/bin" 2>/dev/null || true
fi

echo ""
log_info "=== PHASE 5: CLEAN UP BUILD ARTIFACTS ==="

log_info "Removing build artifacts from /tmp..."
[[ -d /tmp/podman ]] && rm -rf /tmp/podman*
[[ -d /tmp/crun ]] && rm -rf /tmp/crun*
[[ -d /tmp/conmon ]] && rm -rf /tmp/conmon*
[[ -d /tmp/passt ]] && rm -rf /tmp/passt*

echo ""
log_info "=== PHASE 6: VERIFICATION ==="

log_info "Verifying Podman removal..."

# # Check Podman
# if command -v podman &>/dev/null; then
#     log_warning "Podman still found in PATH: $(which podman)"
# else
#     log_success "✅ Podman no longer in PATH"
# fi

# # Check crun
# if command -v crun &>/dev/null; then
#     log_warning "crun still found in PATH: $(which crun)"
# else
#     log_success "✅ crun no longer in PATH"
# fi

# # Check passt
# if command -v passt &>/dev/null; then
#     log_warning "passt still found in PATH: $(which passt)"
# else
#     log_success "✅ passt no longer in PATH"
# fi

# # Check conmon
# if command -v conmon &>/dev/null; then
#     log_warning "conmon still found in PATH: $(which conmon)"
# else
#     log_success "✅ conmon no longer in PATH"
# fi

# # Check podman-compose
# if command -v podman-compose &>/dev/null; then
#     log_warning "podman-compose still found in PATH: $(which podman-compose)"
# else
#     log_success "✅ podman-compose no longer in PATH"
# fi

# final check
if ! check_podman_uninstall; then 
    log_error "One or more of the podman features was still found"
    echo "Hint: check more details with 'check_podman_uninstall'"
    exit 1
fi

echo ""
log_success "=== UNINSTALLATION COMPLETED ==="
log_info "Podman 5.x and all components have been removed for user: $TARGET_USER"
if dpkg -l | grep -E "podman|crun|conmon|passt|podman-compose"; then 
    log_info "Remove remaining Debian packages with:"
    echo "   sudo apt remove --purge podman crun conmon passt podman-compose"
else
    log_info "No existing Debian packages installed"
fi
log_info "Full Diagnostic: run ..."