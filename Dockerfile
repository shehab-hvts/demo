# Stage 1: Build
FROM node:20-slim AS build

WORKDIR /app

COPY package*.json ./

RUN npm install --production=false --legacy-peer-deps --no-audit --no-fund && \
    npm list 2>&1 | head -20

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