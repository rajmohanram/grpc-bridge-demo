# gRPC Bridge Architecture Flow

This document describes the complete flow from gRPC client to server through the gRPC bridge architecture.

## Architecture Overview

The gRPC bridge consists of multiple components that handle protocol conversion, security, and routing:

1. **gRPC Client** - Initiates gRPC calls with TLS
2. **Client-side Proxy (Envoy)** - Converts gRPC to HTTP/1.1 for WAF compatibility
3. **WAF (Nginx)** - Web Application Firewall for security inspection
4. **Server-side Proxy (Envoy)** - Converts HTTP/1.1 back to gRPC
5. **gRPC Server** - Handles the actual gRPC service calls

## Sequence Diagram

```mermaid
sequenceDiagram
    participant Client as gRPC Client<br/>(user-grpc-client)
    participant ClientProxy as Client-side Proxy<br/>(Envoy)<br/>Port 8443
    participant WAF as Web Application Firewall<br/>(Nginx)<br/>Port 443
    participant ServerProxy as Server-side Proxy<br/>(Envoy)<br/>Port 8443
    participant Server as gRPC Server<br/>(user-grpc-server)<br/>Port 50051

    Note over Client,Server: TLS Certificate Chain Validation (CA-signed certificates)

    Client->>+ClientProxy: 1. gRPC/HTTP2 Request<br/>TLS encrypted<br/>(client-side-proxy:8443)
    Note over ClientProxy: Protocol Conversion:<br/>gRPC → HTTP/1.1<br/>(grpc_http1_reverse_bridge)

    ClientProxy->>+WAF: 2. HTTP/1.1 Request<br/>TLS encrypted<br/>(waf:443)
    Note over WAF: Security Inspection:<br/>- SQL injection checks<br/>- Malicious pattern detection<br/>- Header validation<br/>- gRPC-Web compatibility

    WAF->>+ServerProxy: 3. HTTP/1.1 Request<br/>TLS encrypted<br/>(server-side-proxy:8443)
    Note over ServerProxy: Protocol Conversion:<br/>HTTP/1.1 → gRPC<br/>(grpc_http1_bridge)

    ServerProxy->>+Server: 4. gRPC/HTTP2 Request<br/>TLS encrypted<br/>(user-grpc-server:50051)
    Note over Server: Business Logic Processing

    Server-->>-ServerProxy: 5. gRPC/HTTP2 Response<br/>TLS encrypted
    Note over ServerProxy: Protocol Conversion:<br/>gRPC → HTTP/1.1

    ServerProxy-->>-WAF: 6. HTTP/1.1 Response<br/>TLS encrypted
    Note over WAF: Response Inspection:<br/>- Header validation<br/>- Error handling<br/>- Custom gRPC error pages

    WAF-->>-ClientProxy: 7. HTTP/1.1 Response<br/>TLS encrypted
    Note over ClientProxy: Protocol Conversion:<br/>HTTP/1.1 → gRPC

    ClientProxy-->>-Client: 8. gRPC/HTTP2 Response<br/>TLS encrypted

    Note over Client,Server: End-to-End Security Features
    rect rgb(240, 248, 255)
        Note over Client,Server: • Mutual TLS authentication<br/>• Certificate validation<br/>• Circuit breakers & retries<br/>• Health checks<br/>• Load balancing<br/>• Connection pooling
    end
```

## Protocol Conversions

### Client-side Proxy (Envoy)
- **Input**: gRPC/HTTP2 from client
- **Output**: HTTP/1.1 to WAF
- **Filter**: `envoy.filters.http.grpc_http1_reverse_bridge`
- **Purpose**: Convert gRPC to HTTP/1.1 for WAF compatibility

### Server-side Proxy (Envoy)
- **Input**: HTTP/1.1 from WAF
- **Output**: gRPC/HTTP2 to server
- **Filter**: `envoy.filters.http.grpc_http1_bridge`
- **Purpose**: Convert HTTP/1.1 back to native gRPC

## Security Features

### TLS Configuration
- All components use mutual TLS with CA-signed certificates
- Certificate distribution handled by `generate-certs.sh`
- SNI validation for proper certificate matching

### WAF Protection
- SQL injection pattern detection
- Malicious request filtering
- gRPC-specific header preservation
- Custom error handling for gRPC responses

### Circuit Breakers & Resilience
- Connection limits and timeouts
- Retry policies with exponential backoff
- Health checks for service availability
- Outlier detection for automatic failover

## Performance Optimizations

### HTTP/2 Settings
- Optimized stream and connection window sizes
- Enhanced concurrent stream limits
- Connection pooling and keepalive

### Buffer Management
- Request/response buffering disabled for streaming
- Optimized buffer sizes for high throughput
- Connection-level optimizations

## Error Handling

### Retry Policies
- Automatic retries on 5xx, timeouts, and connection failures
- Exponential backoff with jitter
- Host selection retry for failover

### Custom Error Pages
- gRPC-specific error responses from WAF
- Proper gRPC status codes and messages
- Graceful degradation on service unavailability
