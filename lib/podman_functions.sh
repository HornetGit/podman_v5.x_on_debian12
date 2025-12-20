#!/bin/bash
# PURPOSE: Podman container and service management functions
# USAGE: Source this file after log_functions.sh
# OWNER: XCS HornetGit
# LICENCE: MIT

# Safe guard: source log_functions.sh if not already sourced
# Check if log_info function exists (sentinel for log_functions.sh)
if ! declare -F log_info >/dev/null 2>&1; then
    # Determine library directory relative to this script
    LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${LIB_DIR}/log_functions.sh"
fi

# Check if service is running
service_is_running() {
    local service="$1"
    systemctl --user is-active --quiet "$service" 2>/dev/null
}

# check if a container dockerfile has an ACTIVE healthcheck or not
# ignores commented out healthchecks (lines starting with # or whitespace + #)
detect_healthcheck() {
    local dockerfile="$1"
    [ -f "$dockerfile" ] && grep -q "^[[:space:]]*HEALTHCHECK" "$dockerfile"
}

# define podman build format option (OCI or Dockerfile)
build_with_format() {
    # format: default if no healthcheck in the service docker file
    # format: docker if an healthcheck was detected in the service docker file, to prevent the podman HC bug
    # bug: WARN[0000] HEALTHCHECK is not supported for OCI image format and will be ignored. Must use `docker` format
    # this bug is persistent at least until podman v5.3.1, prevening HC to work as expected
    # solutions: use docker format , or upgrade podman if bug fix in podman v5.5.6+
    # doc: https://stackoverflow.com/questions/76720076/podman-missing-health-check
    local dockerfile="$1"

    # Check if dockerfile exists and has healthcheck
    if [ -f "$dockerfile" ] && detect_healthcheck "$dockerfile"; then
        log_info "HEALTHCHECK detected in $dockerfile, requires --format docker"
        echo "--format docker"
    else
        # Return empty string for default OCI format
        echo ""
    fi
}

# Rebuild containers.conf with all settings from install_podman.sh workflow
# Usage: rebuild_containers_conf [target_user]
# Must be called with sudo -u target_user for proper ownership
rebuild_containers_conf() {
    local target_user="${1:-$(whoami)}"
    local target_home

    # Resolve home directory
    if [ "$target_user" = "$(whoami)" ]; then
        target_home="$HOME"
    else
        target_home=$(eval echo "~$target_user")
    fi

    local dest_path="$target_home/.config/containers/"
    local conf_file="$dest_path/containers.conf"

    # Guard: Only rebuild if containers.conf does not exist
    [[ -f "$conf_file" ]] && return 0

    mkdir -p "$dest_path"

    cat > "$conf_file" << EOF
runtime = "crun"
compose_warning_logs=false
# cgroup_manager = "cgroupfs" : moved to [engine]
# log_level = "error" tihs is only a podman flag, not a containers.conf

[engine.runtimes]
crun = ["$target_home/.local/bin/crun"]

[engine]
cgroup_manager = "cgroupfs"
compose_provider = "$target_home/bin/podman-compose"
helper_binaries_dir = ["$target_home/.local/bin", "/usr/lib/podman", "/usr/local/libexec/podman"]
# note: added /usr/local/libexec/podman to avoid "manually" creating a symlink from 
# Podman searching in /usr/lib/podman and ~/.local/bin

[network]
network_cmd_path = "$target_home/.local/bin/pasta"
EOF

    chown "$target_user:$target_user" "$conf_file"
    chmod 644 "$conf_file"
}

