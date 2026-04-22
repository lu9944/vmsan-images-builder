# =============================================================================
# Stage 1: Build QwenPaw frontend (Node.js)
# =============================================================================
FROM node:20-slim AS console-builder
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_OPTIONS=--max-old-space-size=4096
COPY console/package.json console/package-lock.json ./
RUN npm ci
COPY console/ .
RUN npm run build

# =============================================================================
# Stage 2: Runtime rootfs (Ubuntu 24.04 + systemd + QwenPaw)
# =============================================================================
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# System packages: systemd (required by vmsan) + Python build deps + dev tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv sudo \
    python3 python3-pip python3-venv \
    build-essential libssl-dev git \
    bind9-utils bzip2 findutils gzip iptables iputils-ping \
    libicu-dev libjpeg-dev libpng-dev ncurses-base openssl \
    procps tar unzip debianutils whois zstd \
    curl wget iproute2 iputils-ping iputils-tracepath netcat-openbsd \
    vim-tiny nano jq dnsutils tcpdump strace lsof less \
    && rm -rf /var/lib/apt/lists/*

# Create ubuntu user with passwordless sudo
RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && mkdir -p /etc/sudoers.d \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && chown -R ubuntu:ubuntu /home/ubuntu

ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

# Copy QwenPaw source and built frontend
WORKDIR /build
COPY pyproject.toml setup.py README.md ./
COPY src ./src
COPY --from=console-builder /app/dist ./src/qwenpaw/console/

# Install QwenPaw in a virtual environment
RUN python3 -m venv /opt/qwenpaw-venv \
    && /opt/qwenpaw-venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/qwenpaw-venv/bin/pip install --no-cache-dir .

# Make CLI available system-wide
RUN ln -sf /opt/qwenpaw-venv/bin/qwenpaw /usr/local/bin/qwenpaw \
    && ln -sf /opt/qwenpaw-venv/bin/copaw /usr/local/bin/copaw

# Initialize QwenPaw config as ubuntu user
USER ubuntu
ENV HOME=/home/ubuntu
RUN /usr/local/bin/qwenpaw init --defaults --accept-security
USER root

# Create systemd service for QwenPaw auto-start
RUN printf '[Unit]\n\
Description=QwenPaw AI Assistant\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
ExecStart=/usr/local/bin/qwenpaw app --host 0.0.0.0 --port 8088\n\
Restart=always\n\
RestartSec=5\n\
Environment=HOME=/home/ubuntu\n\
WorkingDirectory=/home/ubuntu\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/qwenpaw.service \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s /etc/systemd/system/qwenpaw.service \
       /etc/systemd/system/multi-user.target.wants/qwenpaw.service

# Clean up build artifacts
RUN rm -rf /build /tmp/*
