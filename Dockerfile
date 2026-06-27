# Stage 1: Build
FROM node:22-bookworm AS build

WORKDIR /app

COPY package*.json ./

RUN npm install --no-audit --no-fund

COPY . .

RUN npm run build

RUN npm prune --production

# Stage 2: Production
FROM node:22-bookworm

WORKDIR /app

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

EXPOSE 3001

CMD ["node", "dist/server.js"]