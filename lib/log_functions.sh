#!/bin/bash
# PURPOSE: Shared functions library
# USAGE: Source this file in other scripts with: source log_functions.sh (command line usage not included yet)
# OWNER: XCS HornetGit
# LICENCE: MIT
# CREATED: 05OCTJUL2025
# UPDATED: _
# CHANGES: 

set -Eeuo pipefail
IFS=$'\n\t'

# source constants.sh if RED unset 
[[ -z "${RED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"

# Log functions (nice echoing)
log_debugmode(){
    if [[ "$DEBUG" = true ]] && [[ -w "$dbg_path" || -w "$(dirname "$dbg_path")" ]]; then
        echo -e "$1" | sed $'s/\033\[[0-9;]*m//g' >> "$dbg_path" 2>/dev/null || true
    fi
}

log_info() {
    local msg="${BLUE}ℹ️  $1${NC}"
    echo -e "$msg"
    log_debugmode "$msg"
}

log_success() {
    local msg="${GREEN}✅ $1${NC}"
    echo -e "$msg"
    log_debugmode "$msg"
}

log_warning() {
    local msg="${YELLOW1}⚠️  $1${NC}"
    echo -e "$msg"
    log_debugmode "$msg"
}

log_debug() {
    local msg="${YELLOW1}DEBUG:  $1${NC}"
    echo -e "$msg"
    log_debugmode "$msg"
}

log_error() {
    local msg="${RED}❌ $1${NC}"
    echo -e "$msg"
    log_debugmode "$msg"
}

log_command() {
    #set_command "$1"
    local msg="${RED}CMD: $1${NC}"
    echo -e "$msg"
    log_debugmode "$msg"
}

log_title() {
    # Display formatted title for scripts
    local script_name="${1:-$(basename "$0")}"
    # TODO: set "CLEAR" screen as an option
    local title_with_padding="$script_name by XCS  "
    local title_clean="$script_name by XCS"
    printf "##"'%*s\n' "${#title_with_padding}" '' | tr ' ' '#'
    echo "# $title_clean #"
    printf "##"'%*s\n' "${#title_with_padding}" '' | tr ' ' '#'
    echo ""
}