# Clean up podman images, containers and socket (NO RESET applied Vs. destructive action)
cleanup_podman() {
    # Clean up podman containers
    # note that podman system reset --force
    # will entirely WIPE OUT your setup if any,
    # including crun manually installed binaries
    # log_info "Cleaning up podman containers and networks..."

    # check user
    user=$(whoami)
    echo "cleanup_podman executed by: $user"

    # Stop and remove all containers
    podman stop --all 2>/dev/null || true
    sleep 2
    podman kill --all --force 2>/dev/null || true
    sleep 2
    podman rm --all --force 2>/dev/null || true
    sleep 2
    podman rmi --all --force 2>/dev/null || true
    sleep 2
    # added to prevent lock files by podman user
    podman volume prune -f 2>/dev/null || true
    sleep 2

    # Storage manual cleanup for fs overlay (fixes corrupted layers)
    # block is against "Found incomplete layer" podman issue
    # doc: see https://github.com/containers/storage/issues/2184
    local storage_path="$HOME/.local/share/containers/storage"
    if [ -d "$storage_path" ]; then
        # log_info "Performing manual fs overlay storage cleanup..."

        # Remove overlay storage contents (preserves structure)
        rm -rf "$storage_path"/overlay-layers/* 2>/dev/null || true
        rm -rf "$storage_path"/overlay-containers/* 2>/dev/null || true
        rm -rf "$storage_path"/overlay-images/* 2>/dev/null || true
        rm -rf "$storage_path"/cache/* 2>/dev/null || true

        # Clear storage locks and database
        rm -f "$storage_path"/*.lock 2>/dev/null || true
        rm -f "$storage_path"/storage.lock 2>/dev/null || true

        # log_success "Manual storage cleanup completed"
    fi

    # Standard cleanup
    podman system prune -af 2>/dev/null || true
    podman network prune -f 2>/dev/null || true
    # podman system reset --force 2>/dev/null || true

    # Reset podman socket after storage cleanup (ensures clean networking)
    # thus making sure pasta is reset
    #log_info "Resetting podman socket..."
    if reset_socket; then
        return 0
        # log_success "Podman socket reset completed"
    else
        # log_warning "Podman socket reset failed, but continuing with cleanup"
        return 1
    fi

    return 0
}

# called by podman/uninstall_podman.sh
check_podman_uninstall() {
    local chk=0
    local count=0
    local bins=(podman crun passt pasta conmon podman-compose)

    for b in "${bins[@]}"; do
        command -v "$b" >/dev/null 2>&1 && count=$((count+1))
    done
    echo "features still installed: $count"
    [ "$count" -gt 0 ] && chk=1
    return "$chk"
}


# reset podman socket
reset_socket(){
    systemctl --user enable podman.socket
    systemctl --user start --now podman.socket
    systemctl --user status --no-pager podman.socket
    if systemctl --user is-active --quiet podman.socket; then
        if export_podman_socket; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Validate podman-compose configuration (sanity check)
# Usage: validate_compose_config [env_file] [compose_file]
# Returns: 0 if valid, 1 if invalid
validate_compose_config() {
    local env_file="${1:-.env}"
    local compose_file="${2:-podman-compose.yml}"

    # Guard clauses
    [[ -f "$env_file" ]] || {
        log_error "ENV file not found: $env_file"
        return 1
    }

    [[ -f "$compose_file" ]] || {
        log_error "Compose file not found: $compose_file"
        return 1
    }

    log_info "Validating compose configuration..."
    log_debug "  ENV file: $env_file"
    log_debug "  Compose file: $compose_file"

    # Run validation (podman-compose config validates YAML + env vars)
    local validation_output
    local validation_exit_code

    validation_output=$(podman-compose --env-file "$env_file" -f "$compose_file" config 2>&1)
    validation_exit_code=$?

    if [[ $validation_exit_code -ne 0 ]]; then
        log_error "Compose configuration validation failed"
        log_error "Output:"
        echo "$validation_output" >&2
        return 1
    fi

    log_success "Compose configuration is valid"
    return 0
}

get_podman_uid(){
    CURRENT_USER_ID=$(id -u)
    if [ -z "$CURRENT_USER_ID" ] || [ "$CURRENT_USER_ID" -eq 0 ] || [ "$CURRENT_USER_ID" -lt 1001 ]; then
        log_error "Failed to get current user ID or running as non-authorized user"
        return 1
    fi
    echo "$CURRENT_USER_ID"
}

get_podman_socket() {
    # 1. /run/user/1001/podman/podman.sock - Modern systemd user runtime directory
    # 2. /var/run/user/1001/podman/podman.sock - Traditional location (often a symlink)
    # Note:
    # The /run/user/ path is the canonical location. However, there might be system-specific differences
    # it was confirmed /var/run/user/ worked previously, .

    local user_id="$(get_podman_uid)" #"${1:-$(id -u)}"

    # Try modern path first
    local socket_path="/run/user/${user_id}/podman/podman.sock"
    if [[ -S "$socket_path" ]]; then
    echo "$socket_path"
    return 0
    fi

    # Fallback to traditional path
    socket_path="/var/run/user/${user_id}/podman/podman.sock"
    if [[ -S "$socket_path" ]]; then
    echo "$socket_path"
    return 0
    fi

    # Neither found
    log_error "Podman socket not found at either location"
    return 1
}

# Export PODMAN_SOCKET to .bashrc
export_podman_socket() {
    bashrc="$HOME/.bashrc"
    [ ! -f "$bashrc" ] && { echo "ERR: $bashrc not found in export_podman_socket"; return 1; }

    CURRENT_USER_ID=$(id -u)
    new_line="export PODMAN_SOCKET=/run/user/${CURRENT_USER_ID}/podman/podman.sock"
    export PODMAN_SOCKET="/run/user/${CURRENT_USER_ID}/podman/podman.sock"

    # Remove any existing lines containing this export
    sed -i '/PODMAN_SOCKET/d' "$bashrc"

    # Add the export
    echo "$new_line" >> "$bashrc"

    # Source the updated bashrc
    source "$bashrc"

    echo "Updated $bashrc with Podman socket path"
    return 0
}

resolve_podman_config() {
    local user_uid
    local socket_path
    local service_user

    user_uid=$(get_podman_uid) || {
        log_error "Failed to get podman UID" >&2
        return 1
    }

    socket_path=$(get_podman_socket) || {
        log_error "Failed to get podman socket path" >&2
        return 1
    }

    service_user="${USER:-$(whoami)}"

    cat <<-EOF
PODMAN_USER_UID=$user_uid
PODMAN_SOCKET=$socket_path
SERVICE_USER=$service_user
EOF

    log_success "Podman configuration resolved" >&2
}

check_podman_service_up_and_running() {
    local service_name="$1"
    # usage if no input
    if [ -z "$service_name" ]; then
        log_error "No service name provided to: check_podman_service_up_and_running()"
        return 1
    fi
    if podman ps --format "{{.Names}} {{.Status}}" | grep -q "$service_name" | grep -q "Up"; then
        return 0  # running
    else
        return 1  # not running
    fi
}

# Wait for services without healthchecks - just wait until running
wait_for_running() {
    local container_name="$1"
    local timeout="${2:-60}"
    local count=0

    echo "Waiting for $container_name to be running..."
    while [ $count -lt $timeout ]; do
        if podman ps --format "{{.Names}} {{.Status}}" | grep "$container_name" | grep -q "Up"; then
            echo "$container_name is running!"
            return 0
        fi
        sleep 2
        count=$((count + 2))
    done
    echo "Timeout waiting for $container_name to be running"
    return 1
}

# Wait for a service container to stop
wait_for_not_running() {
    local container_name="$1"
    local timeout="${2:-30}"
    local count=0
    
    while [ $count -lt $timeout ]; do
        # if ! podman ps --log-level=error --format "{{.Names}}" | grep -q "^${container_name}$"; then
        if ! podman ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            return 0
        fi
        sleep 2
        count=$((count + 2))
    done
    
    log_warning "Timeout waiting for container to stop: $container_name"
    return 1
}

# Wait for services with healthchecks - wait until healthcheck passes
wait_for_healthy() {
    local container_name="$1"
    local timeout="${2:-120}"
    local count=0

    echo "Waiting for $container_name to be healthy..."
    while [ $count -lt $timeout ]; do
        # local status=$(podman ps --log-level=error --format "{{.Names}} {{.Status}}" | grep "$container_name")
        local status=$(podman ps --format "{{.Names}} {{.Status}}" | grep "$container_name")        
        if [[ "$status" == *"healthy"* ]]; then
            echo "$container_name is healthy!"
            return 0
        fi
        sleep 3
        count=$((count + 3))
    done
    echo "Timeout waiting for $container_name to be healthy"
    return 1
}

# Get podman image name for a given container
get_podman_image_name() {
    # Usage: image_name=$(get_podman_image_name "container_name")
    #        if [[ $? -eq 0 ]] && [[ -n "$image_name" ]]; then
    #            podman rmi "$image_name"
    #        fi
    local container_name="$1"

    # Validate input parameter
    if [[ -z "$container_name" ]]; then
        log_error "get_podman_image_name: Missing required parameter"
        return 1
    fi

    # Get image name for the container
    # local image_name=$(podman ps -a --log-level=error --format "{{.Names}} {{.Image}}" | grep "^${container_name} " | awk '{print $2}' 2>/dev/null)
    local image_name=$(podman ps -a --format "{{.Names}} {{.Image}}" | grep "^${container_name} " | awk '{print $2}' 2>/dev/null)

    if [[ -z "$image_name" ]]; then
        log_debug "get_podman_image_name: No image found for container $container_name"
        return 1
    fi

    echo "$image_name"
    return 0
}

# Get podman OCI engine (default: crun)
get_podman_OCIengine() {
    local expected_engine="${1:-crun}"
    local runtime
    runtime=$(podman info --format '{{.Host.OCIRuntime.Name}}' 2>/dev/null) || return 1
    [[ "$runtime" == "$expected_engine" ]] ||  return 1
    log_success "OCI runtime verified: $expected_engine"
    return 0
}

# Get default permissions that Podman applies to named volumes
get_podman_volume_permissions() {
    local temp_vol="temp-permission-check-$$"
    local mountpoint perms owner group

    podman volume create "$temp_vol" >/dev/null 2>&1 || {
        log_error "Failed to create temporary volume"
        return 1
    }

    mountpoint=$(podman volume inspect "$temp_vol" --format '{{.Mountpoint}}' 2>/dev/null) || {
        log_error "Failed to inspect volume mountpoint"
        podman volume rm "$temp_vol" >/dev/null 2>&1
        return 1
    }

    perms=$(stat -c '%a' "$mountpoint" 2>/dev/null) || {
        log_error "Failed to get permissions"
        podman volume rm "$temp_vol" >/dev/null 2>&1
        return 1
    }

    owner=$(stat -c '%U' "$mountpoint" 2>/dev/null) || {
        log_error "Failed to get owner"
        podman volume rm "$temp_vol" >/dev/null 2>&1
        return 1
    }

    group=$(stat -c '%G' "$mountpoint" 2>/dev/null) || {
        log_error "Failed to get group"
        podman volume rm "$temp_vol" >/dev/null 2>&1
        return 1
    }

    podman volume rm "$temp_vol" >/dev/null 2>&1

    cat <<-EOF
PODMAN_VOL_PERMS=$perms
PODMAN_VOL_OWNER=$owner
PODMAN_VOL_GROUP=$group
EOF

    return 0
}

# Test healthcheck functionality (e.g. the main reason for my podman upgrade to v5.x)
test_healthcheck(){
    local silent="${1:-false}"
    local timeout="${2:-30}"

    # Cleanup function for trap
    cleanup_test_container() {
        podman stop test-health >/dev/null 2>&1 || true
        podman rm test-health >/dev/null 2>&1 || true
    }

    # Ensure cleanup on exit
    trap cleanup_test_container EXIT

    [[ "$silent" != "true" ]] && log_info "Testing healthcheck functionality..." || true

    # debug
    # currentdir=$(pwd)
    # echo "currentdir: $currentdir"
    # echo "running:"
    # podmancommand="podman run -d --name test-health \
    #     --health-cmd="echo 'healthy'" \
    #     --health-interval=5s \
    #     --health-retries=3 \
    #     --health-start-period=2s \
    #     alpine:latest sleep 60"
    # echo "$podmancommand"
    # exit 1

    podman run -d --name test-health \
        --health-cmd="echo 'healthy'" \
        --health-interval=5s \
        --health-retries=3 \
        --health-start-period=2s \
        alpine:latest sleep 30 >/dev/null 2>&1 || {
        [[ "$silent" != "true" ]] && log_error "Failed to start test container" || true
        cleanup_test_container
        trap - EXIT
        return 1
    }

    # Use existing wait_for_healthy function
    if [[ "$silent" != "true" ]]; then
        wait_for_healthy "test-health" "$timeout" || {
            log_error "Healthcheck test failed (timeout after ${timeout}s)"
            cleanup_test_container
            trap - EXIT
            return 1
        }
    else
        # Silent mode: suppress output from wait_for_healthy
        wait_for_healthy "test-health" "$timeout" >/dev/null 2>&1 || {
            cleanup_test_container
            trap - EXIT
            return 1
        }
    fi

    [[ "$silent" != "true" ]] && log_success "Healthcheck working correctly" || true

    # Clean up
    cleanup_test_container
    trap - EXIT
    return 0
}
# ==========================================
# V12-INSPIRED COMMAND EXECUTION PATTERN
# ==========================================
# Imported from /home/dockeruser/Projects/XCS/Dev/Step02/version12/functions.sh
# Purpose: set_command() + run_command() pattern for safer podman command execution

# Podman command file for set_command/run_command pattern
readonly PODMAN_CMD_FILE="/tmp/v13_podman_commands_$$.sh"

# Initialize command file
init_podman_cmd_file() {
    [[ -f "$PODMAN_CMD_FILE" ]] && rm "$PODMAN_CMD_FILE"
    touch "$PODMAN_CMD_FILE"
    chmod +x "$PODMAN_CMD_FILE"
    echo "#!/bin/bash" > "$PODMAN_CMD_FILE"
}

# Set command (write to file) - from V12 functions.sh:92-96
set_command() {
    local msg="$1"
    [[ ! -f "$PODMAN_CMD_FILE" ]] && init_podman_cmd_file
    echo -e "$msg" >> "$PODMAN_CMD_FILE"
    echo -e "sleep 3" >> "$PODMAN_CMD_FILE"
}

# Run command (execute file) - from V12 functions.sh:98-130
run_command() {
    local script_file="$PODMAN_CMD_FILE"

    # Guard: Check if file exists
    [[ ! -f "$script_file" ]] && {
        log_error "Script file not found: $script_file"
        return 1
    }

    # Guard: Check if file is not empty
    [[ ! -s "$script_file" ]] && {
        log_warning "Script file is empty: $script_file"
        return 1
    }

    # Execute the script
    log_info "Executing: $script_file"
    "$script_file"

    # Check result
    local exit_code=$?
    [[ $exit_code -eq 0 ]] && log_success "Command completed successfully" || {
        log_error "Command failed with exit code $exit_code"
        return 1
    }

    return 0
}

# Cleanup command file
cleanup_podman_cmd_file() {
    [[ -f "$PODMAN_CMD_FILE" ]] && rm "$PODMAN_CMD_FILE"
}

# ==========================================
# DIAGNOSTIC FUNCTIONS
# ==========================================

# Diagnostic function to check permissions and ownership of podman-related binaries
# Usage: check_podman_permissions [target_user]
# Output: Plain text report suitable for tee redirection
# Returns: 0 if critical binaries exist, 1 if any critical binary is missing
check_podman_permissions() {
    # local target_user="${1:-$USER}"
    local target_user="${1:?Target user required}"
    local target_home
    local critical_missing=0

    # Resolve home directory
    target_home=$(eval echo "~$target_user")
    # Safe guard: validate home directory exists
    [ -d "$target_home" ] || {
        echo "ERROR: Home directory not found: $target_home"
        return 1
    }

    # if [ "$target_user" = "$USER" ]; then
    #     target_home="$HOME"
    # else
    #     target_home=$(eval echo "~$target_user")
    # fi

    echo "=== Podman Permissions Diagnostic ==="
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Host: $(hostname)"
    echo "User: $target_user"
    echo "Home: $target_home"
    echo ""

    # Helper function to check a single binary
    # Returns: 0 if exists, 1 if missing
    check_binary() {
        local name="$1"
        local path="$2"
        local is_critical="${3:-false}"  # Third parameter: true for critical binaries

        echo "--- $name ---"
        if sudo [ -e "$path" ] || sudo [ -L "$path" ]; then
            echo "Path: $path"
            echo "Exists: yes"

            # Check if symlink
            if sudo [ -L "$path" ]; then
                echo "Type: symlink"
                local link_target=$(sudo readlink "$path" 2>/dev/null || echo 'cannot read link')
                local real_path=$(sudo readlink -f "$path" 2>/dev/null || echo 'cannot resolve')
                echo "Link target: $link_target"
                echo "Real path: $real_path"

                # Check if target exists
                if sudo [ -e "$real_path" ]; then
                    echo "Target exists: yes"
                    # Get permissions of the target
                    local target_perms=$(sudo stat -c '%a' "$real_path" 2>/dev/null)
                    local target_owner=$(sudo stat -c '%U' "$real_path" 2>/dev/null)
                    local target_group=$(sudo stat -c '%G' "$real_path" 2>/dev/null)
                    echo "Target permissions: $target_perms"
                    echo "Target owner: $target_owner"
                    echo "Target group: $target_group"
                else
                    echo "Target exists: no (broken symlink)"
                fi
            else
                echo "Type: regular file"
            fi

            # Permissions (octal) of the link itself
            local perms=$(sudo stat -c '%a' "$path" 2>/dev/null)
            echo "Permissions: $perms"

            # Owner of the link itself
            local owner=$(sudo stat -c '%U' "$path" 2>/dev/null)
            echo "Owner: $owner"

            # Group of the link itself
            local group=$(sudo stat -c '%G' "$path" 2>/dev/null)
            echo "Group: $group"

            # Size
            if ! sudo [ -L "$path" ]; then
                local size=$(sudo stat -c '%s' "$path" 2>/dev/null)
                echo "Size: $size bytes"
            fi

            # Executable check
            if sudo [ -x "$path" ]; then
                echo "Executable: yes"
            else
                echo "Executable: no"
            fi
        else
            echo "Path: $path"
            echo "Exists: no"
            # Track if critical binary is missing
            if [ "$is_critical" = "true" ]; then
                critical_missing=1
            fi
        fi
        echo ""
    }

    # Check system-wide binaries (might be symlinks)
    check_binary "podman (system)" "/usr/local/bin/podman" "true"
    check_binary "conmon (system)" "/usr/local/bin/conmon" "true"

    # Check user-specific binaries (might be symlinks)
    check_binary "crun (user)" "$target_home/.local/bin/crun" "true"
    check_binary "passt (user)" "$target_home/.local/bin/passt" "false"
    check_binary "pasta (user)" "$target_home/.local/bin/pasta" "false"
    check_binary "podman-compose (user)" "$target_home/bin/podman-compose" "true"
    check_binary "podman-compose (system symlink)" "/usr/local/bin/podman-compose" "false"

    # Check configuration files
    echo "--- Configuration Files ---"
    local config_dir="$target_home/.config/containers"
    echo "Config directory: $config_dir"
    if sudo [ -d "$config_dir" ]; then
        echo "Exists: yes"
        echo "Permissions: $(sudo stat -c '%a' "$config_dir" 2>/dev/null)"
        echo "Owner: $(sudo stat -c '%U' "$config_dir" 2>/dev/null)"
        echo ""

        # Check containers.conf
        local containers_conf="$config_dir/containers.conf"
        if sudo [ -f "$containers_conf" ]; then
            echo "containers.conf: exists"
            echo "Permissions: $(sudo stat -c '%a' "$containers_conf" 2>/dev/null)"
            echo "Owner: $(sudo stat -c '%U' "$containers_conf" 2>/dev/null)"
        else
            echo "containers.conf: not found"
        fi
    else
        echo "Exists: no"
    fi
    echo ""

    # Check runtime directory
    echo "--- Runtime Directory ---"
    local target_uid=$(id -u "$target_user" 2>/dev/null)
    if [ -n "$target_uid" ]; then
        local runtime_dir="/run/user/$target_uid"
        echo "Runtime directory: $runtime_dir"
        if sudo [ -d "$runtime_dir" ]; then
            echo "Exists: yes"
            echo "Permissions: $(sudo stat -c '%a' "$runtime_dir" 2>/dev/null)"
            echo "Owner: $(sudo stat -c '%U' "$runtime_dir" 2>/dev/null)"

            # Check podman socket
            local socket_path="$runtime_dir/podman/podman.sock"
            if sudo [ -S "$socket_path" ]; then
                echo "Podman socket: exists"
                echo "Socket path: $socket_path"
                echo "Permissions: $(sudo stat -c '%a' "$socket_path" 2>/dev/null)"
                echo "Owner: $(sudo stat -c '%U' "$socket_path" 2>/dev/null)"
            else
                echo "Podman socket: not found"
            fi
        else
            echo "Exists: no"
        fi
    else
        echo "Cannot determine UID for user: $target_user"
    fi
    echo ""

    echo "=== End of Diagnostic ==="

    # Return status based on critical binaries
    return $critical_missing
}
