# Stage 1: Build
FROM node:20-slim AS build

WORKDIR /app

COPY package*.json ./

# npm ci with explicit verification that it succeeds
RUN npm ci --legacy-peer-deps --no-audit --no-fund || \
    (echo "npm ci failed" && exit 1)

# Verify node_modules was created with files
RUN test -d node_modules && [ "$(find node_modules -type f | wc -l)" -gt 100 ] || \
    (echo "node_modules missing or empty!" && exit 1)

# List installed packages to verify
RUN npm list --depth=0

COPY . .

RUN npm run build

RUN npm prune --production

# Stage 2: Production
FROM node:20-slim

WORKDIR /app

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

EXPOSE 3001

CMD ["node", "dist/server/server.js"]