FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus sudo \
    ca-certificates curl wget \
    iptables iproute2 procps \
    vim-tiny nano jq strace lsof less \
    containerd docker.io tzdata gettext-base \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

RUN mkdir -p /usr/local/lib/docker/cli-plugins
ADD "https://github.com/docker/compose/releases/download/v2.36.1/docker-compose-linux-x86_64" /usr/local/lib/docker/cli-plugins/docker-compose
RUN chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && mkdir -p /etc/sudoers.d \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && usermod -aG docker ubuntu \
    && chown -R ubuntu:ubuntu /home/ubuntu

RUN mkdir -p /opt/maxkb/data /opt/maxkb/conf /opt/maxkb/logs \
    /opt/maxkb/python-packages /opt/maxkb/local \
    /opt/maxkb/cache

RUN rm -rf /tmp/*
