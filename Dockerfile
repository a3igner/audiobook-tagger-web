# Audiobook Tagger (forked from philipvox/audiobook-tagger-web)
# Self-hosted web version. 100% client-side static site.
#
# Build:   docker build -t audiobook-tagger .
# Run:     docker run -d -p 8082:80 --name audiobook-tagger audiobook-tagger
# Access:  http://localhost:8082
#
# Build args (override at build time):
#   LITELLM_UPSTREAM  — URL of your LiteLLM server. Default: http://localhost:4000
#                       Examples:
#                         --build-arg LITELLM_UPSTREAM=http://litellm.local:4000
#                         --build-arg LITELLM_UPSTREAM=http://10.0.0.5:4000
#
#   VITE_BASE_PATH    — URL path the SPA is served from. Default: /
#                       If serving from a subpath (e.g. behind Caddy at /tagger/),
#                       set this so Vite rewrites all asset URLs:
#                         --build-arg VITE_BASE_PATH=/tagger/
#
# For Unraid: Add as a Docker container, map port 80 to your preferred port.
# Note: When self-hosting over HTTP, your ABS server can also be HTTP
# (no mixed content issue).
#
# Local patch: --ignore-scripts because rollup 4.53.0 in package-lock.json
# ships a postinstall that calls `patch-package` (unrelated to rollup) which
# is not declared as a dep. Skipping is safe — vite doesn't need that hook.
#
# nginx config (see nginx.conf) provides:
#   SPA fallback for the React app
#   /api/litellm/*      → same-origin reverse proxy to local LiteLLM
#   /api/audible/*      → reverse proxy to api.audible.com (for ISBN/ASIN/publisher lookup)
#   /api/openlibrary/*  → reverse proxy to openlibrary.org (for ISBN/year/publisher)

FROM node:20-slim AS build
ARG VITE_BASE_PATH=/
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY src/ src/
COPY index.html vite.config.js tailwind.config.js postcss.config.js ./
RUN VITE_BASE_PATH=${VITE_BASE_PATH} npm run build

FROM nginx:alpine
ARG LITELLM_UPSTREAM=http://localhost:4000
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
# Substitute the LiteLLM upstream placeholder at build time. Uses sed so we
# don't need to install gettext/envsubst. The nginx $host, $remote_addr, etc.
# variables are untouched — sed only replaces the literal ${LITELLM_UPSTREAM}.
RUN sed -i "s|\${LITELLM_UPSTREAM}|${LITELLM_UPSTREAM}|g" /etc/nginx/conf.d/default.conf
EXPOSE 80
