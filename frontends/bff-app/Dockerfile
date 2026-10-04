FROM node:22-alpine AS build
WORKDIR /app
COPY package.json vite.config.js index.html ./
COPY src src
ARG VITE_API_URL
ARG VITE_ARCHITECTURE
ENV VITE_API_URL=$VITE_API_URL VITE_ARCHITECTURE=$VITE_ARCHITECTURE
RUN npm install --no-audit --no-fund && npm run build
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

