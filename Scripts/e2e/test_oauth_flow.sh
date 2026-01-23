#!/bin/bash
# E2E Test: OAuth Flow Verification
# Manual test script for verifying Google OAuth authentication
# Requires: Running app, test Google account credentials

set -e

LOG_DIR="$HOME/Library/Logs/gcal-notifier"
LOG_FILE="$LOG_DIR/e2e-tests.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] E2E OAuth: $1" | tee -a "$LOG_FILE"
}

echo "=== OAuth Flow E2E Test ==="
echo ""
log "OAuth flow test started"

echo "Prerequisites:"
echo "  - GCal Notifier app is running"
echo "  - You have a Google account with calendar access"
echo ""

echo "Test Steps:"
echo "  1. Launch the app (if not already running)"
echo "  2. Open Settings > Account"
echo "  3. Click 'Sign In with Google'"
echo "  4. Complete Google sign-in in browser"
echo "  5. Authorize calendar access"
echo ""

log "Waiting for user to complete OAuth flow"

echo "Expected Result:"
echo "  - Browser opens for Google authentication"
echo "  - After authorization, app shows 'Signed in as: <your-email>'"
echo "  - No error messages appear"
echo ""

read -p "Did OAuth complete successfully? (y/n): " result

if [ "$result" = "y" ] || [ "$result" = "Y" ]; then
    log "OAuth flow PASSED"
    echo ""
    echo "PASSED: OAuth flow completed successfully"
    exit 0
else
    log "OAuth flow FAILED"
    echo ""
    read -p "Enter failure reason (optional): " reason
    if [ -n "$reason" ]; then
        log "Failure reason: $reason"
    fi
    echo "FAILED: OAuth flow verification failed"
    exit 1
fi
