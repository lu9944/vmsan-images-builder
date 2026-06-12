# =============================================================================
# Runtime rootfs (Ubuntu 24.04 + systemd + x-ui-yg)
# =============================================================================
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH

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

RUN ARCH=$(case "${TARGETARCH:-amd64}" in amd64) echo "amd64";; arm64) echo "arm64";; *) echo "amd64";; esac) \
    && curl -L -o /tmp/x-ui-linux-${ARCH}.tar.gz \
       https://github.com/yonggekkk/x-ui-yg/releases/download/xui_yg/x-ui-linux-${ARCH}.tar.gz \
    && cd /usr/local \
    && tar xzf /tmp/x-ui-linux-${ARCH}.tar.gz \
    && rm -f /tmp/x-ui-linux-${ARCH}.tar.gz \
    && cd /usr/local/x-ui \
    && chmod +x x-ui bin/xray-linux-${ARCH}

RUN /usr/local/x-ui/x-ui setting -username admin -password admin -port 54321 -webBasePath /

RUN printf '[Unit]\n\
Description=x-ui-yg Panel Service\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
ExecStart=/usr/local/x-ui/x-ui\n\
Restart=always\n\
RestartSec=5\n\
Environment=HOME=/root\n\
WorkingDirectory=/usr/local/x-ui\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/x-ui.service \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s /etc/systemd/system/x-ui.service \
       /etc/systemd/system/multi-user.target.wants/x-ui.service

RUN rm -rf /tmp/*
