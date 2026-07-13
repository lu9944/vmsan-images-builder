# syntax=docker/dockerfile:1
# =============================================================================
# Stage 1: Frontend (Vite)
# Builds the React frontend that gets embedded into the Go binary via go:embed.
# =============================================================================
FROM node:22-alpine AS frontend
WORKDIR /src/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
COPY internal/web/translation /src/internal/web/translation
RUN npm run build

# =============================================================================
# Stage 2: Go Builder + Xray/geoip downloader
# Compiles the 3x-ui binary (CGO) and fetches Xray-core, mtg-multi, geo data.
# Uses Debian-based (not Alpine) Go image so CGO links against glibc, matching
# the Ubuntu runtime. Alpine's musl libc binary would fail on Ubuntu runtime.
# =============================================================================
FROM golang:1.26 AS builder
WORKDIR /app
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  gcc \
  curl \
  unzip \
  && rm -rf /var/lib/apt/lists/*

COPY . .
COPY --from=frontend /src/internal/web/dist ./internal/web/dist

ENV CGO_ENABLED=1
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE"
RUN go build -ldflags "-w -s" -o build/x-ui main.go
RUN ./DockerInit.sh "${TARGETARCH:-amd64}"

# =============================================================================
# Stage 3: Runtime rootfs (Ubuntu 24.04 + systemd + 3x-ui)
# vmsan requires systemd for service management inside the Firecracker microVM.
# Layout follows the native Linux install (/usr/local/x-ui) so the x-ui
# management script and systemd unit work out of the box.
# =============================================================================
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus sudo \
    ca-certificates tzdata \
    curl wget git socat \
    bind9-utils bzip2 findutils gzip iptables iputils-ping \
    ncurses-base openssl procps tar unzip debianutils whois zstd \
    iproute2 iputils-tracepath netcat-openbsd \
    vim-tiny nano jq dnsutils tcpdump strace lsof less \
    fail2ban cron \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

# Create ubuntu user (vmsan convention for console access)
RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && mkdir -p /etc/sudoers.d \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && chown -R ubuntu:ubuntu /home/ubuntu

# Install 3x-ui to /usr/local/x-ui/ (native Linux layout)
COPY --from=builder /app/build/ /usr/local/x-ui/
COPY --from=builder /app/x-ui.sh /usr/bin/x-ui
COPY --from=builder /app/internal/web/translation /usr/local/x-ui/internal/web/translation
RUN chmod +x /usr/local/x-ui/x-ui /usr/bin/x-ui \
    && find /usr/local/x-ui/bin -type f -exec chmod +x {} +

# Set default panel credentials and port (upstream default: 2053)
RUN /usr/local/x-ui/x-ui setting -username admin -password admin -port 2053 -webBasePath /

# Runtime directories and service env file
RUN mkdir -p /etc/x-ui /var/log/x-ui
COPY <<'EOF' /etc/default/x-ui
XUI_ENABLE_FAIL2BAN=true
XRAY_VMESS_AEAD_FORCED=false
EOF

# ---------------------------------------------------------------------------
# Fail2ban: 3x-ui IP-limit jail (adapted from upstream DockerEntrypoint.sh)
# ---------------------------------------------------------------------------
RUN mkdir -p /etc/fail2ban/jail.d /etc/fail2ban/filter.d /etc/fail2ban/action.d \
    && cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local 2>/dev/null || true \
    && sed -i 's/^\[sshd\]$/&\nenabled = false/' /etc/fail2ban/jail.local 2>/dev/null || true \
    && sed -i 's/^allowipv6.*$/allowipv6 = auto/g' /etc/fail2ban/fail2ban.conf 2>/dev/null || true

COPY <<'EOF' /etc/fail2ban/jail.d/3x-ipl.conf
[3x-ipl]
enabled = true
backend = auto
filter = 3x-ipl
action = 3x-ipl
logpath = /var/log/x-ui/3xipl.log
maxretry = 1
findtime = 32
bantime = 30m
EOF

COPY <<'EOF' /etc/fail2ban/filter.d/3x-ipl.conf
[Definition]
datepattern = ^%%Y/%%m/%%d %%H:%%M:%%S
failregex   = \[LIMIT_IP\]\s*Email\s*=\s*<F-USER>.+</F-USER>\s*\|\|\s*Disconnecting OLD IP\s*=\s*<ADDR>\s*\|\|\s*Timestamp\s*=\s*\d+
ignoreregex =
EOF

COPY <<'EOF' /etc/fail2ban/action.d/3x-ipl.conf
[INCLUDES]
before = iptables-allports.conf

[Definition]
actionstart = <iptables> -N f2b-<name>
              <iptables> -A f2b-<name> -j <returntype>
              <iptables> -I <chain> -j f2b-<name>

actionstop = <iptables> -D <chain> -j f2b-<name>
             <actionflush>
             <iptables> -X f2b-<name>

actioncheck = <iptables> -n -L <chain> | grep -q 'f2b-<name>[ \t]'

actionban = <iptables> -I f2b-<name> 1 -s <ip> -p tcp -m multiport ! --dports <exemptports> -j <blocktype>
            <iptables> -I f2b-<name> 1 -s <ip> -p udp -m multiport ! --dports <exemptports> -j <blocktype>
            echo "$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   BAN   [Email] = <F-USER> [IP] = <ip> banned for <bantime> seconds." >> /var/log/x-ui/3xipl-banned.log

actionunban = <iptables> -D f2b-<name> -s <ip> -p tcp -m multiport ! --dports <exemptports> -j <blocktype>
              <iptables> -D f2b-<name> -s <ip> -p udp -m multiport ! --dports <exemptports> -j <blocktype>
              echo "$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   UNBAN   [Email] = <F-USER> [IP] = <ip> unbanned." >> /var/log/x-ui/3xipl-banned.log

[Init]
name = default
chain = INPUT
exemptports = 22,2053
EOF

# Enable fail2ban + cron systemd services
RUN ln -sf /lib/systemd/system/fail2ban.service \
       /etc/systemd/system/multi-user.target.wants/fail2ban.service \
    && ln -sf /lib/systemd/system/cron.service \
       /etc/systemd/system/multi-user.target.wants/cron.service

# ---------------------------------------------------------------------------
# x-ui systemd service
# ---------------------------------------------------------------------------
RUN printf '[Unit]\n\
Description=3x-ui Panel Service\n\
After=network.target fail2ban.service\n\
Wants=network.target\n\
\n\
[Service]\n\
EnvironmentFile=-/etc/default/x-ui\n\
Environment="XRAY_VMESS_AEAD_FORCED=false"\n\
Environment="XUI_MAIN_FOLDER=/usr/local/x-ui"\n\
Type=simple\n\
WorkingDirectory=/usr/local/x-ui/\n\
ExecStart=/usr/local/x-ui/x-ui\n\
ExecReload=/bin/kill -USR1 $MAINPID\n\
Restart=on-failure\n\
RestartSec=5s\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/x-ui.service \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s /etc/systemd/system/x-ui.service \
       /etc/systemd/system/multi-user.target.wants/x-ui.service

RUN rm -rf /tmp/*
