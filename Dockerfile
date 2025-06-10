# syntax=docker/dockerfile:1

# Stage 1: Build
FROM node:18-alpine as builder

# Install corepack and pin exact pnpm version
RUN corepack enable && corepack prepare pnpm@9.7.0 --activate

WORKDIR /build

# Copy package files
COPY package.json pnpm-lock.yaml ./
COPY pnpm-workspace.yaml ./

# Install dependencies reproducibly
RUN pnpm install --frozen-lockfile

# Copy source code
COPY . .

# Generate code and build
RUN pnpm codegen && pnpm build

# Stage 2: Runtime
FROM node:18-alpine

WORKDIR /app

# Install corepack and pin exact pnpm version
RUN corepack enable && corepack prepare pnpm@9.7.0 --activate

# Copy built files and dependencies
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/generated ./generated
COPY --from=builder /build/package.json ./

# Set environment
ENV NODE_ENV=production

# Set the entrypoint to use ts-node for the generated code
ENTRYPOINT ["./node_modules/.bin/ts-node", "generated/src/Index.bs.js"] 