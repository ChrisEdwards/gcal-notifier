#!/bin/bash
# Package GCalNotifier as a macOS .app bundle
# Usage: ./Scripts/package_app.sh [release|debug]
#
# Creates GCalNotifier.app in dist/ directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Configuration
BUILD_TYPE="${1:-release}"
APP_NAME="GCalNotifier"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

# Source version info
if [ -f "version.env" ]; then
    source version.env
else
    echo "Error: version.env not found" >&2
    exit 1
fi

# Build if needed
echo "Building ($BUILD_TYPE)..."
if [ "$BUILD_TYPE" = "release" ]; then
    swift build -c release
    EXECUTABLE="$PROJECT_ROOT/.build/release/$APP_NAME"
else
    swift build
    EXECUTABLE="$PROJECT_ROOT/.build/debug/$APP_NAME"
fi

if [ ! -f "$EXECUTABLE" ]; then
    echo "Error: Executable not found at $EXECUTABLE" >&2
    exit 1
fi

# Clean previous bundle
rm -rf "$APP_BUNDLE"

# Create .app bundle structure
echo "Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Generate Info.plist from template and version.env
if [ -f "Info.plist" ]; then
    cp "Info.plist" "$APP_BUNDLE/Contents/Info.plist"

    # Update version info using PlistBuddy
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"
else
    echo "Warning: Info.plist not found, creating minimal plist" >&2
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

# Copy Resources if they exist
if [ -d "Resources" ]; then
    cp -r Resources/* "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
fi

# Copy entitlements for reference (useful for signing)
if [ -f "GCalNotifier.entitlements" ]; then
    cp "GCalNotifier.entitlements" "$DIST_DIR/"
fi

# Code sign if Developer ID is available
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID"; then
    echo "Signing app bundle..."
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    if [ -f "GCalNotifier.entitlements" ]; then
        codesign --force --options runtime --entitlements "GCalNotifier.entitlements" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    else
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    fi
    echo "Signed with: $SIGNING_IDENTITY"
else
    echo "Note: No Developer ID found, app bundle is unsigned"
    echo "For local testing, you can ad-hoc sign with:"
    echo "  codesign --force --sign - $APP_BUNDLE"
fi

echo ""
echo "Package complete: $APP_BUNDLE"
echo "Version: $MARKETING_VERSION ($BUILD_NUMBER)"
