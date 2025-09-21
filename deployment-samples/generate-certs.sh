#!/bin/bash

# Simple Self-Signed Certificate Generation Script
#
# To customize the certificate, edit the COMMON_NAME and SANS variables below:
# - COMMON_NAME: The primary domain/hostname for the certificate
# - SANS: Comma-separated list of Subject Alternative Names
#   Format: DNS:domain.com,IP:127.0.0.1
#
# Usage: ./generate-certs.sh

set -e

# Configuration - Edit these variables as needed
COMMON_NAME="localhost"
SANS="DNS:localhost,DNS:*.localhost,IP:127.0.0.1,IP:::1"
CERT_DIR="certs"
KEY_FILE="$CERT_DIR/server.key"
CERT_FILE="$CERT_DIR/server.crt"
DAYS=365
KEY_SIZE=2048

# Create certs directory if it doesn't exist
mkdir -p "$CERT_DIR"

echo "Generating self-signed certificate..."
echo "Common Name: $COMMON_NAME"
echo "Subject Alternative Names: $SANS"
echo "Output directory: $CERT_DIR"
echo ""

# Generate private key
echo "Generating private key..."
openssl genrsa -out "$KEY_FILE" $KEY_SIZE

# Generate self-signed certificate
echo "Generating self-signed certificate..."
# Generate self-signed certificate with Subject Alternative Names
openssl req -new -x509 -key "$KEY_FILE" -out "$CERT_FILE" -days $DAYS \
    -subj "/CN=$COMMON_NAME" \
    -extensions v3_req \
    -config <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $COMMON_NAME

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = $SANS
EOF
)

echo ""
echo "Certificate generated successfully!"
echo "Private Key: $KEY_FILE"
echo "Certificate: $CERT_FILE"
echo "Valid for: $DAYS days"

# Display certificate information
echo ""
echo "Certificate details:"
openssl x509 -in "$CERT_FILE" -text -noout | grep -E "(Subject:|DNS:|IP Address:|Not Before|Not After)"
