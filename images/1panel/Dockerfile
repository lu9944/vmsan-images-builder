# =============================================================================
# Stage 1: Build 1Panel frontend (Node.js)
# =============================================================================
FROM node:20-slim AS frontend-builder
WORKDIR /build
ENV NODE_OPTIONS=--max-old-space-size=8192
COPY frontend/package.json frontend/package-lock.json ./frontend/
RUN cd frontend && npm install
COPY frontend/ ./frontend/
RUN cd frontend && npm run build:pro

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
COPY --from=frontend-builder /build/core/cmd/server/web/ ./core/cmd/server/web/

RUN cd /build/core \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
       -trimpath -ldflags '-s -w' \
       -o /build/1panel-core ./cmd/server/main.go

RUN cd /build/agent \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
       -trimpath -ldflags '-s -w' \
       -o /build/1panel-agent ./cmd/server/main.go

# =============================================================================
# Stage 3: Runtime rootfs (Ubuntu 24.04 + systemd + 1Panel + pre-installed apps)
# =============================================================================
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG APPSTORE_BRANCH=dev

RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus sudo \
    ca-certificates curl wget git \
    bind9-utils bzip2 findutils gzip iptables iputils-ping \
    ncurses-base openssl procps tar unzip debianutils whois zstd \
    iproute2 iputils-tracepath netcat-openbsd \
    vim-tiny nano jq dnsutils tcpdump strace lsof less \
    containerd docker.io sqlite3 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/lib/docker/cli-plugins
ADD "https://github.com/docker/compose/releases/download/v2.36.1/docker-compose-linux-x86_64" /usr/local/lib/docker/cli-plugins/docker-compose
RUN chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && mkdir -p /etc/sudoers.d \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && usermod -aG docker ubuntu \
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
    && mkdir -p /opt/1panel/resource/apps/remote \
    && mkdir -p /opt/1panel/resource/icon \
    && mkdir -p /opt/1panel/apps \
    && chown -R root:root /opt/1panel

# ---------------------------------------------------------------------------
# Download app store resources from 1Panel-dev/appstore (dev branch)
# mysql 8.0.46 + openresty 1.31.1.1-0-noble
# ---------------------------------------------------------------------------
RUN set -x \
    && A="https://raw.githubusercontent.com/1Panel-dev/appstore/${APPSTORE_BRANCH}/apps" \
    && mkdir -p /opt/1panel/resource/apps/remote/mysql/8.0.46/conf \
    && curl -sfL "$A/mysql/8.0.46/docker-compose.yml" \
         -o /opt/1panel/resource/apps/remote/mysql/8.0.46/docker-compose.yml \
    && curl -sfL "$A/mysql/8.0.46/data.yml" \
         -o /opt/1panel/resource/apps/remote/mysql/8.0.46/data.yml \
    && curl -sfL "$A/mysql/8.0.46/conf/my.cnf" \
         -o /opt/1panel/resource/apps/remote/mysql/8.0.46/conf/my.cnf \
    && mkdir -p /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/conf/default \
    && mkdir -p /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/conf/ssl \
    && mkdir -p /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/scripts \
    && mkdir -p /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/root \
    && mkdir -p /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/1pwaf/data/conf \
    && curl -sfL "$A/openresty/1.31.1.1-0-noble/docker-compose.yml" \
         -o /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/docker-compose.yml \
    && curl -sfL "$A/openresty/1.31.1.1-0-noble/data.yml" \
         -o /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/data.yml \
    && curl -sfL "$A/openresty/1.31.1.1-0-noble/.env" \
         -o /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/.env \
    && curl -sfL "$A/openresty/1.31.1.1-0-noble/conf/nginx.conf" \
         -o /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/conf/nginx.conf \
    && curl -sfL "$A/openresty/1.31.1.1-0-noble/conf/fastcgi_params" \
         -o /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/conf/fastcgi_params \
    && curl -sfL "$A/openresty/1.31.1.1-0-noble/conf/fastcgi-php.conf" \
         -o /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/conf/fastcgi-php.conf \
    && curl -sfL "$A/openresty/1.31.1.1-0-noble/conf/mime.types" \
         -o /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/conf/mime.types \
    && curl -sfL "$A/openresty/1.31.1.1-0-noble/conf/default/00.default.conf" \
         -o /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/conf/default/00.default.conf \
    && curl -sfL "$A/openresty/1.31.1.1-0-noble/conf/default/default.conf" \
         -o /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/conf/default/default.conf \
    && curl -sfL "$A/openresty/1.31.1.1-0-noble/conf/ssl/root_ssl.conf" \
         -o /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/conf/ssl/root_ssl.conf \
    && curl -sfL "$A/openresty/1.31.1.1-0-noble/scripts/init.sh" \
         -o /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/scripts/init.sh \
    && chmod +x /opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/scripts/init.sh \
    && for f in index.html 404.html; do \
         curl -sfL "$A/openresty/1.31.1.1-0-noble/root/$f" \
           -o "/opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble/root/$f" 2>/dev/null || true; \
       done

