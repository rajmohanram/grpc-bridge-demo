# gRPC through HTTP/1.1 WAF Proxy Architecture

This project demonstrates a production-ready solution for enabling gRPC communication through an HTTP/1.1 Web Application Firewall (WAF) using Envoy proxy protocol bridges and Docker Compose.

## Problem Statement

Traditional gRPC services require HTTP/2 for proper operation, particularly for trailer handling that contains essential status information. However, many enterprise environments use HTTP/1.1-only WAFs that cannot natively handle gRPC traffic. This creates a challenge when trying to deploy gRPC services behind existing WAF infrastructure.

## Solution Overview

This architecture implements a **bidirectional gRPC-HTTP/1.1 bridge** using Envoy proxies that:
- Converts incoming gRPC (HTTP/2) to HTTP/1.1 for WAF compatibility
- Routes traffic through an NGINX-based WAF with full inspection capabilities
- Converts HTTP/1.1 back to native gRPC (HTTP/2) for the backend service
- Preserves gRPC semantics through specialized bridge filters
- Provides TLS termination and certificate management

## Architecture Components

```
┌─────────────────┐    ┌───────────────────┐    ┌─────────┐    ┌───────────────────┐    ┌──────────────────┐
│   gRPC Client   │───▶│ Client-Side Proxy │───▶│   WAF   │───▶│ Server-Side Proxy │───▶│   gRPC Server    │
│                 │    │    (Envoy)        │    │ (NGINX) │    │     (Envoy)       │    │                  │
│ HTTP/2 + gRPC   │    │  gRPC → HTTP/1.1  │    │HTTP/1.1 │    │ HTTP/1.1 → gRPC   │    │  HTTP/2 + gRPC   │
└─────────────────┘    └───────────────────┘    └─────────┘    └───────────────────┘    └──────────────────┘
```

### Component Details

#### 1. gRPC Client (`user-grpc-client`)
- **Purpose**: Standard gRPC client application
- **Protocol**: HTTP/2 with gRPC
- **Features**: User management operations (CRUD)
- **Configuration**: Connects to client-side proxy with TLS

#### 2. Client-Side Proxy (`client-side-proxy`)
- **Technology**: Envoy Proxy v1.33.4
- **Purpose**: Convert gRPC to HTTP/1.1 for WAF compatibility
- **Key Features**:
  - `envoy.filters.http.grpc_http1_reverse_bridge`: Converts gRPC to HTTP/1.1
  - TLS termination and re-encryption
  - gRPC statistics and monitoring
  - CORS support for web clients
  - Timeout and retry configuration

#### 3. Web Application Firewall (`waf`)
- **Technology**: NGINX Alpine
- **Purpose**: Security filtering and traffic inspection
- **Features**:
  - HTTP/1.1 request/response handling
  - SSL/TLS proxy termination
  - Request logging and monitoring
  - Security header management
  - Content inspection capabilities

#### 4. Server-Side Proxy (`server-side-proxy`)
- **Technology**: Envoy Proxy v1.33.4
- **Purpose**: Convert HTTP/1.1 back to native gRPC for backend service
- **Key Features**:
  - `envoy.filters.http.grpc_http1_bridge`: Converts HTTP/1.1 to gRPC
  - Connection pooling and load balancing
  - Health checking (TCP-based)
  - gRPC statistics collection

#### 5. gRPC Server (`user-grpc-server`)
- **Technology**: Go-based gRPC service
- **Purpose**: Backend business logic
- **Features**: User management API with protobuf definitions

## Flow Diagram

```mermaid
graph TB
    subgraph "Client Environment"
        A["gRPC Client<br/>HTTP/2 + gRPC"]
    end

    subgraph "Edge Infrastructure"
        B["Client-Side Proxy<br/>Envoy"]
        C["WAF<br/>NGINX"]
        D["Server-Side Proxy<br/>Envoy"]
    end

    subgraph "Backend Services"
        E["gRPC Server<br/>Go Service"]
    end

    A -->|"(1). gRPC Request<br/>HTTP/2"| B
    B -->|"(2). HTTP/1.1<br/>Bridge Conversion"| C
    C -->|"(3). HTTP/1.1<br/>WAF Processing"| D
    D -->|"(4). gRPC Request<br/>HTTP/2 Conversion"| E
    E -->|"(5). gRPC Response<br/>HTTP/2"| D
    D -->|"(6). HTTP/1.1<br/>Response"| C
    C -->|"(7). HTTP/1.1<br/>Response"| B
    B -->|"(8). gRPC Response<br/>HTTP/2"| A

    style A fill:#e1f5fe
    style B fill:#f3e5f5
    style C fill:#fff3e0
    style D fill:#f3e5f5
    style E fill:#e8f5e8
```

## Protocol Flow Details

### Request Flow
1. **Client → Client-Side Proxy**: gRPC request over HTTP/2 with TLS
2. **Client-Side Proxy**:
   - Terminates TLS
   - Applies `grpc_http1_reverse_bridge` filter for HTTP/1.1 conversion
   - Converts gRPC to HTTP/1.1 POST request
   - Re-encrypts for WAF
