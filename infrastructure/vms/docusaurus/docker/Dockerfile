FROM node:22-alpine AS build

WORKDIR /app

COPY docusaurus-site/package.json docusaurus-site/package-lock.json ./
RUN npm ci

COPY docusaurus-site/ ./
RUN npm run build

FROM nginx:1.27-alpine

COPY infrastructure/vms/docusaurus/docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1
