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

# Copy CA certificate to grpc-client directory for easy distribution
cp certs/ca.crt certs/grpc-client/
