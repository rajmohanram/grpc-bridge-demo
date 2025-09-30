#!/bin/bash

# Script to create a self-signed CA (10 years) and server certificate for wildcard domains (1 year)
# Handles multiple runs intelligently:
# - Reuses existing CA if present and valid
# - Always regenerates server certificate (for renewal purposes)
# - Provides comprehensive logging and error handling
# - Supports multiple domains and advanced certificate features

set -euo pipefail  # Enhanced error handling: exit on error, undefined vars, pipe failures

# Enable debug mode if DEBUG environment variable is set
[[ "${DEBUG:-}" == "1" ]] && set -x

# =============================================================================
# CONFIGURATION VARIABLES - Modify these as needed
# =============================================================================

# Certificate validity periods
CA_VALIDITY_DAYS=3650        # CA certificate validity (10 years)
SERVER_VALIDITY_DAYS=365     # Server certificate validity (1 year)

# Key sizes
CA_KEY_SIZE=4096             # CA private key size
SERVER_KEY_SIZE=2048         # Server private key size

# Domain configuration
DOMAIN="*.uidai.gov.in"       # Primary domain (wildcard)
ALT_DOMAIN="uidai.gov.in"     # Alternative domain (apex domain)

# CA Certificate Subject
CA_COUNTRY="IN"
CA_STATE="KA"
CA_CITY="Bengaluru"
CA_ORGANIZATION="UIDAI"
CA_ORG_UNIT="IT Department"
CA_COMMON_NAME="Envoy Root CA"

# Server Certificate Subject
SERVER_COUNTRY="IN"
SERVER_STATE="KA"
SERVER_CITY="Bengaluru"
SERVER_ORGANIZATION="UIDAI"
SERVER_ORG_UNIT="IT Department"
SERVER_COMMON_NAME="${DOMAIN}"

# File names
CA_KEY_FILE="ca.key"
CA_CERT_FILE="ca.crt"
SERVER_KEY_FILE="server.key"
SERVER_CERT_FILE="server.crt"
SERVER_CSR_FILE="server.csr"

# Directory for certificates
CERT_DIR="certs"

# =============================================================================
# END CONFIGURATION
# =============================================================================

echo "Creating self-signed CA and wildcard certificate for ${DOMAIN}"
echo "=============================================================="
echo "Configuration:"
echo "- CA Validity: ${CA_VALIDITY_DAYS} days ($(( CA_VALIDITY_DAYS / 365 )) years)"
echo "- Server Validity: ${SERVER_VALIDITY_DAYS} days ($(( SERVER_VALIDITY_DAYS / 365 )) year(s))"
echo "- Primary Domain: ${DOMAIN}"
echo "- Alternative Domain: ${ALT_DOMAIN}"
echo "- CA Subject: /C=${CA_COUNTRY}/ST=${CA_STATE}/L=${CA_CITY}/O=${CA_ORGANIZATION}/OU=${CA_ORG_UNIT}/CN=${CA_COMMON_NAME}"
echo "- Server Subject: /C=${SERVER_COUNTRY}/ST=${SERVER_STATE}/L=${SERVER_CITY}/O=${SERVER_ORGANIZATION}/OU=${SERVER_ORG_UNIT}/CN=${SERVER_COMMON_NAME}"
echo ""

# Create directories for certificates
mkdir -p "${CERT_DIR}"
cd "${CERT_DIR}"

# Function to check if CA certificate exists and is valid
check_ca_validity() {
    if [[ -f "${CA_CERT_FILE}" && -f "${CA_KEY_FILE}" ]]; then
        # Check if CA certificate is still valid (not expired)
        if openssl x509 -in "${CA_CERT_FILE}" -checkend 86400 -noout >/dev/null 2>&1; then
            echo "✓ Existing CA certificate found and is valid"
            return 0
        else
            echo "⚠ Existing CA certificate found but is expired or invalid"
            return 1
        fi
    else
        echo "ℹ No existing CA certificate found"
        return 1
    fi
}

# Step 1 & 2: Create CA private key and certificate (only if needed)
if check_ca_validity; then
    echo "1-2. Using existing CA certificate and private key..."
    echo "     CA Subject: $(openssl x509 -in "${CA_CERT_FILE}" -subject -noout)"
    echo "     CA Valid until: $(openssl x509 -in "${CA_CERT_FILE}" -enddate -noout)"
