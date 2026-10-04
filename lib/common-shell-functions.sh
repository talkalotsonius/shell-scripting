#!/usr/bin/env bash
set -euo pipefail

# Common high-level shell functions for scripts
# This library provides reusable functions for logging, tool validation,
# and git operations

#=============================================================================
# COLOURS AND LOGGING
#=============================================================================

# ANSI colour codes for terminal output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly RED='\033[0;31m'
readonly COLOUR_RESET='\033[0m'

# Print an informational message to stdout (cyan scope, plain message)
# Args:
#   $1 - message to print
#   $2 - scope label rendered as [scope] (required)
# Example:
#   info "Starting validation..." "yaml-lint"
info() {
    local message="$1"
    local scope="$2"
    echo -e "${CYAN}[${scope}]${COLOUR_RESET} ${message}"
}

# Print a success message to stdout (green scope, plain message)
# Args:
#   $1 - message to print
#   $2 - scope label rendered as [scope] (required)
# Example:
#   success "All checks passed" "yaml-lint"
success() {
    local message="$1"
    local scope="$2"
    echo -e "${GREEN}[${scope}]${COLOUR_RESET} ${message}"
}

# Print a warning message to stdout (yellow scope, plain message)
# Args:
#   $1 - message to print
#   $2 - scope label rendered as [scope] (required)
# Example:
#   warn "Skipping optional check" "yaml-lint"
warn() {
    local message="$1"
    local scope="$2"
    echo -e "${YELLOW}[${scope}]${COLOUR_RESET} ${message}"
}

# Print an error message to stderr (red scope, plain message)
# Args:
#   $1 - message to print
#   $2 - scope label rendered as [scope] (required)
# Example:
#   error "Validation failed for ${file}" "yaml-lint"
error() {
    local message="$1"
    local scope="$2"
    echo -e "${RED}[${scope}]${COLOUR_RESET} ${message}" >&2
}

# Exit the script with a success message via success()
# Args:
#   $1 - success message
#   $2 - scope label rendered as [scope] (required, defaults to "common")
# Example:
#   exit_success "All files passed validation" "yaml-lint"
exit_success() {
    local message="$1"
    local scope="${2:-common}"
    success "✅  ${message}" "${scope}"

    # Fall back to exit when this file is executed instead of sourced.
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
}

# Exit the script with an error message via error(), then terminate with code 1
# Args:
#   $1 - primary error message
#   $2 - scope label rendered as [scope] (required, defaults to "common")
#   $@ - optional additional detail lines printed as further error() calls
# Example:
#   exit_error "Validation failed for ${file}" "yaml-lint"
#   exit_error "Missing required field" "json-lint" "Expected: name" "Got: (empty)"
exit_error() {
    local message="$1"
    local scope="${2:-common}"

    error "❌  ${message}" "${scope}"

    # Print any additional detail lines passed as $3, $4, ...
    local line
    for line in "${@:3}"; do
        error "${line}" "${scope}"
    done

    # Fall back to exit when this file is executed instead of sourced.
    # shellcheck disable=SC2317
    return 1 2>/dev/null || exit 1
}


# Check if a required tool is installed in PATH; exit via exit_error() if not found.
# Args:
#   $1 - tool name to check (e.g., "yamllint", "jq", "az")
#   $2 - scope label rendered as [scope] in the error output (defaults to "common")
#   $@ - optional additional detail lines forwarded to exit_error()
# Returns:
#   Exits with code 1 via exit_error() if the tool is not in PATH
# Example:
#   require_tool "yamllint" "${SCOPE}"
#   require_tool "az" "${SCOPE}"
require_tool() {
    local tool_name="$1"
    local scope="${2:-common}"

    if ! command -v -- "${tool_name}" >/dev/null 2>&1; then
        exit_error "${tool_name} is not installed or not in PATH" "${scope}" "${@:3}"
        return 1
    fi
}


#=============================================================================
# GIT OPERATIONS
#=============================================================================

# Get current git branch name
# Returns:
#   Current branch name; prefers GITHUB_HEAD_REF env var in CI environments
# Example:
#   branch=$(get_current_branch)
get_current_branch() {
    # In CI mode, try GITHUB_HEAD_REF first, otherwise use git
    if [ "${GITHUB_HEAD_REF:-}" ]; then
        echo "$GITHUB_HEAD_REF"
    else
        git rev-parse --abbrev-ref HEAD
    fi
}

# Get a list of files staged for commit (used in hook mode)
# Returns:
#   Newline-separated list of staged file paths (added, copied, modified, renamed, type-changed)
# Example:
#   files=$(get_staged_git_files)
get_staged_git_files() {
    git diff --cached --name-only --diff-filter=ACMRT
}

# Get a list of files changed relative to origin/main (used in CI mode)
# Returns:
#   Newline-separated list of changed file paths (added, copied, modified, renamed, type-changed)
# Example:
#   files=$(get_changed_git_files)
get_changed_git_files() {
    git diff --name-only --diff-filter=ACMRT origin/main..HEAD
}

# Get files to check based on execution mode; delegates to get_staged_git_files or get_changed_git_files
# Args:
#   $1 - mode (hook/ci, default: hook)
# Returns:
#   Newline-separated list of file paths relevant to the current mode
# Example:
#   FILES=$(get_files_to_check "${MODE}")
get_files_to_check() {
    local mode="${1:-hook}"

    if [ "$mode" = "ci" ]; then
        get_changed_git_files
    else
        get_staged_git_files
    fi
}
