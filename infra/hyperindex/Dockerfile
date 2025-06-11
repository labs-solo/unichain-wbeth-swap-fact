# syntax=docker/dockerfile:1
# Dockerfile for HyperIndex UniChain WBTC/ETH indexer
FROM node:18 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y python3 make g++ postgresql-client curl

# Install envio
RUN npm install -g envio@2.21.5

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Copy configuration and source
COPY . .

# Generate code
RUN --mount=type=secret,id=.env sh -c 'set -a && . /run/secrets/.env && set +a && envio codegen'

# Production stage
FROM node:18 AS runner

# Install runtime dependencies
RUN apt-get update && apt-get install -y postgresql-client curl

# Install envio CLI and pnpm
RUN npm install -g envio@2.21.5 pnpm

WORKDIR /app

# Copy built application and config
COPY --from=builder /app ./

# Create non-root user and home directory
RUN addgroup --system --gid 1001 hyperindex && \
    adduser --system --uid 1001 --gid 1001 hyperindex && \
    mkdir -p /home/hyperindex && \
    chown -R hyperindex:hyperindex /home/hyperindex

# Change ownership
RUN chown -R hyperindex:hyperindex /app
USER hyperindex

# Set home directory for user
ENV HOME=/home/hyperindex

# Health check for envio start (GraphQL endpoint or health endpoint)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/health || curl -f http://localhost:8080/graphql || exit 1

# Environment variables
ENV NODE_ENV=production
ENV CHAIN_ID=11877
ENV LOG_LEVEL=info
ENV TZ=UTC

# Run the envio indexer in production mode
CMD ["envio", "start"] 