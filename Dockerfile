# syntax=docker/dockerfile:1.7

# Upstream Pages CMS release to package. This is the single source of truth for
# the version: the Makefile reads it from here and uses it as the image tag.
ARG PAGESCMS_VERSION=2.1.8
ARG NODE_VERSION=24

# ---------------------------------------------------------------------------
# source: fetch the tagged upstream release
# ---------------------------------------------------------------------------
FROM alpine:3 AS source
ARG PAGESCMS_VERSION
ADD --keep-git-dir=false https://github.com/pagescms/pagescms.git#${PAGESCMS_VERSION} /src

# ---------------------------------------------------------------------------
# deps: install exactly what upstream's lockfile pins
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS deps
WORKDIR /src
COPY --from=source /src/package.json /src/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund

# ---------------------------------------------------------------------------
# build: produce a Next.js standalone server
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS build
WORKDIR /src
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=source /src ./
COPY --from=deps /src/node_modules ./node_modules
# Wrap upstream's next.config.mjs so we can enable `output: "standalone"`
# without editing upstream files in place.
RUN mv next.config.mjs next.config.upstream.mjs
COPY docker/next.config.mjs ./next.config.mjs
# Call `next build` directly: `npm run build` triggers upstream's `postbuild`
# hook, which runs DB migrations and would need a database at build time.
# BASE_URL is required at module load; this placeholder only satisfies the
# build. The real value is read from the environment at runtime.
RUN BASE_URL=http://build.invalid npx next build

# ---------------------------------------------------------------------------
# runtime
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS runtime
ARG PAGESCMS_VERSION

LABEL org.opencontainers.image.title="pagescms" \
      org.opencontainers.image.description="Pages CMS packaged as a container image" \
      org.opencontainers.image.version="${PAGESCMS_VERSION}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.url="https://pagescms.org" \
      org.opencontainers.image.source="https://github.com/pagescms/pagescms"

RUN apk add --no-cache tini

WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    MIGRATE_ON_START=true \
    PAGESCMS_VERSION=${PAGESCMS_VERSION}

# Standalone server, static assets and public files.
COPY --from=build --chown=node:node /src/.next/standalone ./
COPY --from=build --chown=node:node /src/.next/static ./.next/static
COPY --from=build --chown=node:node /src/public ./public
# Migration SQL plus the (dependency-free) packages the migrator needs. The
# standalone trace only includes the parts of these the app itself imports.
COPY --from=build --chown=node:node /src/db/migrations ./db/migrations
COPY --from=build --chown=node:node /src/node_modules/drizzle-orm ./node_modules/drizzle-orm
COPY --from=build --chown=node:node /src/node_modules/postgres ./node_modules/postgres
COPY --chown=node:node docker/migrate.mjs ./docker/migrate.mjs
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh

# The Next.js cache dir must be writable (mount an emptyDir here when running
# with a read-only root filesystem).
RUN mkdir -p .next/cache && chown node:node .next/cache

# Numeric UID so Kubernetes `runAsNonRoot` can verify it. 1000 = `node`.
USER 1000:1000
EXPOSE 3000

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["serve"]
