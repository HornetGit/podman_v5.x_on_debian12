#!/bin/bash
# PURPOSE: Validation and prerequisite checking functions
# USAGE: Source this file after log_functions.sh
# OWNER: XCS HornetGit
# LICENCE: MIT

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root
check_not_root() {
    if [ "$EUID" -eq 0 ]; then
        log_error "This script should NOT be run as root"
        exit 1
    fi
}

# Check if user is in sudoers group and has home directory
check_sudoer_with_home() {
    local current_user=$(whoami)
    local user_id=$(id -u)
    local home_dir="$HOME"

    # Check if user has a proper home directory
    if [ ! -d "$home_dir" ] || [ "$home_dir" = "/" ]; then
        log_error "User $current_user does not have a valid home directory"
        log_error "Expected: /home/$current_user, Found: $home_dir"
        return 1
    fi

    # Check if user is in sudo group (without actually running sudo)
    if ! groups "$current_user" | grep -q '\bsudo\b'; then
        log_error "User $current_user is not in the sudo group"
        log_error "Add user to sudo group: sudo usermod -aG sudo $current_user"
        return 1
    fi

    # Check if user ID is not 0 (additional root check)
    if [ "$user_id" -eq 0 ]; then
        log_error "Running as root user (UID 0) - use a regular user with sudo access"
        return 1
    fi

    log_success "User validation passed:"
    log_info "  User: $current_user (UID: $user_id)"
    log_info "  Home: $home_dir"
    log_info "  Sudo: User is in sudo group (password required)"

    return 0
}

# Check dependencies
check_dependency() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed"
        return 1
    fi
}

check_podman_version() {
    local min_version=$1 #"5.0"
    local current_version=$(podman --version | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    if [[ $(printf '%s\n' "$min_version" "$current_version" | sort -V | head -n1) = "$min_version" ]]; then
        #log_success "Podman version: $current_version"
        return 0
    else
        #log_error "Podman version $current_version is below minimum requirement ($min_version)"
        return 1
    fi
}

# check if crun or runc as OCI engine
check_OCI_engine() {
    local expected="${1:-crun}"  # set "crun" by default
    local current_engine=$(podman info --format "{{.Host.OCIRuntime.Name}}" 2>/dev/null)
   if [[ "$current_engine" == "$expected" ]]; then
        # log_success "Using $expected runtime"
        return 0
    else
        # log_error "$expected runtime not detected"
        return 1
    fi
}

# Check pasta (passt) installation and effectiveness for rootless networking
check_pasta() {
    # Simple check if passt/pasta is installed
    if command -v passt >/dev/null 2>&1; then
        return 0  # passt found
    elif command -v pasta >/dev/null 2>&1; then
        return 0  # pasta found
    else
        return 1  # not found
    fi
}

# Check if running as root
check_rootless() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should NOT be run as root (for rootless Podman)"
        return 1
    fi
}

# Combined prerequisites check function
check_prerequisites() {
    local failed_checks=()

    log_info "Running system prerequisites check..."

    # Check if not running as root
    echo -n "🔍 Checking rootless user..."
    if ! check_not_root; then
        log_error "running as root (rootless required)"
        failed_checks+=("not_root")
    else
        log_success "rootless"
    fi

    # Check if user has sudo with home
    echo -n "🔍 Checking sudo privileges..."
    if ! check_sudoer_with_home; then
        log_error "sudo privileges with home directory required"
        failed_checks+=("sudoer_with_home")
    else
        log_success "sudo available"
    fi

    # Check dependencies
    echo -n "🔍 Checking dependencies..."
    if check_dependency "podman" && check_dependency "podman-compose"; then
        log_success "(podman, podman-compose)"
    else
        log_error "missing dependencies"
        failed_checks+=("dependencies")
    fi

    # Check podman version
    echo -n "🔍 Checking podman version..."
    if check_podman_version "5.0"; then
        log_success "v5+"
    else
        log_error "podman v5+ expected"
        failed_checks+=("podman_version")
    fi

    # Check OCI engine (crun)
    echo -n "🔍 Checking crun as podman engine..."
    if check_OCI_engine "crun"; then
        log_success "using crun at OCI runtime"
    else
        log_error "crun runtime not detected"
        failed_checks+=("oci_engine")
    fi

    # Check pasta networking
    echo -n "🔍 Checking pasta networking..."
    if check_pasta; then
        log_success "pasta available"
    else
        log_error "pasta networking not available"
        failed_checks+=("pasta")
    fi

    # Return results
    if [ ${#failed_checks[@]} -eq 0 ]; then
        log_success "All prerequisites passed"
        return 0
    else
        log_error "Prerequisites failed: ${failed_checks[*]}"
        return 1
    fi
}