# ---------------------------------------------------------------------------
# Create MySQL install directory (pre-installed)
# ---------------------------------------------------------------------------
RUN mkdir -p /opt/1panel/apps/mysql/mysql/{conf,data,log} \
    && cp /opt/1panel/resource/apps/remote/mysql/8.0.46/docker-compose.yml \
          /opt/1panel/apps/mysql/mysql/docker-compose.yml \
    && cp /opt/1panel/resource/apps/remote/mysql/8.0.46/conf/my.cnf \
          /opt/1panel/apps/mysql/mysql/conf/my.cnf \
    && printf 'CONTAINER_NAME=1Panel-mysql-ppre\nPANEL_DB_ROOT_PASSWORD=mysql123456\nPANEL_APP_PORT_HTTP=3306\n' \
       > /opt/1panel/apps/mysql/mysql/.env

# ---------------------------------------------------------------------------
# Create OpenResty install directory (pre-installed)
# Uses pre-built image from Docker Hub (no local build needed)
# ---------------------------------------------------------------------------
RUN set -x \
    && R=/opt/1panel/resource/apps/remote/openresty/1.31.1.1-0-noble \
    && I=/opt/1panel/apps/openresty/openresty \
    && mkdir -p "$I"/{conf/{default,ssl},log,root,1pwaf/data/conf} \
    && cp "$R/conf/nginx.conf"       "$I/conf/" \
    && cp "$R/conf/fastcgi_params"   "$I/conf/" \
    && cp "$R/conf/fastcgi-php.conf" "$I/conf/" \
    && cp "$R/conf/mime.types"       "$I/conf/" \
    && cp "$R/conf/default/"*.conf   "$I/conf/default/" \
    && (cp "$R/conf/ssl/"*.conf "$I/conf/ssl/" 2>/dev/null || true) \
    && (cp -r "$R/root/"* "$I/root/" 2>/dev/null || true) \
    && touch "$I/1pwaf/data/conf/waf.conf" \
    && mkdir -p /opt/1panel/www/{conf.d,stream.d}

# OpenResty docker-compose.yml (without build section — uses pre-built image)
RUN printf 'services:\n\
  openresty:\n\
    image: 1panel/openresty:1.31.1.1-0-noble\n\
    container_name: ${CONTAINER_NAME}\n\
    restart: always\n\
    network_mode: host\n\
    volumes:\n\
      - ./conf/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf\n\
      - ./conf/fastcgi_params:/usr/local/openresty/nginx/conf/fastcgi_params\n\
      - ./conf/fastcgi-php.conf:/usr/local/openresty/nginx/conf/fastcgi-php.conf\n\
      - ./conf/mime.types:/usr/local/openresty/nginx/conf/mime.types\n\
      - ./conf/default:/usr/local/openresty/nginx/conf/default/\n\
      - ./conf/ssl:/usr/local/openresty/nginx/conf/ssl/\n\
      - ./log:/var/log/nginx\n\
      - ./root:/usr/share/nginx/html\n\
      - /etc/localtime:/etc/localtime\n\
      - ./1pwaf/data:/usr/local/openresty/1pwaf/data\n\
      - ${WEBSITE_DIR}:/www\n\
      - ${WEBSITE_DIR}/conf.d:/usr/local/openresty/nginx/conf/conf.d/\n\
      - ${WEBSITE_DIR}/stream.d:/usr/local/openresty/nginx/conf/stream.d/\n\
    labels:\n\
      createdBy: "Apps"\n' > /opt/1panel/apps/openresty/openresty/docker-compose.yml

