# =============================================================================
# Stage 1: Download code-server .deb from GitHub releases
# =============================================================================
FROM alpine:3 AS downloader
RUN apk add --no-cache curl
RUN VERSION=$(curl -fsSLI -o /dev/null -w "%{url_effective}" \
      https://github.com/coder/code-server/releases/latest \
      | sed 's|.*/v||') \
    && echo "Downloading code-server ${VERSION}" \
    && curl -fSL -o /tmp/code-server.deb \
       "https://github.com/coder/code-server/releases/download/v${VERSION}/code-server_${VERSION}_amd64.deb"

# =============================================================================
# Stage 2: Runtime rootfs (Ubuntu 24.04 + systemd + code-server)
# =============================================================================
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus sudo \
    curl wget git git-lfs \
    openssh-client ca-certificates \
    bind9-utils bzip2 findutils gzip iptables iputils-ping \
    ncurses-base openssl procps tar unzip debianutils whois zstd \
    iproute2 iputils-tracepath netcat-openbsd \
    vim-tiny nano jq dnsutils tcpdump strace lsof less \
    locales man-db \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i "s/# en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen \
    && locale-gen
ENV LANG=en_US.UTF-8

RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && mkdir -p /etc/sudoers.d \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && chown -R ubuntu:ubuntu /home/ubuntu

COPY --from=downloader /tmp/code-server.deb /tmp/code-server.deb
RUN dpkg -i /tmp/code-server.deb && rm -f /tmp/code-server.deb

USER ubuntu
ENV HOME=/home/ubuntu
RUN mkdir -p /home/ubuntu/.config/code-server \
    && printf 'bind-addr: 0.0.0.0:8080\nauth: none\npassword: \ncert: false\n' \
       > /home/ubuntu/.config/code-server/config.yaml \
    && mkdir -p /home/ubuntu/project \
    && chown -R ubuntu:ubuntu /home/ubuntu
USER root

RUN printf '[Unit]\n\
Description=code-server - VS Code in the browser\n\
After=network.target\n\
\n\
[Service]\n\
Type=exec\n\
User=ubuntu\n\
Environment=HOME=/home/ubuntu\n\
ExecStart=/usr/bin/code-server --disable-telemetry\n\
Restart=always\n\
RestartSec=5\n\
WorkingDirectory=/home/ubuntu/project\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/code-server.service \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s /etc/systemd/system/code-server.service \
       /etc/systemd/system/multi-user.target.wants/code-server.service

RUN rm -rf /tmp/*
