# Multi-stage Dockerfile for JsonAtomic
# Production-hardened with non-root user, read-only filesystem, and minimal capabilities

# Stage 1: Build
FROM node:24.1.0-alpine3.20 AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies with npm ci for reproducible builds
RUN npm ci --only=production && \
    npm cache clean --force

# Copy source code
COPY . .

# Build TypeScript
RUN npm run build

# Stage 2: Runtime
FROM node:24.1.0-alpine3.20 AS runtime

# Security: Create non-root user
RUN addgroup -g 1001 -S jsonatomic && \
    adduser -u 1001 -S jsonatomic -G jsonatomic

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install only production dependencies
RUN npm ci --only=production && \
    npm cache clean --force && \
    rm -rf /root/.npm

# Copy built files from builder
COPY --from=builder --chown=jsonatomic:jsonatomic /app/dist ./dist
COPY --from=builder --chown=jsonatomic:jsonatomic /app/schemas ./schemas

# Create data directory with proper permissions
RUN mkdir -p /app/data && \
    chown -R jsonatomic:jsonatomic /app

# Security: Use non-root user
USER jsonatomic:jsonatomic

# Expose ports (non-privileged)
EXPOSE 8000 9090

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:8000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Set environment variables
ENV NODE_ENV=production \
    PORT=8000 \
    HOST=0.0.0.0 \
    LEDGER_PATH=/app/data/ledger.jsonl

# Security labels for metadata
LABEL org.opencontainers.image.title="JsonAtomic" \
      org.opencontainers.image.description="Ledger-based constitutional governance platform" \
      org.opencontainers.image.version="1.1.0" \
      org.opencontainers.image.vendor="LogLineOS" \
      org.opencontainers.image.source="https://github.com/danvoulez/JsonAtomic" \
      org.opencontainers.image.licenses="MIT"

# Start the application
# Note: For maximum security in production, run with:
# docker run --read-only --cap-drop=ALL -v data:/app/data --tmpfs /tmp jsonatomic
# - --read-only: Read-only root filesystem
# - --cap-drop=ALL: Drop all Linux capabilities
# - -v data:/app/data: Writable volume for ledger data
# - --tmpfs /tmp: Temporary filesystem for runtime
CMD ["node", "dist/index.js"]
