# Trust Store Manager - Multi-stage Docker Build
# Supports both Bash and Go implementations with full JRE support

# Stage 1: Build Go binary
FROM golang:1.21-alpine AS go-builder

WORKDIR /app/go-trust-store-manager

# Install build dependencies
RUN apk add --no-cache git ca-certificates

# Copy Go source and dependencies
COPY go-trust-store-manager/go.mod go-trust-store-manager/go.sum ./
RUN go mod download

# Copy Go source code
COPY go-trust-store-manager/ ./

# Build the Go binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w -X main.version=$(date +%Y%m%d-%H%M%S)" \
    -o trust-store-manager .

# Stage 2: Create runtime image
FROM eclipse-temurin:11-jre-alpine

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    curl \
    openssl \
    ca-certificates \
    git \
    && rm -rf /var/cache/apk/*

# Create non-root user for security
RUN addgroup -g 1000 truststore && \
    adduser -D -s /bin/bash -u 1000 -G truststore truststore

# Set working directory
WORKDIR /app

# Copy built Go binary from builder stage
COPY --from=go-builder /app/go-trust-store-manager/trust-store-manager /usr/local/bin/

# Copy bash implementation
COPY bash-trust-store-manager/ ./bash-trust-store-manager/
RUN chmod +x ./bash-trust-store-manager/*.sh

# Copy configuration
COPY config.yaml ./

# Create necessary directories
RUN mkdir -p /app/logs /app/backups /app/data && \
    chown -R truststore:truststore /app

# Switch to non-root user
USER truststore

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD trust-store-manager --help > /dev/null || exit 1

# Default configuration
ENV TRUST_STORE_CONFIG="/app/config.yaml"
ENV TRUST_STORE_LOG_DIR="/app/logs"
ENV TRUST_STORE_BACKUP_DIR="/app/backups"

# Expose typical ports (if needed for webhook endpoints)
EXPOSE 8080

# Default command - display help
CMD ["trust-store-manager", "--help"]

# Build-time metadata
LABEL maintainer="Trust Store Manager Team" \
      description="Enterprise SSL/TLS Trust Store Management Tool" \
      version="1.0.0" \
      org.opencontainers.image.title="Trust Store Manager" \
      org.opencontainers.image.description="Automated SSL/TLS trust store management with centralized logging" \
      org.opencontainers.image.vendor="Trust Store Manager" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/Mudaserb365/ssl.git" 