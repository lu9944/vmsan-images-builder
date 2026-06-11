# =============================================================================
# Stage 1: Build default frontend (Bun)
# =============================================================================
FROM oven/bun:1 AS frontend-builder

WORKDIR /build
COPY ./VERSION /build/VERSION
COPY ./web/default/package.json ./web/default/bun.lock ./web/default/
RUN cd web/default && bun install --frozen-lockfile
COPY ./web/default ./web/default
RUN cd web/default && DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat /build/VERSION) bun run build

# =============================================================================
# Stage 2: Build classic frontend (Bun)
# =============================================================================
FROM oven/bun:1 AS frontend-builder-classic

WORKDIR /build
COPY ./VERSION /build/VERSION
COPY ./web/classic/package.json ./web/classic/bun.lock ./web/classic/
RUN cd web/classic && bun install --frozen-lockfile
COPY ./web/classic ./web/classic
RUN cd web/classic && VITE_REACT_APP_VERSION=$(cat /build/VERSION) bun run build

# =============================================================================
# Stage 3: Build Go backend
# =============================================================================
FROM golang:1.26.1-alpine AS go-builder
ENV GO111MODULE=on CGO_ENABLED=0
ARG TARGETOS
ARG TARGETARCH
ENV GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64}
ENV GOEXPERIMENT=greenteagc

WORKDIR /build

ADD go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=frontend-builder /build/web/default/dist ./web/default/dist
COPY --from=frontend-builder-classic /build/web/classic/dist ./web/classic/dist
RUN go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api

# =============================================================================
# Stage 4: Runtime rootfs (Ubuntu 24.04 + systemd + new-api)
# =============================================================================
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

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

RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && mkdir -p /etc/sudoers.d \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && chown -R ubuntu:ubuntu /home/ubuntu

COPY --from=go-builder /build/new-api /usr/local/bin/new-api
RUN chmod +x /usr/local/bin/new-api

RUN mkdir -p /data /var/log/new-api \
    && chown -R ubuntu:ubuntu /data /var/log/new-api

RUN printf '[Unit]\n\
Description=New API Service\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=ubuntu\n\
ExecStart=/usr/local/bin/new-api --port 3000 --log-dir /var/log/new-api\n\
Restart=always\n\
RestartSec=5\n\
Environment=HOME=/home/ubuntu\n\
WorkingDirectory=/data\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/new-api.service \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s /etc/systemd/system/new-api.service \
       /etc/systemd/system/multi-user.target.wants/new-api.service

EXPOSE 3000

RUN rm -rf /tmp/*
