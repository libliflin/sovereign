# Stage 1: Build frontend (Vite)
FROM node:20-alpine AS frontend-builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --ignore-scripts
COPY src/client/ ./src/client/
COPY tsconfig.client.json ./
COPY vite.config.ts ./
COPY tailwind.config.js ./
COPY postcss.config.js ./
RUN npx vite build

# Stage 2: Build backend (TypeScript → JavaScript)
FROM node:20-alpine AS backend-builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --ignore-scripts
COPY src/server/ ./src/server/
COPY tsconfig.json ./
COPY tsconfig.server.json ./
RUN npx tsc --project tsconfig.server.json

# Stage 3: Production image (distroless-equivalent: node:20-alpine minimal)
# NOTE: Using node:20-alpine as the production base because Node.js services
# cannot use gcr.io/distroless/static (requires a C runtime + node binary).
# This service has a deprecation entry in vendor/VENDORS.yaml:
#   sovereign-pm: deprecated: true, deprecated_reason: "Node.js runtime requires non-distroless base"
#   alternative: "Rewrite in Go or Rust for gcr.io/distroless/static compatibility"
FROM node:20-alpine AS production
RUN apk add --no-cache dumb-init
WORKDIR /app

# Copy only production dependencies
COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts

# Copy compiled backend
COPY --from=backend-builder /app/dist/server ./dist/server

# Copy built frontend (served as static files by Express in production)
COPY --from=frontend-builder /app/dist/client ./dist/client

# Copy ralph scripts (for the Job container variant)
COPY --chown=node:node . ./

# Run as non-root
USER node

EXPOSE 3000
ENV NODE_ENV=production

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/server/index.js"]
