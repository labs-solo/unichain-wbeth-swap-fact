# Dockerfile for HyperIndex UniChain WBTC/ETH indexer
# Builds from enviodev/uniswap-v4-indexer pinned tag with pnpm

FROM node:18-alpine AS builder

# Install pnpm
RUN npm install -g pnpm@8.6.12

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json pnpm-lock.yaml* ./

# Install dependencies without strict lockfile check
RUN pnpm install --no-frozen-lockfile

# Copy source code and config
COPY . .

# Build the indexer
RUN pnpm build

# Production stage
FROM node:18-alpine AS runner

# Install runtime dependencies
RUN apk add --no-cache postgresql-client curl

# Install pnpm in production stage
RUN npm install -g pnpm@8.6.12

WORKDIR /app

# Copy built application
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/pnpm-lock.yaml ./pnpm-lock.yaml

# Copy configuration
COPY config.yaml ./
COPY mappings.ts ./

# Create non-root user
RUN addgroup -g 1001 -S hyperindex && \
    adduser -S hyperindex -u 1001

# Change ownership
RUN chown -R hyperindex:hyperindex /app
USER hyperindex

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Default command
CMD ["pnpm", "start"]

# Environment variables
ENV NODE_ENV=production
ENV CHAIN_ID=11877
ENV LOG_LEVEL=info 