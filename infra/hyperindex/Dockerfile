# Dockerfile for HyperIndex UniChain WBTC/ETH indexer
FROM node:18-alpine AS builder

# Install build dependencies
RUN apk add --no-cache python3 make g++ postgresql-client curl

# Install pnpm and envio
RUN npm install -g pnpm@8.6.12 envio@2.21.5

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json pnpm-lock.yaml* ./

# Install dependencies
RUN pnpm install

# Copy configuration and source
COPY . .

# Generate code and build
RUN envio codegen && pnpm build

# Production stage
FROM node:18-alpine AS runner

# Install runtime dependencies
RUN apk add --no-cache postgresql-client curl

# Install envio CLI
RUN npm install -g envio@2.21.5

WORKDIR /app

# Copy built application and config
COPY --from=builder /app ./

# Create non-root user
RUN addgroup -g 1001 -S hyperindex && \
    adduser -S hyperindex -u 1001

# Change ownership
RUN chown -R hyperindex:hyperindex /app
USER hyperindex

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