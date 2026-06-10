# =============================================================================
# Stage 1: Build Reasonix Go binary
# =============================================================================
FROM golang:1.25-bookworm AS builder
WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -trimpath -ldflags '-s -w' \
    -o /build/reasonix ./cmd/reasonix

# =============================================================================
# Stage 2: Runtime rootfs (Ubuntu 24.04 + systemd + Reasonix web server)
# =============================================================================
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus sudo \
    ca-certificates curl git \
    bash less openssh-client python3 \
    bind9-utils bzip2 findutils gzip iptables iputils-ping \
    ncurses-base openssl procps tar unzip debianutils whois zstd \
    iproute2 iputils-tracepath netcat-openbsd \
    vim-tiny nano jq dnsutils tcpdump strace lsof \
    && rm -rf /var/lib/apt/lists/*

RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && mkdir -p /etc/sudoers.d \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && chown -R ubuntu:ubuntu /home/ubuntu

COPY --from=builder /build/reasonix /usr/local/bin/reasonix
RUN chmod +x /usr/local/bin/reasonix

RUN mkdir -p /home/ubuntu/.config/reasonix \
    && printf 'default_model = "deepseek"\n\
\n\
[[providers]]\n\
name        = "deepseek"\n\
kind        = "openai"\n\
base_url    = "https://api.deepseek.com"\n\
models      = ["deepseek-v4-flash", "deepseek-v4-pro"]\n\
default     = "deepseek-v4-flash"\n\
api_key_env = "DEEPSEEK_API_KEY"\n\
context_window = 1000000\n\
effort      = "high"\n' > /home/ubuntu/.config/reasonix/config.toml \
    && chown -R ubuntu:ubuntu /home/ubuntu/.config

RUN printf '[Unit]\n\
Description=Reasonix AI Coding Agent (Web Server)\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=ubuntu\n\
Environment=HOME=/home/ubuntu\n\
ExecStart=/usr/local/bin/reasonix serve --addr 0.0.0.0:8787\n\
Restart=always\n\
RestartSec=5\n\
WorkingDirectory=/home/ubuntu\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/reasonix.service \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s /etc/systemd/system/reasonix.service \
       /etc/systemd/system/multi-user.target.wants/reasonix.service

EXPOSE 8787