3. **WAF**:
   - Inspects HTTP/1.1 traffic
   - Applies security policies
   - Forwards to server-side proxy
4. **Server-Side Proxy**:
   - Receives HTTP/1.1 request
   - Applies `grpc_http1_bridge` filter to convert back to gRPC
   - Forwards native gRPC over HTTP/2 to server
5. **gRPC Server**: Processes business logic with full gRPC semantics

### Response Flow
1. **gRPC Server**: Returns gRPC response over HTTP/2
2. **Server-Side Proxy**:
   - Converts gRPC response to HTTP/1.1
3. **WAF**: Forwards HTTP/1.1 response
4. **Client-Side Proxy**:
   - Converts HTTP/1.1 back to native gRPC
5. **Client**: Receives native gRPC response

## Configuration Files

### Directory Structure
```
.
├── docker-compose.yml                 # Service orchestration
├── client-side-proxy/
│   └── envoy.yaml                    # Client-side Envoy configuration
├── server-side-proxy/
│   └── envoy.yaml                    # Server-side Envoy configuration
├── waf/
│   └── nginx.conf                    # WAF configuration
├── certs/                            # TLS certificates
│   ├── ca.crt, ca.key                # Certificate Authority
│   ├── client-proxy/                 # Client proxy certificates
│   ├── server-proxy/                 # Server proxy certificates
│   ├── waf/                          # WAF certificates
│   ├── grpc-service/                 # gRPC server certificates
│   └── grpc-client/                  # gRPC client certificates
└── generate-certs.sh                 # Certificate generation script
```

### Key Configuration Features

#### Client-Side Proxy (envoy.yaml)
```yaml
# HTTP/2 for downstream (client), HTTP/1.1 for upstream (WAF)
codec_type: HTTP2

http_filters:
- name: envoy.filters.http.grpc_http1_reverse_bridge
  # Converts gRPC to HTTP/1.1
- name: envoy.filters.http.grpc_stats
  # gRPC metrics collection
- name: envoy.filters.http.cors
  # CORS support for web clients
- name: envoy.filters.http.router
```

#### Server-Side Proxy (envoy.yaml)
```yaml
# HTTP/1.1 for downstream (WAF), HTTP/2 for upstream (gRPC server)
codec_type: HTTP1

http_filters:
- name: envoy.filters.http.grpc_http1_bridge
  # Converts HTTP/1.1 back to gRPC
- name: envoy.filters.http.grpc_stats
- name: envoy.filters.http.router
```

## Setup and Deployment

### Prerequisites
- Docker and Docker Compose
- Valid TLS certificates (generated via `generate-certs.sh`)

### Quick Start
```bash
# Generate certificates
./generate-certs.sh

# Start all services
docker compose up

# Test the setup
docker compose run --rm user-grpc-client
```

### Service URLs
- **gRPC Client → Client-Side Proxy**: `client-side-proxy:8443`
- **Client-Side Proxy → WAF**: `waf:443`
- **WAF → Server-Side Proxy**: `server-side-proxy:8443`
- **Server-Side Proxy → gRPC Server**: `user-grpc-server:50051`

## Testing and Validation

### Health Check Flow
```bash
# Direct connection to gRPC server (baseline)
docker compose run --rm -e SERVER_ADDRESS=user-grpc-server:50051 \
  -e TLS_SERVER_NAME=user-grpc-server user-grpc-client

# Through proxy chain
docker compose up user-grpc-client
```

### Log Monitoring
```bash
# Monitor proxy logs
docker compose logs -f client-side-proxy
docker compose logs -f server-side-proxy
docker compose logs -f waf

# Monitor gRPC server
docker compose logs -f user-grpc-server
```

## Known Limitations and Considerations

### Performance Characteristics
- **Protocol Overhead**: Double conversion (gRPC ↔ HTTP/1.1) adds latency
- **Streaming**: Client and server streaming work but may have higher latency than direct gRPC
- **Connection Pooling**: HTTP/1.1 connection limitations may affect high-throughput scenarios
- **Trailer Handling**: gRPC trailers are converted to HTTP status codes and headers

### WAF Integration Benefits
- **Content Inspection**: WAF can inspect HTTP/1.1 content for security threats
- **Standard Policies**: HTTP/1.1 security policies work with converted gRPC traffic
- **Logging**: Complete request/response logging available at WAF level

### Alternative Approaches
For specific use cases, consider:
- **Custom Gateway**: For maximum performance and custom security logic
- **HTTP/2 WAF**: Upgrade to HTTP/2-capable WAF for native gRPC support
- **Service Mesh**: Use Istio/Linkerd for more advanced traffic management

## Monitoring and Observability

