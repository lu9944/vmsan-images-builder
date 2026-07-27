# syntax=docker/dockerfile:1.4
# =============================================================================
# vmsan rootfs image for LobeHub (Next.js standalone web service).
#
# Stages 1-3 are taken verbatim from the upstream LobeHub Dockerfile so the
# production build is identical to the official image. Stage 4 assembles a
# systemd-based Ubuntu rootfs that auto-starts the web service on boot, which
# is what vmsan (Firecracker microVM) requires.
# =============================================================================

## Set global build ENV
ARG NODEJS_VERSION="24"

## -----------------------------------------------------------------------------
## Stage 1: Base image — node runtime + distroless libs (proxychains, ssl, ...)
## -----------------------------------------------------------------------------
FROM node:${NODEJS_VERSION}-slim AS base

ARG USE_CN_MIRROR

ENV DEBIAN_FRONTEND="noninteractive"

RUN set -e && \
    if [ "${USE_CN_MIRROR:-false}" = "true" ]; then \
        sed -i "s/deb.debian.org/mirrors.ustc.edu.cn/g" "/etc/apt/sources.list.d/debian.sources"; \
    fi && \
    apt update && \
    apt install ca-certificates proxychains-ng -qy && \
    mkdir -p /distroless/bin /distroless/etc /distroless/etc/ssl/certs /distroless/lib && \
    cp /usr/lib/$(arch)-linux-gnu/libproxychains.so.4 /distroless/lib/libproxychains.so.4 && \
    cp /usr/lib/$(arch)-linux-gnu/libdl.so.2 /distroless/lib/libdl.so.2 && \
    cp /usr/bin/proxychains4 /distroless/bin/proxychains && \
    cp /etc/proxychains4.conf /distroless/etc/proxychains4.conf && \
    cp /usr/lib/$(arch)-linux-gnu/libstdc++.so.6 /distroless/lib/libstdc++.so.6 && \
    cp /usr/lib/$(arch)-linux-gnu/libgcc_s.so.1 /distroless/lib/libgcc_s.so.1 && \
    cp /usr/lib/$(arch)-linux-gnu/librt.so.1 /distroless/lib/librt.so.1 && \
    cp /usr/local/bin/node /distroless/bin/node && \
    cp /etc/ssl/certs/ca-certificates.crt /distroless/etc/ssl/certs/ca-certificates.crt && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

## -----------------------------------------------------------------------------
## Stage 2: Builder — install deps and build the Next.js standalone app
## -----------------------------------------------------------------------------
FROM base AS builder

ARG USE_CN_MIRROR
ARG NEXT_PUBLIC_BASE_PATH
ARG NEXT_PUBLIC_SENTRY_DSN
ARG NEXT_PUBLIC_ANALYTICS_POSTHOG
ARG NEXT_PUBLIC_POSTHOG_HOST
ARG NEXT_PUBLIC_POSTHOG_KEY
ARG NEXT_PUBLIC_ANALYTICS_UMAMI
ARG NEXT_PUBLIC_UMAMI_SCRIPT_URL
ARG NEXT_PUBLIC_UMAMI_WEBSITE_ID
ARG FEATURE_FLAGS

ENV NEXT_PUBLIC_BASE_PATH="${NEXT_PUBLIC_BASE_PATH}" \
    FEATURE_FLAGS="${FEATURE_FLAGS}"

ENV APP_URL="http://app.com" \
    DATABASE_DRIVER="node" \
    DATABASE_URL="postgres://postgres:password@localhost:5432/postgres" \
    KEY_VAULTS_SECRET="use-for-build" \
    AUTH_SECRET="use-for-build"

# Sentry
ENV NEXT_PUBLIC_SENTRY_DSN="${NEXT_PUBLIC_SENTRY_DSN}" \
    SENTRY_ORG="" \
    SENTRY_PROJECT=""

# Posthog
ENV NEXT_PUBLIC_ANALYTICS_POSTHOG="${NEXT_PUBLIC_ANALYTICS_POSTHOG}" \
    NEXT_PUBLIC_POSTHOG_HOST="${NEXT_PUBLIC_POSTHOG_HOST}" \
    NEXT_PUBLIC_POSTHOG_KEY="${NEXT_PUBLIC_POSTHOG_KEY}"

# Umami
ENV NEXT_PUBLIC_ANALYTICS_UMAMI="${NEXT_PUBLIC_ANALYTICS_UMAMI}" \
    NEXT_PUBLIC_UMAMI_SCRIPT_URL="${NEXT_PUBLIC_UMAMI_SCRIPT_URL}" \
    NEXT_PUBLIC_UMAMI_WEBSITE_ID="${NEXT_PUBLIC_UMAMI_WEBSITE_ID}"

# Node
ENV NODE_OPTIONS="--max-old-space-size=8192"

WORKDIR /app

COPY package.json pnpm-workspace.yaml ./
COPY .npmrc ./
COPY packages ./packages
COPY patches ./patches
# bring in desktop workspace manifest so pnpm can resolve it
COPY apps/desktop/src/main/package.json ./apps/desktop/src/main/package.json

