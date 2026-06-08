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

RUN git init && git config user.email "build@ci" && git config user.name "CI" && git add -A && git commit -m "build" --allow-empty
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
    libglib2.0-0 libnss3 libnspr4 libatk1.0-0t64 libatk-bridge2.0-0t64 \
    libcups2t64 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2t64 \
    libxshmfence1 libdbus-1-3 libatspi2.0-0t64 libx11-xcb1 libxfixes3 \
    && rm -rf /var/lib/apt/lists/*

# Install Rust toolchain (with Chinese mirrors)
ENV RUSTUP_HOME=/opt/rust
ENV CARGO_HOME=/opt/rust/cargo
ENV RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static
ENV RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable \
    && printf '[source.crates-io]\nreplace-with = "rsproxy"\n\n[source.rsproxy]\nregistry = "https://rsproxy.cn/crates.io-index"\n\n[registries.rsproxy]\nindex = "https://rsproxy.cn/crates.io-index"\n\n[net]\ngit-fetch-with-cli = true\n' > /opt/rust/cargo/config.toml \
    && chmod -R 755 /opt/rust
ENV PATH="/opt/rust/cargo/bin:${PATH}"

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

# Patch: raise skill zip uncompressed size limit from 200 MB to 1 GB
RUN sed -i '/^_MAX_ZIP_BYTES/s/= .*/= 1024 * 1024 * 1024/' \
    src/qwenpaw/agents/skill_system/store.py

# Install QwenPaw in a virtual environment
RUN python3 -m venv /opt/qwenpaw-venv \
    && /opt/qwenpaw-venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/qwenpaw-venv/bin/pip install --no-cache-dir .

# Patch: FastAPI 0.103+ no longer bundles python-multipart (required for file uploads)
RUN /opt/qwenpaw-venv/bin/pip install --no-cache-dir python-multipart

# Make CLI available system-wide
RUN ln -sf /opt/qwenpaw-venv/bin/qwenpaw /usr/local/bin/qwenpaw \
    && ln -sf /opt/qwenpaw-venv/bin/copaw /usr/local/bin/copaw

# Initialize QwenPaw config as ubuntu user
USER ubuntu
ENV HOME=/home/ubuntu
RUN /usr/local/bin/qwenpaw init --defaults --accept-security \
    && printf '{"language":"zh"}' > /home/ubuntu/.qwenpaw/settings.json \
    && mkdir -p /home/ubuntu/.qwenpaw.secret/providers/custom \
    && printf '{"id":"bitzh-vllm","name":"BITZH vLLM","base_url":"https://dify-beta.bitzh.edu.cn/v1","api_key":"","chat_model":"OpenAIChatModel","models":[],"extra_models":[{"id":"qwen3.5-27b","name":"Qwen 3.5 27B"}],"api_key_prefix":"","is_local":false,"freeze_url":false,"require_api_key":false,"is_custom":true,"support_model_discovery":false,"support_connection_check":false,"generate_kwargs":{},"meta":{}}' \
       > /home/ubuntu/.qwenpaw.secret/providers/custom/bitzh-vllm.json \
    && printf '{"provider_id":"bitzh-vllm","model":"qwen3.5-27b"}' \
       > /home/ubuntu/.qwenpaw.secret/providers/active_model.json
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
Environment=QWENPAW_UPLOAD_MAX_SIZE_MB=512\n\
WorkingDirectory=/home/ubuntu\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/qwenpaw.service \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s /etc/systemd/system/qwenpaw.service \
       /etc/systemd/system/multi-user.target.wants/qwenpaw.service

# Clean up build artifacts
RUN rm -rf /build /tmp/*
