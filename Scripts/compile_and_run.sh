#!/bin/bash
# Compile and run GCalNotifier as a proper .app bundle
# Kills any existing instance, builds debug, creates bundle, and launches
# Usage: ./Scripts/compile_and_run.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Kill existing instance
./Scripts/kill_app.sh 2>/dev/null || true

# Build
if ! swift build; then
    echo "Build failed" >&2
    exit 1
fi

# Create minimal .app bundle for debug (required for UNUserNotificationCenter)
APP_NAME="GCalNotifier"
APP_BUNDLE="$PROJECT_ROOT/.build/debug/$APP_NAME.app"
EXECUTABLE="$PROJECT_ROOT/.build/debug/$APP_NAME"

# Source version info
if [ -f "$PROJECT_ROOT/version.env" ]; then
    source "$PROJECT_ROOT/version.env"
else
    BUNDLE_ID="com.gcal-notifier"
    MARKETING_VERSION="0.1.0"
    BUILD_NUMBER="1"
fi

# Clean and create bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create Info.plist
if [ -f "$PROJECT_ROOT/Info.plist" ]; then
    cp "$PROJECT_ROOT/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
else
    cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key>
    <string>$MARKETING_VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF
fi

# Copy sound resources if they exist
if [ -d "$PROJECT_ROOT/Sources/GCalNotifier/Resources/Sounds" ]; then
    cp -r "$PROJECT_ROOT/Sources/GCalNotifier/Resources/Sounds" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
fi

# Ad-hoc sign for local development
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

# Launch the app bundle
open "$APP_BUNDLE"
