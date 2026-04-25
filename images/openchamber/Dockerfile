# =============================================================================
# Stage 1: Build OpenChamber frontend (Bun)
# =============================================================================
FROM oven/bun:1 AS builder
WORKDIR /app

COPY package.json bun.lock ./
COPY packages/ui/package.json ./packages/ui/
COPY packages/web/package.json ./packages/web/
COPY packages/desktop/package.json ./packages/desktop/
COPY packages/vscode/package.json ./packages/vscode/
RUN bun install --ignore-scripts

COPY . .
RUN bun run build:web

# =============================================================================
# Stage 2: Runtime rootfs (Ubuntu 24.04 + systemd + OpenChamber)
# =============================================================================
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG BUN_VERSION=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus sudo \
    curl unzip ca-certificates \
    bash git less openssh-client python3 \
    bind9-utils bzip2 findutils gzip iptables iputils-ping \
    ncurses-base openssl procps tar unzip debianutils whois zstd \
    iproute2 iputils-tracepath netcat-openbsd \
    vim-tiny nano jq dnsutils tcpdump strace lsof \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && mkdir -p /etc/sudoers.d \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && chown -R ubuntu:ubuntu /home/ubuntu

RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr bash

COPY --from=cloudflare/cloudflared:latest /usr/local/bin/cloudflared /usr/local/bin/cloudflared

WORKDIR /home/openchamber

RUN groupadd -g 1001 openchamber \
    && useradd -u 1001 -g 1001 -m -s /bin/bash openchamber \
    && mkdir -p /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh \
    && chown -R openchamber:openchamber /home/openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=/home/openchamber/.npm-global/bin:/usr/bin:/usr/local/bin:$PATH

USER openchamber
RUN npm config set prefix /home/openchamber/.npm-global \
    && mkdir -p /home/openchamber/.npm-global \
    && npm install -g opencode-ai
USER root

COPY scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh
RUN chmod +x /home/openchamber/openchamber-entrypoint.sh

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder /app/packages/web/bin ./packages/web/bin
COPY --from=builder /app/packages/web/server ./packages/web/server
COPY --from=builder /app/packages/web/dist ./packages/web/dist

RUN chown -R openchamber:openchamber /home/openchamber

ENV NODE_ENV=production
ENV OPENCHAMBER_HOST=0.0.0.0

RUN OPENCODE_AUTH_PASSWORD=$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=') \
    && printf '%s' "$OPENCODE_AUTH_PASSWORD" > /etc/openchamber-opencode-password \
    && chmod 640 /etc/openchamber-opencode-password \
    && chgrp openchamber /etc/openchamber-opencode-password \
    && printf '[Unit]\n\
Description=OpenCode AI Agent Server\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=openchamber\n\
Environment=HOME=/home/openchamber\n\
Environment=PATH=/home/openchamber/.npm-global/bin:/usr/local/bin:/usr/bin:/bin\n\
Environment=OPENCODE_SERVER_PASSWORD=%s\n\
ExecStart=/home/openchamber/.npm-global/bin/opencode serve --hostname 127.0.0.1 --port 4096\n\
Restart=always\n\
RestartSec=5\n\
WorkingDirectory=/home/openchamber\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' "$OPENCODE_AUTH_PASSWORD" > /etc/systemd/system/opencode.service \
    && printf '[Unit]\n\
Description=OpenChamber Web UI\n\
After=network.target opencode.service\n\
Wants=opencode.service\n\
\n\
[Service]\n\
Type=simple\n\
User=openchamber\n\
Environment=HOME=/home/openchamber\n\
Environment=NODE_ENV=production\n\
Environment=OPENCHAMBER_HOST=0.0.0.0\n\
Environment=OPENCHAMBER_PORT=3000\n\
Environment=PATH=/home/openchamber/.npm-global/bin:/usr/local/bin:/usr/bin:/bin\n\
Environment=OPENCODE_SKIP_START=true\n\
Environment=OPENCODE_PORT=4096\n\
Environment=OPENCODE_HOST=http://127.0.0.1:4096\n\
Environment=OPENCODE_SERVER_PASSWORD=%s\n\
ExecStartPre=/bin/sh -c "ssh-keygen -t ed25519 -N \"\" -f /home/openchamber/.ssh/id_ed25519 2>/dev/null || true"\n\
ExecStart=/usr/bin/node packages/web/bin/cli.js --foreground --port 3000\n\
Restart=always\n\
RestartSec=5\n\
WorkingDirectory=/home/openchamber\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' "$OPENCODE_AUTH_PASSWORD" > /etc/systemd/system/openchamber.service \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s /etc/systemd/system/opencode.service \
       /etc/systemd/system/multi-user.target.wants/opencode.service \
    && ln -s /etc/systemd/system/openchamber.service \
       /etc/systemd/system/multi-user.target.wants/openchamber.service

RUN rm -rf /tmp/*
