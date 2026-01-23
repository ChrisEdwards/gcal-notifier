#!/bin/bash
# E2E Test: Alert Timing Verification
# Manual test script for verifying alerts fire at correct times
# Requires: Running app, authenticated, ability to create test events

set -e

LOG_DIR="$HOME/Library/Logs/gcal-notifier"
LOG_FILE="$LOG_DIR/e2e-tests.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] E2E Alert: $1" | tee -a "$LOG_FILE"
}

echo "=== Alert Timing E2E Test ==="
echo ""
log "Alert timing test started"

echo "Setup:"
echo "  1. Create a test event starting in ~12 minutes"
echo "  2. Ensure app settings have:"
echo "     - Stage 1 alert = 10 minutes before"
echo "     - Stage 2 alert = 2 minutes before"
echo ""

current_time=$(date '+%H:%M:%S')
echo "Current time: $current_time"
echo ""

echo "Expected Alert Times:"
echo "  - Stage 1: Should fire at T-10 minutes"
echo "  - Stage 2: Should fire at T-2 minutes"
echo ""

echo "Record the actual times when each alert fires."
echo "Accuracy should be within +/- 30 seconds."
echo ""

log "Waiting for alert timing verification"

read -p "Did Stage 1 alert fire on time? (y/n): " stage1_result
if [ "$stage1_result" = "y" ] || [ "$stage1_result" = "Y" ]; then
    log "Stage 1 alert timing: PASSED"
    stage1_pass=true
else
    log "Stage 1 alert timing: FAILED"
    stage1_pass=false
    read -p "Stage 1 - How many seconds off? (negative=early, positive=late): " stage1_offset
    if [ -n "$stage1_offset" ]; then
        log "Stage 1 offset: ${stage1_offset}s"
    fi
fi

read -p "Did Stage 2 alert fire on time? (y/n): " stage2_result
if [ "$stage2_result" = "y" ] || [ "$stage2_result" = "Y" ]; then
    log "Stage 2 alert timing: PASSED"
    stage2_pass=true
else
    log "Stage 2 alert timing: FAILED"
    stage2_pass=false
    read -p "Stage 2 - How many seconds off? (negative=early, positive=late): " stage2_offset
    if [ -n "$stage2_offset" ]; then
        log "Stage 2 offset: ${stage2_offset}s"
    fi
fi

echo ""
if [ "$stage1_pass" = true ] && [ "$stage2_pass" = true ]; then
    log "Alert timing test PASSED"
    echo "PASSED: All alerts fired within acceptable timing"
    exit 0
else
    log "Alert timing test FAILED"
    echo "FAILED: Alert timing verification failed"
    exit 1
fi
