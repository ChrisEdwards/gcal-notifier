#!/usr/bin/env bash
# Creates a self-signed code signing certificate for GCalNotifier development builds.
# This allows Keychain access to persist across rebuilds (no more password prompts!).
#
# Usage: ./Scripts/setup_dev_certificate.sh
#
# The certificate is stored in your login keychain and marked as trusted for code signing.
# You only need to run this once per machine.

set -euo pipefail

CERT_NAME="GCalNotifier Dev"
KEYCHAIN="login.keychain-db"

# Check if certificate already exists
if security find-identity -v -p codesigning | grep -q "${CERT_NAME}"; then
    echo "✓ Certificate '${CERT_NAME}' already exists"
    security find-identity -v -p codesigning | grep "${CERT_NAME}"
    exit 0
fi

echo "Creating self-signed code signing certificate: ${CERT_NAME}"
echo "You may be prompted for your keychain password."
echo ""

# Create a temporary directory for certificate files
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Generate certificate signing request config
cat > "${TEMP_DIR}/cert.conf" << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = ${CERT_NAME}
O = GCalNotifier Development
OU = Development

[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:FALSE
EOF

# Generate private key and self-signed certificate
openssl req -x509 -newkey rsa:2048 \
    -keyout "${TEMP_DIR}/key.pem" \
    -out "${TEMP_DIR}/cert.pem" \
    -days 3650 \
    -nodes \
    -config "${TEMP_DIR}/cert.conf" \
    2>/dev/null

# Convert to PKCS12 format for import (with a temporary password, required by macOS)
TEMP_PASS="temp$$"
openssl pkcs12 -export \
    -out "${TEMP_DIR}/cert.p12" \
    -inkey "${TEMP_DIR}/key.pem" \
    -in "${TEMP_DIR}/cert.pem" \
    -passout "pass:${TEMP_PASS}" \
    2>/dev/null

# Import into keychain
echo "Importing certificate into keychain..."
security import "${TEMP_DIR}/cert.p12" \
    -k "${KEYCHAIN}" \
    -T /usr/bin/codesign \
    -P "${TEMP_PASS}" \
    -A

# Allow codesign to access the key without prompting
# This requires your keychain password once during setup
echo ""
echo "Configuring keychain access (enter your login keychain password when prompted)..."
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "${KEYCHAIN}" 2>/dev/null || \
    echo "Note: You may need to enter your keychain password to allow codesign access."

# Trust the certificate for code signing
echo "Setting certificate trust for code signing..."
security add-trusted-cert -d -r trustRoot -k "${KEYCHAIN}" "${TEMP_DIR}/cert.pem" 2>/dev/null || true

# Verify the certificate is available
echo ""
if security find-identity -v -p codesigning | grep -q "${CERT_NAME}"; then
    echo "✓ Certificate '${CERT_NAME}' created successfully!"
    echo ""
    security find-identity -v -p codesigning | grep "${CERT_NAME}"
    echo ""
    echo "Debug builds will now use this certificate for signing."
    echo "Keychain access will persist across rebuilds - no more password prompts!"
else
    echo "⚠ Certificate created but may need manual trust approval."
    echo "Open Keychain Access, find '${CERT_NAME}', and set it to 'Always Trust'."
fi