### Metrics Available
- **Envoy Admin Interface**: `http://localhost:9901/stats` (for each proxy)
- **gRPC Statistics**: Request counts, latencies, error rates
- **Connection Metrics**: Pool utilization, connection failures
- **WAF Logs**: Request/response logging via NGINX

### Key Metrics to Monitor
- `grpc.success` / `grpc.failure` counters
- `http.downstream_rq_2xx` / `http.downstream_rq_5xx`
- `cluster.upstream_rq_retry` and `cluster.upstream_rq_timeout`
- Connection pool statistics

## Security Considerations

### TLS Configuration
- End-to-end TLS encryption between all components
- Certificate validation at each hop
- SNI-based routing support

### WAF Integration
- HTTP/1.1 traffic inspection capabilities
- Standard web security policies applicable
- Request/response size limits and timeouts

## Troubleshooting

### Common Issues
1. **Certificate Errors**: Ensure all certificates are properly generated and mounted
2. **Connection Timeouts**: Check network connectivity between services
3. **Health Check Failures**: Verify gRPC server is responding on port 50051
4. **Protocol Mismatches**: Ensure client-side proxy uses HTTP/2 and server-side uses HTTP/1.1

### Debug Commands
```bash
# Check service status
docker compose ps

# View service logs
docker compose logs <service-name>

# Test direct connectivity
docker compose exec client-side-proxy nc -zv waf 443

# Monitor gRPC bridge traffic
docker compose logs -f client-side-proxy | grep grpc
```

## Industry Best Practices

### gRPC-HTTP/1.1 Bridge Benefits

This implementation follows industry best practices for gRPC-HTTP/1.1 integration:

1. **Protocol Conversion**: Envoy bridge filters handle bidirectional conversion between gRPC and HTTP/1.1
2. **Standards Compliance**: Uses official Envoy bridge filters for maximum compatibility
3. **Security Integration**: Enables WAF inspection while maintaining gRPC functionality
4. **Streaming Support**: Supports both unary and streaming gRPC calls through bridge conversion

### Production Considerations

**Scalability**:
- Connection pooling configured for optimal performance
- Health checking ensures traffic only goes to healthy backends
- Retry policies handle transient failures

**Security**:
- End-to-end TLS encryption
- WAF can inspect and filter converted HTTP/1.1 traffic
- Certificate validation at each hop

**Monitoring**:
- Comprehensive gRPC metrics collection
- Request/response logging at each layer
- Health check visibility

### Deployment Patterns

This architecture supports various deployment patterns:
- **Edge Deployment**: Client-side proxy at edge, server-side proxy in private network
- **Service Mesh Integration**: Can be integrated with Istio, Linkerd, or other service mesh solutions
- **Multi-Cloud**: Works across cloud providers and on-premises infrastructure

## Future Enhancements

1. **HTTP/2 WAF Support**: Upgrade to HTTP/2-capable WAF for native gRPC support
2. **Enhanced Monitoring**: Add Prometheus/Grafana for comprehensive metrics
3. **Circuit Breaker**: Implement circuit breaker patterns for resilience
4. **Rate Limiting**: Add request rate limiting at WAF level
5. **Service Mesh**: Consider Istio/Linkerd for more advanced traffic management

## Conclusion

This project demonstrates a **production-ready solution** for gRPC-HTTP/1.1 WAF integration using industry-standard protocols and tools.

### Key Achievements

1. **Complete gRPC Compatibility**: Full preservation of gRPC functionality through bridge filters
2. **WAF Integration**: Enables existing HTTP/1.1 WAF infrastructure to inspect and secure converted gRPC traffic
3. **Standards Compliance**: Uses official Envoy bridge filters for maximum compatibility
4. **Production Ready**: Includes TLS, monitoring, health checks, and error handling

### Technical Success Factors

- **Protocol Bridge**: Successful bidirectional conversion between gRPC and HTTP/1.1
- **Bridge Filters**: Envoy's specialized filters handle complex protocol conversion
- **Security Integration**: WAF can perform content inspection on converted HTTP/1.1 traffic
- **Performance**: Optimized connection pooling and retry policies

### Solution Validation

This implementation validates that:
- **gRPC-HTTP/1.1 WAF integration is fully achievable** with proper protocol bridging
- **Enterprise security requirements** can be met without sacrificing gRPC functionality
- **Existing WAF infrastructure** can be leveraged for gRPC service protection
- **Industry-standard approaches** provide reliable, maintainable solutions

### Deployment Readiness

The architecture is ready for production deployment with:
- ✅ Complete TLS certificate management
- ✅ Comprehensive monitoring and logging
- ✅ Health checking and failover
- ✅ Configurable security policies
- ✅ Scalable proxy infrastructure

**This project proves that modern gRPC services can be successfully deployed behind traditional HTTP/1.1 WAF infrastructure while maintaining full protocol compatibility and security.**

## Contributing

This project demonstrates enterprise-grade gRPC integration patterns. Contributions welcome for:
- Enhanced error handling
- Additional security features
- Performance optimizations
- Documentation improvements

## License

[Add appropriate license information]
