# =============================================================================
# Stage 1: Build 1Panel frontend (Node.js)
# =============================================================================
FROM node:20-slim AS frontend-builder
WORKDIR /app
ENV NODE_OPTIONS=--max-old-space-size=8192
COPY frontend/ .
RUN npm install && npm run build:pro

# =============================================================================
# Stage 2: Build 1Panel Go binaries
# =============================================================================
FROM golang:1.25-bookworm AS go-builder
WORKDIR /build

COPY core/go.mod core/go.sum ./core/
COPY agent/go.mod agent/go.sum ./agent/
RUN cd core && go mod download \
    && cd /build/agent && go mod download

COPY core/ ./core/
COPY agent/ ./agent/
COPY --from=frontend-builder /app/dist ./core/cmd/server/web/assets/

RUN cd /build/core \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
       -tags=xpack -trimpath -ldflags '-s -w' \
       -o /build/1panel-core ./cmd/server/main.go

RUN cd /build/agent \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
       -tags=xpack -trimpath -ldflags '-s -w' \
       -o /build/1panel-agent ./cmd/server/main.go

# =============================================================================
# Stage 3: Runtime rootfs (Ubuntu 24.04 + systemd + 1Panel)
# =============================================================================
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv sudo \
    curl wget git \
    bind9-utils bzip2 findutils gzip iptables iputils-ping \
    ncurses-base openssl procps tar unzip debianutils whois zstd \
    iproute2 iputils-tracepath netcat-openbsd \
    vim-tiny nano jq dnsutils tcpdump strace lsof less \
    containerd docker.io \
    && rm -rf /var/lib/apt/lists/*

RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && mkdir -p /etc/sudoers.d \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && chown -R ubuntu:ubuntu /home/ubuntu

COPY --from=go-builder /build/1panel-core /usr/local/bin/1panel-core
COPY --from=go-builder /build/1panel-agent /usr/local/bin/1panel-agent
RUN chmod +x /usr/local/bin/1panel-core /usr/local/bin/1panel-agent \
    && ln -sf /usr/local/bin/1panel-core /usr/bin/1panel \
    && ln -sf /usr/local/bin/1panel-core /usr/bin/1panel-core \
    && ln -sf /usr/local/bin/1panel-agent /usr/bin/1panel-agent

RUN printf '#!/bin/bash\n\
action=$1\n\
target=$2\n\
args=$@\n\
extra_args=("${@:3}")\n\
BASE_DIR=/opt\n\
ORIGINAL_PORT=8888\n\
ORIGINAL_VERSION=v2.0.0\n\
ORIGINAL_ENTRANCE=1panel\n\
ORIGINAL_USERNAME=1panel\n\
ORIGINAL_PASSWORD=1panel\n\
LANGUAGE=zh\n\
PANEL_EDITION=cn\n\
CHANGE_USER_INFO=\n' > /usr/local/bin/1pctl \
    && chmod +x /usr/local/bin/1pctl \
    && ln -sf /usr/local/bin/1pctl /usr/bin/1pctl

RUN mkdir -p /opt/1panel/{conf,db,log,cache,tmp,data,resource,secret,geo} \
    && chown -R root:root /opt/1panel

RUN printf '[Unit]\n\
Description=1Panel Core Service\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
ExecStart=/usr/local/bin/1panel-core\n\
Restart=always\n\
RestartSec=5\n\
LimitNOFILE=1048576\n\
Environment=HOME=/root\n\
WorkingDirectory=/opt/1panel\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/1panel-core.service \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s /etc/systemd/system/1panel-core.service \
       /etc/systemd/system/multi-user.target.wants/1panel-core.service

RUN printf '[Unit]\n\
Description=1Panel Agent Service\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
ExecStart=/usr/local/bin/1panel-agent\n\
Restart=always\n\
RestartSec=5\n\
LimitNOFILE=1048576\n\
Environment=HOME=/root\n\
WorkingDirectory=/opt/1panel\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/1panel-agent.service \
    && ln -s /etc/systemd/system/1panel-agent.service \
       /etc/systemd/system/multi-user.target.wants/1panel-agent.service

RUN rm -rf /tmp/*
