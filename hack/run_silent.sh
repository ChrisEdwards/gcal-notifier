#!/bin/bash
set -e  # Exit immediately if any command fails

# Helper functions for running commands with clean output
# Reduces token usage in AI agent sessions by ~99%

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if verbose mode is enabled
VERBOSE=${VERBOSE:-0}

# Run command silently, show output only on failure
run_silent() {
    local description="$1"
    local command="$2"

    if [ "$VERBOSE" = "1" ]; then
        echo "  → Running: $command"
        eval "$command"
        return $?
    fi

    local tmp_file=$(mktemp)
    if eval "$command" > "$tmp_file" 2>&1; then
        printf "  ${GREEN}✓${NC} %s\n" "$description"
        rm -f "$tmp_file"
        return 0
    else
        local exit_code=$?
        printf "  ${RED}✗${NC} %s\n" "$description"
        printf "${RED}Command failed: %s${NC}\n" "$command"
        cat "$tmp_file"
        rm -f "$tmp_file"
        return $exit_code
    fi
}

# Run command with native quiet flags (output shown on failure)
run_with_quiet() {
    local description="$1"
    local command="$2"

    if [ "$VERBOSE" = "1" ]; then
        echo "  → Running: $command"
        eval "$command"
        return $?
    fi

    local tmp_file=$(mktemp)
    if eval "$command" > "$tmp_file" 2>&1; then
        printf "  ${GREEN}✓${NC} %s\n" "$description"
        rm -f "$tmp_file"
        return 0
    else
        local exit_code=$?
        printf "  ${RED}✗${NC} %s\n" "$description"
        cat "$tmp_file"
        rm -f "$tmp_file"
        return $exit_code
    fi
}

# Run test command and extract test count
run_silent_with_test_count() {
    local description="$1"
    local command="$2"

    if [ "$VERBOSE" = "1" ]; then
        echo "  → Running: $command"
        eval "$command"
        return $?
    fi

    local tmp_file=$(mktemp)
    local test_count=""
    local duration=""

    if eval "$command" > "$tmp_file" 2>&1; then
        # Try Swift 6 Testing format first (✔ markers)
        test_count=$(grep -c "✔ Test " "$tmp_file" 2>/dev/null || true)

        # Fall back to classic XCTest format
        if [ "$test_count" = "0" ] || [ -z "$test_count" ]; then
            test_count=$(grep -c "Test Case.*passed" "$tmp_file" 2>/dev/null || true)
        fi

        # Extract duration from Swift 6 format
        duration=$(grep "Test run.*passed" "$tmp_file" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+s" | tail -1)
        # Or classic format
        if [ -z "$duration" ]; then
            duration=$(grep "Test Suite 'All tests' passed" "$tmp_file" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+ seconds" | tail -1)
        fi

        if [ -n "$test_count" ] && [ "$test_count" != "0" ]; then
            printf "  ${GREEN}✓${NC} %s (%s tests%s)\n" "$description" "$test_count" "${duration:+, $duration}"
        else
            printf "  ${GREEN}✓${NC} %s\n" "$description"
        fi
        rm -f "$tmp_file"
        return 0
    else
        local exit_code=$?
        printf "  ${RED}✗${NC} %s\n" "$description"
        printf "${RED}Command failed: %s${NC}\n" "$command"

        printf "\n${YELLOW}=== Error Summary ===${NC}\n"

        # Show Swift compiler errors
        grep -E "error:" "$tmp_file" 2>/dev/null | head -20

        # Show test failures
        grep -E "(✘|failed|FAILED)" "$tmp_file" 2>/dev/null | head -20

        # If no specific errors found, show last 30 lines
        if ! grep -qE "(error:|✘|failed|FAILED)" "$tmp_file" 2>/dev/null; then
            printf "\n${YELLOW}(No specific errors found, showing tail)${NC}\n"
            tail -30 "$tmp_file"
        fi
        rm -f "$tmp_file"
        return $exit_code
    fi
}

# Print section header
print_header() {
    local module="$1"
    local description="$2"
    printf "${BLUE}[%s]${NC} %s:\n" "$module" "$description"
}

# Print main section header
print_main_header() {
    local title="$1"
    printf "\n=== %s ===\n\n" "$title"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Swift-specific helpers

# Run Swift build
swift_build() {
    local description="${1:-Build}"
    local config="${2:-debug}"

    local cmd="swift build"
    [ "$config" = "release" ] && cmd="$cmd -c release"

    run_silent "$description" "$cmd"
}

# Run Swift tests
swift_test() {
    local description="${1:-Unit tests}"
    local parallel="${2:-false}"

    local cmd="swift test"
    [ "$parallel" = "true" ] && cmd="$cmd --parallel"

    run_silent_with_test_count "$description" "$cmd"
}

# Run swiftformat
swift_format() {
    local description="${1:-Format code}"
    local check_only="${2:-false}"

    local cmd="swiftformat ."
    [ "$check_only" = "true" ] && cmd="$cmd --lint"

    run_silent "$description" "$cmd"
}

# Run swiftlint
swift_lint() {
    local description="${1:-Lint code}"
    local fix="${2:-false}"
    local strict="${3:-false}"

    local cmd="swiftlint lint"
    [ "$fix" = "true" ] && cmd="$cmd --fix"
    [ "$strict" = "true" ] && cmd="$cmd --strict"

    run_silent "$description" "$cmd"
}
