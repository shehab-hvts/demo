FROM node:22-slim AS build

WORKDIR /app

COPY package*.json ./

RUN npm install --no-audit --no-fund

COPY . .

RUN npm run build

FROM node:22-slim AS production

WORKDIR /app

COPY package*.json package-lock.json ./

RUN npm install --production --no-audit --no-fund

COPY --from=build /app/dist ./dist

EXPOSE 3001

CMD ["node", "dist/server/server.js"]
