# Stage 1: Build
FROM node:20-slim AS build

WORKDIR /app

COPY package*.json ./

RUN npm ci --no-audit --no-fund

COPY . .

RUN npm run build

RUN npm ci --production --no-audit --no-fund

# Stage 2: Production
FROM node:20-slim

WORKDIR /app

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

EXPOSE 3001

CMD ["node", "dist/server/server.js"]