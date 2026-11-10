
# Use a pinned Node.js version
ARG NODE_IMAGE=node:24.22.2-trixie-slim

# Build stage: install dependencies and run tests
FROM ${NODE_IMAGE} AS build

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci

COPY src ./src
COPY tests ./tests

RUN npm test

# Remove development dependencies
RUN npm prune --omit=dev && npm cache clean --force


# Production stage
FROM ${NODE_IMAGE} AS runtime

ARG APP_VERSION=1.0.0

ENV NODE_ENV=production \
    PORT=8080 \
    APP_VERSION=${APP_VERSION}

WORKDIR /app

COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json ./package.json
COPY --chown=node:node src ./src

# Run as a non-root user with a numeric UID and GID
USER 1000:1000

EXPOSE 8080

# OCI image metadata
LABEL org.opencontainers.image.title="DevOps Assessment API" \
      org.opencontainers.image.description="Node.js service for DevOps assessment" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.licenses="MIT"

# Container health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["node", "-e", "require('node:http').get('http://127.0.0.1:8080/health', (res) => process.exit(res.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"]

CMD ["node", "src/server.js"]
