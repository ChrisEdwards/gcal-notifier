#!/bin/bash
# Kill running GCalNotifier instances
# Usage: ./Scripts/kill_app.sh

pkill -f "GCalNotifier" 2>/dev/null || true