RUN set -e && \
    if [ "${USE_CN_MIRROR:-false}" = "true" ]; then \
        export SENTRYCLI_CDNURL="https://npmmirror.com/mirrors/sentry-cli"; \
        npm config set registry "https://registry.npmmirror.com/"; \
        echo 'canvas_binary_host_mirror=https://npmmirror.com/mirrors/canvas' >> .npmrc; \
    fi && \
    export COREPACK_NPM_REGISTRY=$(npm config get registry | sed 's/\/$//') && \
    npm i -g corepack@latest && \
    corepack enable && \
    corepack use $(sed -n 's/.*"packageManager": "\(.*\)".*/\1/p' package.json) && \
    pnpm i && \
    mkdir -p /deps && \
    cd /deps && \
    echo '{"name":"deps","private":true}' > package.json && \
    pnpm add pg drizzle-orm

COPY . .

# Prebuild: env checks (checkDeprecatedAuth, checkRequiredEnvVars, printEnvInfo) then remove desktop-only code
RUN pnpm exec tsx scripts/dockerPrebuild.mts
RUN rm -rf src/app/desktop "src/app/(backend)/trpc/desktop"

# run build standalone for docker version
RUN npm run build:docker

## -----------------------------------------------------------------------------
## Stage 3: App assembly — collect production files (busybox)
## -----------------------------------------------------------------------------
FROM busybox:latest AS app

COPY --from=base /distroless/ /

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder /app/.next/standalone /app/
COPY --from=builder /app/.next/static /app/.next/static
# Copy SPA assets (Vite build output)
COPY --from=builder /app/public/_spa /app/public/_spa
# Copy database migrations
COPY --from=builder /app/packages/database/migrations /app/migrations
COPY --from=builder /app/scripts/migrateServerDB/docker.cjs /app/docker.cjs
COPY --from=builder /app/scripts/migrateServerDB/errorHint.js /app/errorHint.js

# copy dependencies
COPY --from=builder /deps/node_modules/.pnpm /app/node_modules/.pnpm
COPY --from=builder /deps/node_modules/pg /app/node_modules/pg
COPY --from=builder /deps/node_modules/drizzle-orm /app/node_modules/drizzle-orm

# Copy server launcher and shared scripts
COPY --from=builder /app/scripts/serverLauncher/startServer.js /app/startServer.js
COPY --from=builder /app/scripts/_shared /app/scripts/_shared

RUN set -e && \
    addgroup -S -g 1001 nodejs && \
    adduser -D -G nodejs -H -S -h /app -u 1001 nextjs && \
    chown -R nextjs:nodejs /app /etc/proxychains4.conf

## -----------------------------------------------------------------------------
## Stage 4: vmsan runtime rootfs (Ubuntu 24.04 + systemd)
## -----------------------------------------------------------------------------
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# System packages: systemd (required by vmsan) + dev tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus sudo \
    ca-certificates tzdata \
    curl wget git \
    bind9-utils bzip2 findutils gzip iptables iputils-ping \
    ncurses-base openssl procps tar unzip debianutils whois zstd \
    iproute2 iputils-tracepath netcat-openbsd \
    vim-tiny nano jq dnsutils tcpdump strace lsof less \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

# Create ubuntu user with passwordless sudo
RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && mkdir -p /etc/sudoers.d \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && chown -R ubuntu:ubuntu /home/ubuntu

# Install Node.js from the builder base (same version that built the app).
# node:*-slim binaries run on ubuntu:24.04 (glibc 2.39 >= debian's).
COPY --from=base /usr/local/bin/node /usr/local/bin/node
# startServer.js spawns '/bin/node'; ubuntu uses merged /usr (/bin -> usr/bin)
RUN ln -sf /usr/local/bin/node /usr/bin/node

# Copy the assembled LobeHub application
COPY --from=app /app /app
RUN chown -R ubuntu:ubuntu /app

# proxychains support (only used when PROXY_URL is set).
# startServer.js writes to /etc/proxychains4.conf at runtime as the service user.
RUN : > /etc/proxychains4.conf && chown ubuntu:ubuntu /etc/proxychains4.conf

# Default runtime environment.
# NOTE: DATABASE_DRIVER is intentionally left unset so the app boots in
# client-DB mode (browser-side storage) without needing an external database.
ENV NODE_ENV="production" \
    HOSTNAME="0.0.0.0" \
    PORT="3210" \
    MIDDLEWARE_REWRITE_THROUGH_LOCAL="1" \
    HOME="/home/ubuntu" \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# systemd service: auto-start LobeHub web service on boot
RUN printf '[Unit]\n\
Description=LobeHub Web Service\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=ubuntu\n\
ExecStart=/usr/local/bin/node /app/startServer.js\n\
Restart=always\n\
RestartSec=5\n\
Environment=HOME=/home/ubuntu\n\
Environment=NODE_ENV=production\n\
Environment=HOSTNAME=0.0.0.0\n\
Environment=PORT=3210\n\
Environment=MIDDLEWARE_REWRITE_THROUGH_LOCAL=1\n\
WorkingDirectory=/app\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' \
    > /etc/systemd/system/lobehub.service \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s /etc/systemd/system/lobehub.service \
       /etc/systemd/system/multi-user.target.wants/lobehub.service

EXPOSE 3210

RUN rm -rf /tmp/*
