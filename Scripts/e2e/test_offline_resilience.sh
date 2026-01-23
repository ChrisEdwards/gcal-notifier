#!/bin/bash
# E2E Test: Offline Resilience Verification
# Manual test script for verifying app behavior when network is unavailable
# Requires: Running app, authenticated, cached events, network control

set -e

LOG_DIR="$HOME/Library/Logs/gcal-notifier"
LOG_FILE="$LOG_DIR/e2e-tests.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] E2E Offline: $1" | tee -a "$LOG_FILE"
}

echo "=== Offline Resilience E2E Test ==="
echo ""
log "Offline resilience test started"

echo "Prerequisites:"
echo "  - App running and authenticated"
echo "  - Events already synced and visible"
echo "  - Ability to disable/enable network"
echo ""

# Phase 1: Verify initial state
echo "Phase 1: Initial State"
echo "  Verify events are visible in the menu bar"
read -p "Are events currently visible? (y/n): " initial_state
if [ "$initial_state" != "y" ] && [ "$initial_state" != "Y" ]; then
    log "Initial state check failed - no events visible"
    echo "FAILED: Cannot proceed - events must be visible before offline test"
    exit 1
fi
log "Initial state: events visible"
echo ""

# Phase 2: Go offline
echo "Phase 2: Disable Network"
echo "  - Turn off Wi-Fi, or"
echo "  - Enable airplane mode, or"
echo "  - Disconnect ethernet"
echo ""
read -p "Press Enter when network is disabled..."
log "Network disabled by user"
echo ""

# Phase 3: Verify cached events
echo "Phase 3: Verify Cached Events"
echo "  Click menu bar icon and check if events still display"
read -p "Are cached events still visible offline? (y/n): " cached_result
if [ "$cached_result" = "y" ] || [ "$cached_result" = "Y" ]; then
    log "Cached events: VISIBLE"
    cached_pass=true
else
    log "Cached events: NOT VISIBLE"
    cached_pass=false
fi
echo ""

# Phase 4: Verify scheduled alerts (optional)
echo "Phase 4: Scheduled Alerts (Optional)"
echo "  If you have an upcoming event with an alert, verify it still fires"
read -p "Did scheduled alerts fire while offline? (y/n/skip): " alert_result
if [ "$alert_result" = "y" ] || [ "$alert_result" = "Y" ]; then
    log "Offline alerts: WORKING"
    alerts_pass=true
elif [ "$alert_result" = "skip" ]; then
    log "Offline alerts: SKIPPED"
    alerts_pass=true
else
    log "Offline alerts: FAILED"
    alerts_pass=false
fi
echo ""

# Phase 5: Restore network
echo "Phase 5: Re-enable Network"
echo "  Restore your network connection"
read -p "Press Enter when network is restored..."
log "Network restored by user"
echo ""

# Phase 6: Verify sync resumes
echo "Phase 6: Verify Sync Resumes"
echo "  Wait a moment for sync to occur, then check menu"
read -p "Did sync resume successfully? (y/n): " sync_result
if [ "$sync_result" = "y" ] || [ "$sync_result" = "Y" ]; then
    log "Sync resume: SUCCESS"
    sync_pass=true
else
    log "Sync resume: FAILED"
    sync_pass=false
fi
echo ""

# Final result
echo "=== Test Results ==="
echo "  Cached events visible offline: $([ "$cached_pass" = true ] && echo 'PASS' || echo 'FAIL')"
echo "  Alerts fire offline: $([ "$alerts_pass" = true ] && echo 'PASS' || echo 'FAIL')"
echo "  Sync resumes after reconnect: $([ "$sync_pass" = true ] && echo 'PASS' || echo 'FAIL')"
echo ""

if [ "$cached_pass" = true ] && [ "$alerts_pass" = true ] && [ "$sync_pass" = true ]; then
    log "Offline resilience test PASSED"
    echo "PASSED: Offline resilience verification successful"
    exit 0
else
    log "Offline resilience test FAILED"
    echo "FAILED: Offline resilience verification failed"
    exit 1
fi