else
    echo "1. Generating new CA private key (${CA_KEY_SIZE} bits)..."
    openssl genrsa -out "${CA_KEY_FILE}" "${CA_KEY_SIZE}"

    echo "2. Creating new self-signed CA certificate (${CA_VALIDITY_DAYS} days validity)..."
    openssl req -new -x509 -days "${CA_VALIDITY_DAYS}" -key "${CA_KEY_FILE}" -out "${CA_CERT_FILE}" \
        -subj "/C=${CA_COUNTRY}/ST=${CA_STATE}/L=${CA_CITY}/O=${CA_ORGANIZATION}/OU=${CA_ORG_UNIT}/CN=${CA_COMMON_NAME}" \
        -extensions v3_ca \
        -config <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
EOF
)
    echo "✓ New CA certificate created"
fi

# Step 3: Create server private key (always regenerate for security)
echo "3. Generating new server private key (${SERVER_KEY_SIZE} bits)..."
if [[ -f "${SERVER_KEY_FILE}" ]]; then
    mv "${SERVER_KEY_FILE}" "${SERVER_KEY_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "   Previous server key backed up"
fi
openssl genrsa -out "${SERVER_KEY_FILE}" "${SERVER_KEY_SIZE}"

# Step 4: Create server certificate signing request (CSR)
echo "4. Creating server certificate signing request..."
openssl req -new -key "${SERVER_KEY_FILE}" -out "${SERVER_CSR_FILE}" \
    -subj "/C=${SERVER_COUNTRY}/ST=${SERVER_STATE}/L=${SERVER_CITY}/O=${SERVER_ORGANIZATION}/OU=${SERVER_ORG_UNIT}/CN=${SERVER_COMMON_NAME}" \
    -config <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[req_distinguished_name]
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = ${ALT_DOMAIN}
EOF
)

# Step 5: Sign the server certificate with CA (valid for specified days)
echo "5. Signing new server certificate with CA (${SERVER_VALIDITY_DAYS} days validity)..."
if [[ -f "${SERVER_CERT_FILE}" ]]; then
    mv "${SERVER_CERT_FILE}" "${SERVER_CERT_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "   Previous server certificate backed up"
fi
openssl x509 -req -in "${SERVER_CSR_FILE}" -CA "${CA_CERT_FILE}" -CAkey "${CA_KEY_FILE}" -CAcreateserial \
    -out "${SERVER_CERT_FILE}" -days "${SERVER_VALIDITY_DAYS}" -sha256 \
    -extensions v3_req \
    -extfile <(cat <<EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = ${ALT_DOMAIN}
EOF
)

# Clean up CSR file
rm "${SERVER_CSR_FILE}"

echo ""
echo "Certificate generation completed!"
echo "================================"
echo ""
echo "Files in ${CERT_DIR}/ directory:"
echo "- ${CA_KEY_FILE}      : CA private key (keep secure!)"
echo "- ${CA_CERT_FILE}     : CA certificate (${CA_VALIDITY_DAYS} days validity)"
echo "- ${SERVER_KEY_FILE}  : Server private key (newly generated)"
echo "- ${SERVER_CERT_FILE} : Server certificate for ${DOMAIN} (${SERVER_VALIDITY_DAYS} days validity)"
if ls *.backup.* >/dev/null 2>&1; then
    echo "- *.backup.*     : Previous certificates (backed up)"
fi
echo ""

# Verify certificates
echo "Certificate verification:"
echo "========================"
echo ""
echo "CA Certificate details:"
openssl x509 -in "${CA_CERT_FILE}" -text -noout | grep -E "(Subject:|Not Before|Not After|CA:)"
echo ""
echo "Server Certificate details:"
openssl x509 -in "${SERVER_CERT_FILE}" -text -noout | grep -E "(Subject:|Not Before|Not After|DNS:)"
echo ""

# Verify certificate chain
echo "Verifying certificate chain..."
if openssl verify -CAfile "${CA_CERT_FILE}" "${SERVER_CERT_FILE}"; then
    echo "✓ Certificate chain verification successful!"
else
    echo "✗ Certificate chain verification failed!"
fi

echo ""
echo "Usage instructions:"
echo "=================="
echo "1. Install ${CA_CERT_FILE} as a trusted root certificate on client systems (one-time setup)"
echo "2. Use ${SERVER_CERT_FILE} and ${SERVER_KEY_FILE} in your web server configuration"
echo "3. The server certificate covers both ${DOMAIN} and ${ALT_DOMAIN} domains"
echo "4. Run this script again to renew the server certificate before it expires (${SERVER_VALIDITY_DAYS} days)"
echo "   - The CA will be reused if still valid (${CA_VALIDITY_DAYS} days)"
echo "   - Only the server certificate and key will be regenerated"
echo ""
echo ""
echo "To force CA regeneration, delete ${CA_CERT_FILE} and ${CA_KEY_FILE} before running this script."
echo "To customize certificate parameters, edit the variables at the top of this script."
