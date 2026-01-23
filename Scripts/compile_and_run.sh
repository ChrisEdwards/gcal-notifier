#!/bin/bash
# Compile and run GCalNotifier
# Kills any existing instance, builds debug, and launches
# Usage: ./Scripts/compile_and_run.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Kill existing instance
./Scripts/kill_app.sh 2>/dev/null

# Build and launch
if swift build; then
    open .build/debug/GCalNotifier
else
    echo "Build failed" >&2
    exit 1
fi
