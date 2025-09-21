#!/bin/bash
# Script to generate TLS certificates for gRPC Bridge

# Create directories for certs
mkdir -p certs/client-proxy
mkdir -p certs/server-proxy
mkdir -p certs/grpc-service
mkdir -p certs/grpc-client

# Create a CA for all certificates
openssl genrsa -out certs/ca.key 4096
openssl req -new -x509 -days 365 -key certs/ca.key -out certs/ca.crt -subj "/CN=grpc-bridge-ca"

# Generate Client-side Proxy certificate
openssl genrsa -out certs/client-proxy/server.key 2048
openssl req -new -key certs/client-proxy/server.key -out certs/client-proxy/server.csr -subj "/CN=client-side-proxy"
# Add relevant SANs for the client-side proxy (update these to match your domain)
openssl x509 -req -days 365 -in certs/client-proxy/server.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/client-proxy/server.crt \
  -extfile <(printf "subjectAltName=DNS:client-side-proxy,DNS:client-side-proxy.fastlane.com")

# Generate Server-side Proxy server certificate
openssl genrsa -out certs/server-proxy/server.key 2048
openssl req -new -key certs/server-proxy/server.key -out certs/server-proxy/server.csr -subj "/CN=server-side-proxy"
openssl x509 -req -days 365 -in certs/server-proxy/server.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/server-proxy/server.crt \
  -extfile <(printf "subjectAltName=DNS:server-side-proxy,DNS:server-side-proxy.fastlane.com")

# Generate gRPC Service certificate
openssl genrsa -out certs/grpc-service/server.key 2048
openssl req -new -key certs/grpc-service/server.key -out certs/grpc-service/server.csr -subj "/CN=grpc-service.fastlane.com"
openssl x509 -req -days 365 -in certs/grpc-service/server.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/grpc-service/server.crt \
  -extfile <(printf "subjectAltName=DNS:grpc-service.fastlane.com,DNS:grpc-service")

# Generate waf server certificate
openssl genrsa -out certs/waf/server.key 2048
openssl req -new -key certs/waf/server.key -out certs/waf/server.csr -subj "/CN=waf.fastlane.com"
openssl x509 -req -days 365 -in certs/waf/server.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/waf/server.crt \
  -extfile <(printf "subjectAltName=DNS:waf.fastlane.com,DNS:waf")

# Copy CA certificate to all service directories for easy distribution
copy_ca_certificate() {
    local ca_cert="certs/ca.crt"
    local target_dirs=(
        "certs/grpc-client"
        "certs/client-proxy"
        "certs/waf"
        "certs/server-proxy"
        "certs/grpc-service"
    )

    # Verify CA certificate exists
    if [[ ! -f "$ca_cert" ]]; then
        echo "Error: CA certificate not found at $ca_cert" >&2
        return 1
    fi

    echo "Distributing CA certificate to service directories..."

    # Copy CA certificate to each target directory
    for dir in "${target_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo "Warning: Directory $dir does not exist, skipping..." >&2
            continue
        fi

        if cp "$ca_cert" "$dir/ca.crt"; then
            echo "✓ Copied CA certificate to $dir/"
        else
            echo "✗ Failed to copy CA certificate to $dir/" >&2
            return 1
        fi
    done

    echo "CA certificate distribution completed successfully."
    return 0
}

# Execute the CA certificate distribution
copy_ca_certificate || {
    echo "Error: Failed to distribute CA certificate" >&2
    exit 1
}