RUN printf 'CONTAINER_NAME=1Panel-openresty-opre\n\
PANEL_APP_PORT_HTTP=80\n\
PANEL_APP_PORT_HTTPS=443\n\
WEBSITE_DIR=/opt/1panel/www\n\
RESTY_CONFIG_OPTIONS_MORE=\n\
RESTY_ADD_PACKAGE_BUILDDEPS=\n\
CONTAINER_PACKAGE_URL=\n' > /opt/1panel/apps/openresty/openresty/.env

# ---------------------------------------------------------------------------
# Preinstall script: creates docker network, starts app containers
# Runs After=docker.service Before=1panel-core.service
# ---------------------------------------------------------------------------
RUN printf '#!/bin/bash\n\
set -euo pipefail\n\
MARKER="/opt/1panel/.preinstall-containers-done"\n\
[ -f "$MARKER" ] && exit 0\n\
echo "=== preinstall: waiting for docker ===" >&2\n\
for i in $(seq 1 60); do\n\
    docker info >/dev/null 2>&1 && break\n\
    sleep 2\n\
done\n\
docker info >/dev/null 2>&1 || { echo "ERROR: docker not ready" >&2; exit 1; }\n\
echo "=== preinstall: creating 1panel-network ===" >&2\n\
docker network inspect 1panel-network >/dev/null 2>&1 || docker network create 1panel-network\n\
echo "=== preinstall: starting mysql ===" >&2\n\
cd /opt/1panel/apps/mysql/mysql\n\
docker compose up -d 2>&1 || echo "WARN: mysql compose up failed" >&2\n\
echo "=== preinstall: starting openresty ===" >&2\n\
cd /opt/1panel/apps/openresty/openresty\n\
docker compose up -d 2>&1 || echo "WARN: openresty compose up failed" >&2\n\
echo "=== preinstall: waiting for containers ===" >&2\n\
sleep 15\n\
docker ps 2>&1 || true\n\
touch "$MARKER"\n\
echo "=== preinstall: done ===" >&2\n' > /usr/local/bin/preinstall-containers.sh \
    && chmod +x /usr/local/bin/preinstall-containers.sh

# ---------------------------------------------------------------------------
# register-apps.sh is installed via post-extract.sh (to avoid Dockerfile quoting issues)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Systemd services
# ---------------------------------------------------------------------------
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

RUN printf '[Unit]\n\
Description=Pre-install App Containers (MySQL, OpenResty)\n\
After=docker.service\n\
Before=1panel-core.service\n\
Requires=docker.service\n\
\n\
[Service]\n\
Type=oneshot\n\
TimeoutStartSec=600\n\
RemainAfterExit=yes\n\
ExecStart=/usr/local/bin/preinstall-containers.sh\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/preinstall-containers.service \
    && ln -s /etc/systemd/system/preinstall-containers.service \
       /etc/systemd/system/multi-user.target.wants/preinstall-containers.service

RUN printf '[Unit]\n\
Description=Register Pre-installed Apps in 1Panel Database\n\
After=1panel-core.service\n\
Requires=1panel-core.service\n\
\n\
[Service]\n\
Type=oneshot\n\
TimeoutStartSec=300\n\
RemainAfterExit=yes\n\
ExecStart=/usr/local/bin/register-apps.sh\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/register-apps.service \
    && ln -s /etc/systemd/system/register-apps.service \
       /etc/systemd/system/multi-user.target.wants/register-apps.service

RUN rm -rf /tmp/*
