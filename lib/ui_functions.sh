#!/bin/bash
# PURPOSE: Interactive user interface functions incl. a flag sanitized parser
# USAGE: Source this file after log_functions.sh and compose_parser_functions.sh
# OWNER: XCS HornetGit
# LICENCE: MIT

# Select podman-compose file to use with arrow key navigation
select_compose_file() {
    local -a files=($(detect_compose_files))
    local selected_file=""

    if [ ${#files[@]} -eq 0 ]; then
        log_error "No podman-compose files found in current directory"
        return 1
    elif [ ${#files[@]} -eq 1 ]; then
        selected_file="${files[0]}"
        log_info "Using compose file: $(basename "$selected_file")"
    else
        log_info "Multiple podman-compose files detected. Use ↑/↓ arrows to navigate, Enter to select:"
        echo ""

        local current=0
        local max=$((${#files[@]} - 1))

        # Function to display the menu
        display_menu() {
            local is_refresh=$1

            # If refreshing, move cursor up to overwrite previous menu
            if [ "$is_refresh" = "1" ]; then
                # Move cursor up by number of files
                for ((i=0; i<${#files[@]}; i++)); do
                    echo -ne "\033[A"  # Move up one line
                done
            fi

            # Display files with selection indicator, clearing each line
            for i in "${!files[@]}"; do
                local file="${files[$i]}"
                local basename=$(basename "$file")
                local env_type=""

                # Extract environment type from filename
                if [[ "$basename" == *"dev"* ]]; then
                    env_type=" (Development)"
                elif [[ "$basename" == *"prod"* ]]; then
                    env_type=" (Production)"
                fi

                # Clear the line and display content
                echo -ne "\033[K"  # Clear to end of line
                if [ $i -eq $current ]; then
                    echo -e "  ${GREEN}▶ $basename$env_type${NC}"
                else
                    echo "    $basename$env_type"
                fi
            done
        }

        # Initial menu display
        display_menu 0

        # Handle arrow key navigation
        while true; do
            # Read single character without requiring Enter
            read -rsn1 key

            case "$key" in
                $'\x1b')  # ESC sequence
                    read -rsn2 key  # Read the rest of the escape sequence
                    case "$key" in
                        '[A')  # Up arrow
                            current=$(( current > 0 ? current - 1 : max ))
                            display_menu 1
                            ;;
                        '[B')  # Down arrow
                            current=$(( current < max ? current + 1 : 0 ))
                            display_menu 1
                            ;;
                    esac
                    ;;
                '')  # Enter key
                    selected_file="${files[$current]}"
                    break
                    ;;
                'q'|'Q')  # Quit
                    log_error "Selection cancelled by user"
                    return 1
                    ;;
            esac
        done

        echo ""
        log_success "Selected: $(basename "$selected_file")"
    fi

    # Export the selected file for use by other functions
    export SELECTED_COMPOSE_FILE="$selected_file"
    echo "$selected_file"
}

# Secure removal function - handles files, directories, and arrays
# scripting in progress, test soon, see test_rm_secure.sh
# TODO

# Select environment file to use with arrow key navigation
select_env_file() {
    local -a env_files=()

    # Look for .env files (exclude .env itself if it exists)
    for file in .env.example .env.dev .env.prod; do
        if [[ -f "$file" ]]; then
            env_files+=("$file")
        fi
    done

    local selected_file=""

    if [ ${#env_files[@]} -eq 0 ]; then
        log_error "No environment template files found (.env.example, .env.dev, .env.prod)"
        return 1
    elif [ ${#env_files[@]} -eq 1 ]; then
        selected_file="${env_files[0]}"
        log_info "Using environment file: $(basename "$selected_file")"
    else
        log_info "Multiple environment files detected. Use ↑/↓ arrows to navigate, Enter to select:"
        echo ""

        local current=0
        local max=$((${#env_files[@]} - 1))

        # Function to display the menu
        display_env_menu() {
            local is_refresh=$1

            # If refreshing, move cursor up to overwrite previous menu
            if [ "$is_refresh" = "1" ]; then
                # Move cursor up by number of files
                for ((i=0; i<${#env_files[@]}; i++)); do
                    echo -ne "\033[A"  # Move up one line
                done
            fi

            # Display files with selection indicator, clearing each line
            for i in "${!env_files[@]}"; do
                local file="${env_files[$i]}"
                local basename=$(basename "$file")
                local env_type=""

                # Extract environment type from filename
                if [[ "$basename" == *"dev"* ]]; then
                    env_type=" (Development)"
                elif [[ "$basename" == *"prod"* ]]; then
                    env_type=" (Production)"
                elif [[ "$basename" == *"example"* ]]; then
                    env_type=" (Template)"
                fi

                # Clear the line and display content
                echo -ne "\033[K"  # Clear to end of line
                if [ $i -eq $current ]; then
                    echo -e "  ${GREEN}▶ $basename$env_type${NC}"
                else
                    echo "    $basename$env_type"
                fi
            done
        }

        # Initial menu display
        display_env_menu 0

        # Handle arrow key navigation
        while true; do
            # Read single character without requiring Enter
            read -rsn1 key

            case "$key" in
                $'\x1b')  # ESC sequence
                    read -rsn2 key  # Read the rest of the escape sequence
                    case "$key" in
                        '[A')  # Up arrow
                            current=$(( current > 0 ? current - 1 : max ))
                            display_env_menu 1
                            ;;
                        '[B')  # Down arrow
                            current=$(( current < max ? current + 1 : 0 ))
                            display_env_menu 1
                            ;;
                    esac
                    ;;
                '')  # Enter key
                    selected_file="${env_files[$current]}"
                    break
                    ;;
                'q'|'Q')  # Quit
                    log_error "Selection cancelled by user"
                    return 1
                    ;;
            esac
        done

        echo ""
        log_success "Selected: $(basename "$selected_file")"
    fi

    # Export the selected file for use by other functions
    export SELECTED_ENV_FILE="$selected_file"
    echo "$selected_file"
}

# Parse command-line flags with type validation
# Returns KEY=VALUE pairs via stdout (pure function, no exports)
# Flag spec format: "--flag-name|-f:TYPE:description"
# Supported types: help, value, cidr, bool, int
# Usage: parse_script_flags "script.sh" "Description" specs[@] -- "$@"
parse_script_flags() {
    local script_name="$1"
    local usage_desc="$2"
    shift 2

    [[ $# -eq 0 ]] && {
        log_error "No arguments provided" >&2
        return 1
    }

    # Collect flag specifications until we hit '--'
    local -a flag_specs=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do
        flag_specs+=("$1")
        shift
    done

    [[ "$1" == "--" ]] && shift  # Skip separator

    [[ ${#flag_specs[@]} -eq 0 ]] && {
        log_error "No flag specifications provided" >&2
        return 1
    }
    local -A flag_map=()
    local -A type_map=()
    local -A desc_map=()

    # Parse flag specifications
    local spec
    for spec in "${flag_specs[@]}"; do
        IFS=':' read -r flag_names type description <<< "$spec"

        [[ -z "$flag_names" || -z "$type" ]] && {
            log_error "Invalid flag spec: $spec" >&2
            return 1
        }

        # Handle multiple flag names (--long|-short)
        IFS='|' read -ra names <<< "$flag_names"
        local primary_name="${names[0]}"
        local var_name="${primary_name#--}"
        var_name="${var_name//-/_}"

        local name
        for name in "${names[@]}"; do
            flag_map["$name"]="$var_name"
            type_map["$var_name"]="$type"
            desc_map["$var_name"]="$description"
        done
    done

    # Show usage helper
    show_flag_usage() {
        echo "Usage: $script_name [OPTIONS]"
        echo ""
        echo "$usage_desc"
        echo ""
        echo "Options:"

        local processed=()
        local spec
        for spec in "${flag_specs[@]}"; do
            IFS=':' read -r flag_names type description <<< "$spec"
            IFS='|' read -ra names <<< "$flag_names"
            local var_name="${flag_map[${names[0]}]}"

            [[ " ${processed[*]} " =~ " ${var_name} " ]] && continue
            processed+=("$var_name")

            local flag_display="${names[*]}"
            flag_display="${flag_display// /|}"

            case "$type" in
                value|cidr|int)
                    printf "    %-30s %s\n" "$flag_display <value>" "$description"
                    ;;
                *)
                    printf "    %-30s %s\n" "$flag_display" "$description"
                    ;;
            esac
        done
    }

    # Parse actual command-line arguments
    local -A values=()

    while [[ $# -gt 0 ]]; do
        local arg="$1"

        [[ ! -v flag_map["$arg"] ]] && {
            log_error "Unknown flag: $arg" >&2
            show_flag_usage >&2
            return 1
        }

        local var_name="${flag_map[$arg]}"
        local type="${type_map[$var_name]}"

        case "$type" in
            help)
                show_flag_usage >&2
                return 2
                ;;
            bool)
                values["$var_name"]="true"
                shift
                ;;
            value)
                [[ -z "${2:-}" ]] && {
                    log_error "Flag $arg requires a value" >&2
                    return 1
                }
                values["$var_name"]="$2"
                shift 2
                ;;
            cidr)
                [[ -z "${2:-}" ]] && {
                    log_error "Flag $arg requires a CIDR value" >&2
                    return 1
                }
                [[ "$2" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || {
                    log_error "Invalid CIDR format: $2" >&2
                    return 1
                }
                values["$var_name"]="$2"
                shift 2
                ;;
            int)
                [[ -z "${2:-}" ]] && {
                    log_error "Flag $arg requires an integer value" >&2
                    return 1
                }
                [[ "$2" =~ ^[0-9]+$ ]] || {
                    log_error "Invalid integer: $2" >&2
                    return 1
                }
                values["$var_name"]="$2"
                shift 2
                ;;
            *)
                log_error "Unknown type: $type" >&2
                return 1
                ;;
        esac
    done

    # Output KEY=VALUE pairs + list of valid vars for validation
    local var
    local -a var_list=()
    for var in "${!values[@]}"; do
        printf '%s="%s"\n' "$var" "${values[$var]}"
        var_list+=("$var")
    done

    # Export list of parsed variable names for auto-validation (space-separated)
    local IFS=' '
    printf '__FLAG_VARS__="%s"\n' "${var_list[*]}"
}

# Auto-validate flag usage: detects variable name mismatches
# Scans calling function for [[ -v var ]] patterns and checks against __FLAG_VARS__
# Usage: Call immediately after 'eval "$parsed"' with no arguments
validate_flag_usage() {
    local valid_vars="${__FLAG_VARS__:-}"
    local caller_line="${BASH_LINENO[0]}"
    local caller_func="${FUNCNAME[1]}"
    local caller_file="${BASH_SOURCE[1]}"

    [[ -z "$valid_vars" ]] && {
        log_warning "validate_flag_usage: No __FLAG_VARS__ found (call after eval parse_script_flags)" >&2
        return 0
    }

    # Extract only the calling function's code
    local func_code
    func_code=$(declare -f "$caller_func" 2>/dev/null)

    [[ -z "$func_code" ]] && {
        log_warning "validate_flag_usage: Cannot extract function code for $caller_func" >&2
        return 0
    }

    # Find all [[ -v var_name ]] and [[ -v var && patterns in the function
    local -a referenced_vars=()
    while IFS= read -r match; do
        [[ -n "$match" ]] && referenced_vars+=("$match")
    done < <(echo "$func_code" | grep -oP '(?<=-v\s)\w+' | sort -u)

    [[ ${#referenced_vars[@]} -eq 0 ]] && return 0  # No vars to validate

    # Check each referenced var exists in parsed flags
    local found_mismatch=0
    local ref_var
    for ref_var in "${referenced_vars[@]}"; do
        [[ " $valid_vars " =~ " $ref_var " ]] || {
            log_error "Variable mismatch: '\$$ref_var' used but not defined in flag_specs" >&2
            log_error "  Valid variables: $valid_vars" >&2
            log_error "  Function: $caller_func() in $caller_file" >&2
            found_mismatch=1
        }
    done

    [[ $found_mismatch -eq 1 ]] && return 1

    log_debug "Flag validation passed for $caller_func()" >&2
    return 0
}

# continue or abort by the user
continue_or_abort() {
    # Usage: continue_or_abort [condition]
    local condition="${1:-false}"
    if [ "$condition" = false ]; then
        read -n1 -p "Press y/Y to continue, any other key to abort: " key
        echo    # move to a new line
        if [[ "$key" =~ [yY] ]]; then
            log_success "Continuing..."
        else
            log_error "Aborted by user."
            exit 1
        fi
    fi
}

# Display completion message with caller script identification and optional continuation prompt
# Usage: 
#   script_complete "message line 1" "message line 2" [continue]
# Examples:
#   script_complete "V13 Stack configured" ".env and compose files created"
#   script_complete "Installation complete" "Services ready" continue
script_completed() {
    local caller_script="${BASH_SOURCE[1]##*/}"
    local msg1="${1:-Operation completed}"
    local msg2="${2:-}"
    local prompt_continue="${3:-false}"

    log_success "$caller_script : $msg1"
    [[ -n "$msg2" ]] && log_success "$msg2"

    [[ "$prompt_continue" == "continue" ]] && continue_or_abort false
    return 0
}