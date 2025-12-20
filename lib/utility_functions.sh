#!/bin/bash
# PURPOSE: General utility functions
# USAGE: Source this file after log_functions.sh
# OWNER: XCS HornetGit
# LICENCE: MIT

# set file of bash (podman) commands
# purpose: 2-stages podman image build and run
set_command() {
    local msg="$1"
    echo -e "$msg" >> "$podman_cmd"
    echo -e "sleep 3" >> "$podman_cmd"
}

# run bash (podman) commands
# purpose: 2-stages podman image build and run
run_command() {

    local script_file="$podman_cmd"

    # Check if file exists
    if [ ! -f "$script_file" ]; then
        log_error "Script file not found: $script_file"
        return 1
    fi

    # Check if file is not empty
    if [ ! -s "$script_file" ]; then
        log_warning "Script file is empty: $script_file"
        return 1
    fi

    # Remove --verbose flag if DEBUG is false
    if [ "$DEBUG" = false ]; then
        sed -i 's/--verbose //g' "$script_file"
    fi

    # Execute the script
    log_info "Executing: $script_file"
    ./"$script_file"

    # Check result
    if [ $? -eq 0 ]; then
        log_success "Script completed successfully"
    else
        log_error "Script failed with exit code $?"
        return 1
    fi
}

# Test HTTP endpoint with curl and return status
test_endpoint() {
    local url="$1"
    local service="$2"

    printf "%-20s %-50s " "$service" "$url"

    # Test with curl: follow redirects, timeout 10s, show only HTTP status, allow self-signed certificates
    local status=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 10 -L "$url" 2>/dev/null)

    case "$status" in
        200|201|202|301|302|304)
            echo -e "${GREEN}✅ $status${NC}"
            return 0
            ;;
        000)
            echo -e "${RED}❌ Connection failed${NC}"
            return 1
            ;;
        *)
            echo -e "${YELLOW}⚠️  $status${NC}"
            return 1
            ;;
    esac
}

# variable sanity check (on top of 'set -e')
is_variable_set() {

    local myvar_name="$1"
    # log_info "Current value of \$JAIL is '$JAIL' ($HINT) "

    ## Determine if a bash variable is empty or not ##
    if [ -z "${myvar_name}" ]; then
        log_info "$myvar_name is unset or set to the empty string"
        return 1
    fi
    if [ -z "${myvar_name+set}" ]; then
        log_info "$myvar_name is unset"
        return 1
    fi
    if [ -z "${myvar_name-unset}" ]; then
        log_info "$myvar_name is set to the empty string"
        return 1
    fi
    if [ -n "${myvar_name}" ]; then
        log_info "$myvar_name is set to a non-empty string"
        return 0
    fi
    if [ -n "${myvar_name+set}" ]; then
        log_warning "$myvar_name is set, possibly to the empty string"
        return 1
    fi
    if [ -n "${myvar_name-unset}" ]; then
        log_info "$myvar_name is either unset or set to a non-empty string"
        return 1
    fi

}

compare_env_files() {
    # USAGE: compare_env_files_v2 <file1> <file2>
    # Compares environment variable names between two .env files
    # Returns: 0 on success, 1 on error

    local file1="$1"
    local file2="$2"

    # Guard clauses
    [[ -n "$file1" && -n "$file2" ]] || {
        log_error "Usage: compare_env_files_v2 <file1> <file2>"
        return 1
    }

    [[ -f "$file1" ]] || {
        log_error "File not found: $file1"
        return 1
    }

    [[ -f "$file2" ]] || {
        log_error "File not found: $file2"
        return 1
    }

    # Parse variables from both files
    local -A vars1=() vars2=()
    local var_name

    while IFS='=' read -r var_name _; do
        [[ "$var_name" =~ ^[A-Z_][A-Z0-9_]*$ ]] && vars1["$var_name"]=1
    done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$file1" 2>/dev/null)

    while IFS='=' read -r var_name _; do
        [[ "$var_name" =~ ^[A-Z_][A-Z0-9_]*$ ]] && vars2["$var_name"]=1
    done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$file2" 2>/dev/null)

    log_debug "Parsed ${#vars1[@]} vars from file1, ${#vars2[@]} vars from file2"

    # Categorize variables
    local -a common=() only_file1=() only_file2=()
    log_debug "Starting categorization..."

    for var_name in "${!vars1[@]}"; do
        if [[ -v vars2["$var_name"] ]]; then
            common+=("$var_name")
        else
            only_file1+=("$var_name")
        fi
    done

    for var_name in "${!vars2[@]}"; do
        [[ ! -v vars1["$var_name"] ]] && only_file2+=("$var_name")
    done

    log_debug "Categorization done: common=${#common[@]}, only_file1=${#only_file1[@]}, only_file2=${#only_file2[@]}"

    local total_unique=$((${#vars1[@]} + ${#only_file2[@]}))

    # Create sample lists (first 5 from only_file1 and only_file2)
    local -a file1_sample=() file2_sample=()
    local count=0
    local max_sample=5

    log_debug "Creating samples..."

    for var_name in "${only_file1[@]}"; do
        if [[ $count -ge $max_sample ]]; then
            break
        fi
        file1_sample+=("$var_name")
        count=$((count + 1))
    done

    count=0
    for var_name in "${only_file2[@]}"; do
        if [[ $count -ge $max_sample ]]; then
            break
        fi
        file2_sample+=("$var_name")
        count=$((count + 1))
    done

    log_debug "Samples created: file1_sample=${#file1_sample[@]}, file2_sample=${#file2_sample[@]}"

    # Generate comma-separated lists
    local file1_vars=""
    local file2_vars=""

    [[ ${#file1_sample[@]} -gt 0 ]] && {
        file1_vars=$(printf "%s\n" "${file1_sample[@]}" | sort | paste -sd, -)
    }

    [[ ${#file2_sample[@]} -gt 0 ]] && {
        file2_vars=$(printf "%s\n" "${file2_sample[@]}" | sort | paste -sd, -)
    }

    # Display results
    echo ""
    log_success "Environment Files Comparison (v2)"
    echo "File 1: $(basename "$file1")"
    echo "File 2: $(basename "$file2")"
    echo ""

    log_info "Summary:"
    log_info "  Common variables:\t\t${#common[@]}"
    log_info "  Only in file1:\t\t${#only_file1[@]}"
    [[ -n "$file1_vars" ]] && log_info "    Sample (max 5): $file1_vars"
    log_info "  Only in file2:\t\t${#only_file2[@]}"
    [[ -n "$file2_vars" ]] && log_info "    Sample (max 5): $file2_vars"
    log_info "  Total unique:\t\t\t$total_unique"
    echo ""

    return 0
}
