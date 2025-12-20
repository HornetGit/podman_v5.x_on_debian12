#!/bin/bash
# PURPOSE: File and directory operations
# USAGE: Source this file after log_functions.sh
# OWNER: XCS HornetGit
# UPDATE: 17DEC2025
# LICENCE: MIT

if ! declare -F log_info >/dev/null 2>&1; then
    LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${LIB_DIR}/log_functions.sh"
fi

# Rule #3: Wrap primitives - validate paths early
# Pure function: no globals, compute root on-demand for security
as_project_path() {
    local rel_path="$1" root full_path canonical_path

    # Compute root fresh (no global state)
    root="$(get_project_root)"
    full_path="${root}/${rel_path}"

    # Resolve canonical path (handles .., symlinks, etc.)
    canonical_path="$(cd "$(dirname "$full_path")" 2>/dev/null && pwd)/$(basename "$full_path")" || return 1

    # Security: Validate canonical path is under project root (prevents directory traversal)
    case "$canonical_path" in
        "${root}"/*|"${root}") printf '%s\n' "$canonical_path" ;;
        *) return 1 ;;
    esac
}

# Backup file with timestamp
backup_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$file" "$backup" || {
        log_error "Failed to backup $file"
        return 1
    }
    log_info "Backed up $file to $backup"
    return 0
}

# Tag a file with profile.mode suffix
# Usage: tag_filename <source_file> <profile> <mode> <extension>
# Example: tag_filename ".env" "full" "dev" "env"
#   Creates: .env.full.dev (tagged copy)
tag_filename() {
    local source_file="$1"
    local profile="$2"
    local mode="$3"
    local extension="$4"

    [[ ! -f "$source_file" ]] && {
        log_error "Source file not found: $source_file"
        return 1
    }

    local dir=$(dirname "$source_file")
    local base=$(basename "$source_file")

    # Build tagged filename
    local tagged_file
    case "$extension" in
        env)
            tagged_file="${dir}/.env.${profile}.${mode}"
            ;;
        yml)
            # podman-compose.yml -> podman-compose.full.dev.yml
            local orig_ext="${base##*.}"
            local name="${base%.*}"
            tagged_file="${dir}/${name}.${profile}.${mode}.${orig_ext}"
            ;;
        traefik|dynamic)
            # Traefik files: traefik.yml -> traefik.dev.yml (mode only, no profile)
            local orig_ext="${base##*.}"
            local name="${base%.*}"
            tagged_file="${dir}/${name}.${mode}.${orig_ext}"
            ;;
        *)
            log_error "Unknown file extension type: $extension"
            return 1
            ;;
    esac

    # Create tagged copy (overwrite if exists - no backup needed for derived artifacts)
    cp "$source_file" "$tagged_file" || {
        log_error "Failed to create tagged copy: $tagged_file"
        return 1
    }

    log_success "Tagged config saved: $(basename "$tagged_file")"
    return 0
}

# Backup dir with timestamp
backup_directory() {
    local directory="$1"
    if [ -d "$directory" ]; then
        local backup="${directory}.backup.$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup"
        # Enable dotglob so hidden files are included in the copy
        local old_dotglob=$(shopt -p dotglob)
        shopt -s dotglob
        cp -r "$directory/"* "$backup/" 2>/dev/null || true
        eval "$old_dotglob"  # Restore previous dotglob setting
        log_info "Backed up directory $directory to $backup"
    else
        log_warning "Directory $directory does not exist, no backup created"
    fi
}

file_exists() {
    local file="$1"
    [[ -f "$file" ]] || {
        log_info "$(basename $file): does not exist"
        if compgen -G "$file*" > /dev/null 2>&1; then
            log_warning "$(basename $file): SIMILAR patterns DO exist"
        fi
        return 1
    }
    log_info "$(basename $file): exists"
    return 0
}

is_empty_file() {
    local file="$1"
    file_exists "$file" || return 0

    [[ -s "$file" ]] && {
        log_info "$file: not empty"
        return 1
    }

    log_info "$file: empty"
    return 0
}

directory_exists() {
    local dir_to_check="$1"
    if [ -d "$dir_to_check" ]; then
        log_info "$dir_to_check: exists"
        if [ "$(ls -A "$dir_to_check")" ]; then
            log_info "$dir_to_check: not empty"
            return 0
        else
            log_info "$dir_to_check: empty"
            return 0
        fi
    else
        log_info "$dir_to_check: does not exist"
        return 1
    fi
}

# Ensure directory exists, create if missing (silent check)
# Returns: 0 on success (exists or created), 1 on failure
# Usage: ensure_directory_exists "/path/to/dir" || { log_error "Failed"; return 1; }
ensure_directory_exists() {
    local dir_path="$1"

    # Guard: parameter required
    [[ -n "$dir_path" ]] || return 1

    # Already exists
    [[ -d "$dir_path" ]] && return 0

    # Create directory
    mkdir -p "$dir_path" 2>/dev/null || return 1

    return 0
}

# Get log directory for a service (creates if missing)
# Returns: /full/path/to/admin/tracking_logs/SERVICE_NAME
# Usage: log_dir=$(get_service_log_dir "nuxt") || return 1
get_service_log_dir() {
    local service_name="$1"

    # Guard: service name required
    [[ -n "$service_name" ]] || {
        log_error "get_service_log_dir: service name required"
        return 1
    }

    # Build path: project_root/admin/tracking_logs/SERVICE_NAME
    local project_root
    project_root="$(get_project_root)" || {
        log_error "get_service_log_dir: failed to get project root"
        return 1
    }

    local log_dir="$project_root/admin/tracking_logs/$service_name"

    # Create directory if missing
    ensure_directory_exists "$log_dir" || {
        log_error "Failed to create log directory for service: $service_name"
        return 1
    }

    # Return path
    printf '%s\n' "$log_dir"
    return 0
}

formatting_template() {
    local template_file="$1"

    file_exists "$template_file" || return 1

    is_empty_file "$template_file" && {
        log_warning "Template is empty: $template_file"
        return 1
    }

    local last_char
    last_char=$(tail -c 1 "$template_file" 2>/dev/null)

    [[ -z "$last_char" ]] && {
        log_debug "Template has trailing newline: $template_file"
        return 0
    }

    echo "" >> "$template_file"
    log_debug "Added trailing newline to: $template_file"
    return 0
}

# Remove section from .env file between BEGIN/END markers
# Usage: remove_env_section <env_file_path> <section_name>
# Example: remove_env_section ".env" "nuxt"
#   Removes content between "# BEGIN nuxt" and "# END nuxt" (inclusive)
remove_env_section() {
    local env_file="$1"
    local section="$2"

    # Guard: parameters required
    [[ -n "$env_file" ]] || {
        log_error "remove_env_section: env_file parameter required"
        return 1
    }
    [[ -n "$section" ]] || {
        log_error "remove_env_section: section parameter required"
        return 1
    }

    # Guard: file must exist
    [[ -f "$env_file" ]] || {
        log_debug "File does not exist (nothing to remove): $env_file"
        return 0
    }

    # Check if section exists
    grep -q "^# BEGIN ${section}$" "$env_file" || {
        log_debug "Section '${section}' not found in $(basename "$env_file") (nothing to remove)"
        return 0
    }

    # Remove section using sed (handles multiple occurrences)
    # Pattern: /^# BEGIN section$/,/^# END section$/d
    sed -i "/^# BEGIN ${section}$/,/^# END ${section}$/d" "$env_file" || {
        log_error "Failed to remove section '${section}' from $env_file"
        return 1
    }

    log_debug "Removed existing section: ${section}"
    return 0
}

# Get octal permissions from directory
get_permission() {
    local path="$1"
    [[ -e "$path" ]] || {
        log_error "Path does not exist: $path"
        return 1
    }
    stat -c '%a' "$path" 2>/dev/null
}

# Get owner username from directory
get_owner() {
    local path="$1"
    [[ -e "$path" ]] || {
        log_error "Path does not exist: $path"
        return 1
    }
    stat -c '%U' "$path" 2>/dev/null
}

# Get group name from directory
get_group() {
    local path="$1"
    [[ -e "$path" ]] || {
        log_error "Path does not exist: $path"
        return 1
    }
    stat -c '%G' "$path" 2>/dev/null
}

# Apply permissions and ownership to directory
apply_permissions() {
    local path="$1"
    local owner="$2"
    local group="$3"
    local perms="$4"

    [[ -e "$path" ]] || {
        log_error "Path does not exist: $path"
        return 1
    }

    chown "${owner}:${group}" "$path" 2>/dev/null || {
        log_error "Failed to set ownership on: $path"
        return 1
    }

    chmod "$perms" "$path" 2>/dev/null || {
        log_error "Failed to set permissions on: $path"
        return 1
    }

    return 0
}

# Create directory with .gitkeep file (preserves empty dirs in git)
create_directory_with_gitkeep() {
    local rel_path="$1"
    local target_user="$2"
    local project_root full_path
    local target_uid=$(id -u "$target_user")
    local target_gid=$(id -g "$target_user")

    # Guard : validate  target_user
    [[ -n "$target_user" ]] || {
        log_error "create_directory_with_gitkeep: missing target_user parameter"
        return 1
    }

    # Guard : validate rootless
    if [[ $target_uid -le 1000 ]]; then
        log_error "create_directory_with_gitkeep: must be rootless user"
        return 1
    fi

    if [[ $target_gid -eq 0 ]]; then
        log_error "create_directory_with_gitkeep: must be rootless group"
        return 1
    fi

    # Guard: Validate input parameter
    [[ -n "$rel_path" ]] || {
        log_error "create_directory_with_gitkeep: missing rel_path parameter"
        return 1
    }

    # Guard: Get project root
    project_root=$(get_project_root) || {
        log_error "Failed to determine project root"
        return 1
    }

    full_path="${project_root}/${rel_path}"

    # Guard: Create directory if needed
    [[ -d "$full_path" ]] || {
        mkdir -p "$full_path" || {
            log_error "Failed to create directory: $rel_path"
            return 1
        }
        log_info "Created directory: $rel_path"
    }

    # Guard: Create .gitkeep if missing (skip if not writable or has content)
    if [[ ! -f "${full_path}/.gitkeep" ]]; then
        # Skip .gitkeep if directory has content (e.g., cloned repo) or is not writable
        local file_count
        file_count=$(find "$full_path" -maxdepth 1 -type f 2>/dev/null | wc -l)
        if [[ "$file_count" -eq 0 ]]; then
            touch "${full_path}/.gitkeep" 2>/dev/null || {
                # If touch fails, directory may be owned by target_user from prior run
                log_debug "Skipping .gitkeep (dir exists, not writable): $rel_path"
            }
        fi
    fi

    # DEFERRED: chown moved to finalize_ownership() at end of install_wrapper.sh
    # This avoids permission conflicts during stack configuration
    # [[ -d "$full_path" && ! "$rel_path" =~ ^admin ]] && {
    #     chown -R $target_uid:$target_gid "$full_path" || {
    #         log_error "Failed to set ownership for directory: $rel_path"
    #         return 1
    #     }
    #     log_info "Ownership set for: $rel_path"
    # }
    # local parent_path="$full_path"
    # while [[ "$parent_path" != "$project_root" && "$parent_path" != "/" ]]; do
    #     parent_path=$(dirname "$parent_path")
    #     [[ "$parent_path" == "$project_root" ]] && break
    #     if [[ "$parent_path" != "$project_root" && ! "${parent_path#$project_root/}" =~ ^admin ]]; then
    #         chown "$target_uid:$target_gid" "$parent_path" 2>/dev/null || true
    #     fi
    # done

    return 0
}

# Final ownership assignment - call at end of install_wrapper.sh
# Sets ownership of infrastructure directories to target_user (dockeruser)
# Usage: finalize_ownership "dockeruser" "${dirs_array[@]}"
# Note: Caller must filter out admin/ directories before passing array
finalize_ownership() {
    local target_user="${1:-dockeruser}"
    shift
    local -a dirs=("$@")
    local target_uid=$(id -u "$target_user")
    local target_gid=$(id -g "$target_user")
    local project_root
    project_root=$(get_project_root)

    log_info "Final phase: Setting ownership to $target_user..."

    local dir
    for dir in "${dirs[@]}"; do
        local full_path="${project_root}/${dir}"
        [[ -d "$full_path" ]] && {
            sudo chown -R "$target_uid:$target_gid" "$full_path"
            log_success "Ownership set: $dir"
        }
    done

    # Also chown project-level config files read by containers
    local files=(".env" "podman-compose.yml")
    local file
    for file in "${files[@]}"; do
        local full_path="${project_root}/${file}"
        [[ -f "$full_path" ]] && sudo chown "$target_uid:$target_gid" "$full_path"
    done

    return 0
}

# Get canonical volume root from services.conf INFRA array
# Returns the first path matching pattern: ^\.container/[^/]+$
# Usage: volume_root=$(get_canonical_volume_root "$SCRIPT_DIR")
get_canonical_volume_root() {
    local script_dir="${1:-}"
    local services_conf infra_path

    # Guard: script_dir required
    [[ -n "$script_dir" ]] || {
        log_error "get_canonical_volume_root: script_dir parameter required"
        return 1
    }

    services_conf="${script_dir}/../services.conf"

    # Guard: services.conf exists
    [[ -f "$services_conf" ]] || {
        log_error "services.conf not found: $services_conf"
        return 1
    }

    # Source services.conf to get INFRA array
    # shellcheck source=/dev/null
    source "$services_conf" || {
        log_error "Failed to source services.conf"
        return 1
    }

    # Extract volume root: matches ^\.container/[^/]+$ (e.g., .container/mounted_volume)
    for infra_path in "${INFRA[@]}"; do
        [[ "$infra_path" =~ ^\.container/[^/]+$ ]] && {
            printf '%s\n' "$infra_path"
            return 0
        }
    done

    log_error "No volume root found in INFRA array (expected pattern: .container/*)"
    return 1
}
