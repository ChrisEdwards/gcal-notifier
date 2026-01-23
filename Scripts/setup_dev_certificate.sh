#!/bin/bash
# Setup local development certificate for code signing
# Usage: ./Scripts/setup_dev_certificate.sh
#
# This script helps create a self-signed certificate for local development.
# For distribution, you'll need a proper Apple Developer ID certificate.

set -e

CERT_NAME="GCalNotifier Development"

echo "=== Development Certificate Setup ==="
echo ""
echo "This script will help set up code signing for local development."
echo ""

# Check for existing certificates
echo "Checking for existing codesigning certificates..."
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "Development certificate '$CERT_NAME' already exists."
    echo ""
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    exit 0
fi

echo ""
echo "No development certificate found."
echo ""
echo "Options:"
echo ""
echo "1. Ad-hoc signing (simplest, for local testing only):"
echo "   codesign --force --sign - GCalNotifier.app"
echo ""
echo "2. Create a self-signed certificate via Keychain Access:"
echo "   a. Open Keychain Access"
echo "   b. Keychain Access > Certificate Assistant > Create a Certificate"
echo "   c. Name: $CERT_NAME"
echo "   d. Identity Type: Self Signed Root"
echo "   e. Certificate Type: Code Signing"
echo "   f. Check 'Let me override defaults'"
echo "   g. Continue through wizard with defaults"
echo ""
echo "3. Use an Apple Developer ID (for distribution):"
echo "   Sign up at https://developer.apple.com"
echo "   Download your Developer ID certificate"
echo ""
echo "For most local development, option 1 (ad-hoc) is sufficient."
