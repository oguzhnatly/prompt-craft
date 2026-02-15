# VPS fallback — runs the proxy as a Node.js server using Miniflare
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npx tsc --noEmit

FROM node:22-alpine
WORKDIR /app
COPY --from=builder /app .
EXPOSE 8787
CMD ["npx", "wrangler", "dev", "--local", "--port", "8787", "--host", "0.0.0.0"]
