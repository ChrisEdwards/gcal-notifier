#!/bin/bash
# E2E Test: Sync Cycle Verification
# Manual test script for verifying calendar sync produces events
# Requires: Running app, authenticated, test calendar with known events

set -e

LOG_DIR="$HOME/Library/Logs/gcal-notifier"
LOG_FILE="$LOG_DIR/e2e-tests.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] E2E Sync: $1" | tee -a "$LOG_FILE"
}

echo "=== Sync Cycle E2E Test ==="
echo ""
log "Sync cycle test started"

echo "Prerequisites:"
echo "  - App running and authenticated"
echo "  - Test calendar with at least one event today"
echo ""

echo "Test Steps:"
echo "  1. Wait for initial sync to complete (check menu bar icon)"
echo "  2. Click menu bar icon"
echo "  3. Verify 'Today's Meetings' section is visible"
echo "  4. Verify your test event appears in the list"
echo ""

log "Waiting for user to verify sync results"

echo "Expected Result:"
echo "  - Menu shows list of today's calendar events"
echo "  - Event titles, times, and details are accurate"
echo "  - No sync error indicators"
echo ""

read -p "Are events visible and correct in the menu? (y/n): " result

if [ "$result" = "y" ] || [ "$result" = "Y" ]; then
    log "Sync cycle PASSED"
    echo ""

    read -p "How many events were displayed? " event_count
    if [ -n "$event_count" ]; then
        log "Events displayed: $event_count"
    fi

    echo "PASSED: Sync cycle completed successfully"
    exit 0
else
    log "Sync cycle FAILED"
    echo ""
    read -p "Enter failure reason (optional): " reason
    if [ -n "$reason" ]; then
        log "Failure reason: $reason"
    fi
    echo "FAILED: Sync cycle verification failed"
    exit 1
fi
