# Stage 1: Build
FROM node:20-slim AS build

WORKDIR /app

# npm 10.8.2 (bundled) has a bug at 71s. Install stable npm 9.x
RUN npm install -g npm@9.8.1 --no-audit --no-fund && \
    npm --version

COPY package*.json ./

# Use npm install with stable npm 9.x (npm ci also had issues)
RUN npm install --prefer-offline --legacy-peer-deps --no-audit --no-fund && \
    npm list --depth=0 && \
    npm prune --production

COPY . .

RUN npm run build

# Stage 2: Production
FROM node:20-slim

WORKDIR /app

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

EXPOSE 3001

CMD ["node", "dist/server/server.js"]