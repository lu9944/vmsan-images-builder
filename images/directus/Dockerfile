# syntax=docker/dockerfile:1.4

# =============================================================================
# Stage 1: Build Directus from source (Node.js 22 + pnpm monorepo)
# =============================================================================
FROM node:22-slim AS builder

# Build dependencies for native Node modules (sqlite3, sharp, argon2, isolated-vm)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

# Ensure corepack is up-to-date (node:22-slim ships an older version)
RUN npm install --global corepack@latest

WORKDIR /directus

COPY package.json ./
RUN corepack enable && corepack prepare

# Deploy as 'node' user to match production setup
RUN chown node:node .
USER node

ENV NODE_OPTIONS=--max-old-space-size=8192

# Fetch dependencies into pnpm store (cached layer)
COPY pnpm-lock.yaml ./
RUN pnpm fetch

# Copy full source and build
COPY --chown=node:node . .
RUN <<'BUILDEOF'
set -ex
pnpm install --recursive --offline --frozen-lockfile
npm_config_workspace_concurrency=2 pnpm run build
pnpm --filter directus deploy --legacy --prod dist
cd dist
# Regenerate package.json with essential fields only
# (see https://github.com/directus/directus/issues/20338)
node --input-type=commonjs -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json","utf8"));const r=JSON.parse(fs.readFileSync("../package.json","utf8"));fs.writeFileSync("package.json",JSON.stringify({name:p.name,version:p.version,type:p.type,exports:p.exports,bin:p.bin,packageManager:r.packageManager},null,2));'
mkdir -p database extensions uploads
BUILDEOF

# =============================================================================
# Stage 2: Runtime rootfs (Ubuntu 24.04 + systemd + Directus)
# =============================================================================
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# System packages: systemd (required by vmsan) + dev tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus sudo \
    ca-certificates curl wget git \
    bind9-utils bzip2 findutils gzip iptables iputils-ping \
    ncurses-base openssl procps tar unzip debianutils whois zstd \
    iproute2 iputils-tracepath netcat-openbsd \
    vim-tiny nano jq dnsutils tcpdump strace lsof less \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

# Install Node.js 22 from builder stage (same version as build = binary compat)
COPY --from=builder /usr/local/bin/node /usr/local/bin/node
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Create ubuntu user with passwordless sudo
RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && mkdir -p /etc/sudoers.d \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && chown -R ubuntu:ubuntu /home/ubuntu

# Copy built Directus application (source-deployed from pnpm deploy)
COPY --from=builder --chown=ubuntu:ubuntu /directus/dist /opt/directus

# Create data directories
RUN mkdir -p /opt/directus/database /opt/directus/extensions /opt/directus/uploads \
    && chown -R ubuntu:ubuntu /opt/directus

# Default environment
ENV DB_CLIENT=sqlite3 \
    DB_FILENAME=/opt/directus/database/database.sqlite \
    NODE_ENV=production \
    PORT=8055 \
    HOST=0.0.0.0 \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# Create systemd service for Directus auto-start
# (startup script is installed by post-extract.sh)
RUN printf '[Unit]\n\
Description=Directus CMS\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=ubuntu\n\
ExecStart=/usr/local/bin/directus-start.sh\n\
Restart=always\n\
RestartSec=5\n\
Environment=HOME=/home/ubuntu\n\
Environment=NODE_ENV=production\n\
WorkingDirectory=/opt/directus\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' \
    > /etc/systemd/system/directus.service \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s /etc/systemd/system/directus.service \
       /etc/systemd/system/multi-user.target.wants/directus.service

EXPOSE 8055

RUN rm -rf /tmp/*
