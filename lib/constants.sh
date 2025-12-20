#!/bin/bash
# PURPOSE: Constants and global variables for Podman installer
# USAGE: Source this file first before other lib files
# LICENCE: MIT
# Repo: https://github.com/HornetGit/podman_v5.x_on_debian12

# Debug mode (readonly for safety)
[[ -z "${DEBUG:-}" ]] && readonly DEBUG=true || true

# Get installer root directory (from lib/ go up 1 level)
get_project_root() {
    (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
}

# Debug log path (optional, for troubleshooting)
get_debug_path() {
    local root
    root="$(get_project_root)"
    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    printf '%s/logs/debug_%s.log' "$root" "$timestamp"
}

# Session-based logging support (readonly for safety)
if [[ -z "${dbg_path:-}" ]]; then
    readonly dbg_path="${V13_SESSION_LOG:-$(get_debug_path)}"

    # Only initialize if directory is writable
    if [[ ! -f "$dbg_path" ]]; then
        mkdir -p "$(dirname "$dbg_path")" 2>/dev/null || true
        if [[ -w "$(dirname "$dbg_path")" ]]; then
            : > "$dbg_path" 2>/dev/null || true
        fi
    fi
fi

# Colors for output (readonly for safety)
[[ -z "${RED:-}" ]] && readonly RED='\033[0;31m' || true
[[ -z "${GREEN:-}" ]] && readonly GREEN='\033[0;32m' || true
[[ -z "${YELLOW2:-}" ]] && readonly YELLOW2='\033[1;33m' || true
[[ -z "${YELLOW1:-}" ]] && readonly YELLOW1='\033[38;5;208m' || true
[[ -z "${BLUE:-}" ]] && readonly BLUE='\033[0;34m' || true
[[ -z "${NC:-}" ]] && readonly NC='\033[0m' || true

[[ -z "${NOK:-}" ]] && readonly NOK="\e[31mNOK\e[0m" || true
[[ -z "${OK:-}" ]] && readonly OK="\e[32mOK\e[0m" || true
[[ -z "${WARN:-}" ]] && readonly WARN="\e[33mWARN\e[0m" || true

# Error codes
[[ -z "${ERR_LOG_DIR_CREATION:-}" ]] && readonly ERR_LOG_DIR_CREATION=51 || true
