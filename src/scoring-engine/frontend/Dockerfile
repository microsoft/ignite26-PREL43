# Builds either frontend app from the shared workspace:
#   docker build --build-arg APP=web-admin -t scoring-admin .
#   docker build --build-arg APP=web-scorecard -t scoring-scorecard .
FROM node:22-alpine AS build
ARG APP=web-admin
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npx tsc -p tsconfig.json --noEmit && npx vite build --config ${APP}/vite.config.ts

FROM nginxinc/nginx-unprivileged:1.27-alpine
ARG APP=web-admin
COPY ${APP}/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /src/${APP}/dist /usr/share/nginx/html
ENV API_UPSTREAM=http://api:8000
EXPOSE 8080
