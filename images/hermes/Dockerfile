# =============================================================================
# Hermes Agent (NousResearch) vmsan rootfs Dockerfile
#
# Build context is the hermes-agent source tree (set by build.sh).
# Produces an ubuntu:24.04 + systemd rootfs that auto-starts the hermes
# web dashboard on boot (0.0.0.0:8088), matching the qwenpaw vmsan pattern.
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: build the React dashboard (web/) + the Ink TUI bundle (ui-tui/)
# Node 22 is copied from here into the runtime stage as well — the dashboard's
# embedded chat (/api/pty) runs the prebuilt TUI via `node`.
# ---------------------------------------------------------------------------
FROM node:22-bookworm-slim AS web-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates python3 build-essential \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# `file:` workspace deps must install as symlinks (npm 10+ default); set
# explicitly as defense-in-depth — see upstream Dockerfile rationale.
ENV npm_config_install_links=false

# Copy only manifests first for layer caching, plus the hermes-ink workspace
# package referenced via `file:` from ui-tui/package.json.
COPY package.json package-lock.json ./
COPY web/package.json web/package.json
COPY ui-tui/package.json ui-tui/package.json
COPY ui-tui/packages/hermes-ink/ ui-tui/packages/hermes-ink/
RUN npm install --prefer-offline --no-audit

# Now copy the real source and build both frontends.
COPY web/ web/
COPY ui-tui/ ui-tui/
# web build outputs to ../hermes_cli/web_dist (vite outDir); ui-tui to dist/.
RUN cd web && npm run build \
 && cd ../ui-tui && npm run build

# ---------------------------------------------------------------------------
# Stage 2: uv package manager (pinned; binary only, copied into runtime).
# ---------------------------------------------------------------------------
FROM ghcr.io/astral-sh/uv:0.11.6 AS uv-bin

# ---------------------------------------------------------------------------
# Stage 3: runtime rootfs (Ubuntu 24.04 + systemd + Hermes)
# ---------------------------------------------------------------------------
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# System packages: systemd (required by vmsan) + Python build deps + dev tools
# + media/search utilities hermes uses at runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
        systemd systemd-sysv sudo dbus \
        ca-certificates curl wget gnupg git openssh-client \
        python3 python3-venv python3-dev build-essential \
        libssl-dev libffi-dev \
        ffmpeg ripgrep \
        bind9-utils bzip2 findutils gzip xz-utils zstd \
        iptables iputils-ping iputils-tracepath iproute2 \
        netcat-openbsd procps tar unzip debianutils whois \
        ncurses-base openssl less nano vim-tiny jq dnsutils tcpdump strace lsof \
    && rm -rf /var/lib/apt/lists/*

# uv (Python dep installer) + Node 22 LTS (runtime: embedded TUI subprocess).
# Node binary is copied from the bookworm-slim builder; it links against
# glibc 2.36 and runs cleanly on ubuntu 24.04 (glibc 2.39, forward-compatible).
COPY --from=uv-bin /uv /uvx /usr/local/bin/
COPY --from=web-builder /usr/local/bin/node /usr/local/bin/node
COPY --from=web-builder /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Create ubuntu user with passwordless sudo (vmsan exec runs as ubuntu).
RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
 && mkdir -p /etc/sudoers.d \
 && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
 && chmod 440 /etc/sudoers.d/ubuntu \
 && mkdir -p /home/ubuntu/.hermes \
 && chown -R ubuntu:ubuntu /home/ubuntu

# uv config isolation (avoid picking up stray config under sudo -u).
ENV UV_NO_CONFIG=1
ENV UV_PROJECT_ENVIRONMENT=/opt/hermes/.venv
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

WORKDIR /opt/hermes

# ---- Python deps (cached layer: manifests only) ----
# README.md is referenced by pyproject.toml's `readme=` but excluded from the
# build context by the upstream .dockerignore (*.md); touch a placeholder so
# uv's build frontend can stat it during dep resolution.
COPY pyproject.toml uv.lock ./
RUN touch README.md
# Mirror the upstream production dependency set: the curated [all] extra plus
# the messaging gateway and common cloud providers. [matrix] is intentionally
# omitted (it builds python-olm from source and needs libolm-dev); add it back
# with `libolm-dev` if Matrix gateway support is required.
RUN uv sync --frozen --no-install-project \
        --extra all --extra messaging \
        --extra anthropic --extra bedrock --extra azure-identity --extra hindsight

# ---- Source code ----
# .dockerignore excludes node_modules / build outputs; the deps layer above
# survives this COPY. Install the project itself as an editable link (no
# re-resolve, no extra downloads).
COPY . .
RUN uv pip install --no-cache-dir --no-deps -e "."

# ---- Prebuilt frontends (from stage 1) ----
COPY --from=web-builder /app/hermes_cli/web_dist ./hermes_cli/web_dist
COPY --from=web-builder /app/ui-tui/dist ./ui-tui/dist

# Make the hermes CLI available system-wide.
RUN ln -sf /opt/hermes/.venv/bin/hermes /usr/local/bin/hermes \
 && (ln -sf /opt/hermes/.venv/bin/hermes-agent /usr/local/bin/hermes-agent || true)

# Runtime environment for the dashboard service.
ENV HERMES_HOME=/home/ubuntu/.hermes
ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_TUI_DIR=/opt/hermes/ui-tui
ENV HERMES_DISABLE_LAZY_INSTALLS=1
ENV PATH="/opt/hermes/.venv/bin:${PATH}"

# ---- systemd service: auto-start the web dashboard on boot ----
# --insecure is REQUIRED to bind 0.0.0.0 (non-loopback) without the auth gate
# (see hermes_cli/web_server.py start_server allow_public path).
# --skip-build trusts the prebuilt web_dist baked above (HERMES_WEB_DIST).
RUN printf '[Unit]\n\
Description=Hermes Agent Dashboard\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
ExecStart=/opt/hermes/.venv/bin/hermes dashboard --host 0.0.0.0 --port 8088 --no-open --insecure --skip-build\n\
Restart=always\n\
RestartSec=5\n\
Environment=HOME=/home/ubuntu\n\
Environment=HERMES_HOME=/home/ubuntu/.hermes\n\
Environment=HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist\n\
Environment=HERMES_TUI_DIR=/opt/hermes/ui-tui\n\
Environment=HERMES_DISABLE_LAZY_INSTALLS=1\n\
Environment=PATH=/opt/hermes/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n\
WorkingDirectory=/home/ubuntu\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n' > /etc/systemd/system/hermes.service \
 && mkdir -p /etc/systemd/system/multi-user.target.wants \
 && ln -s /etc/systemd/system/hermes.service \
          /etc/systemd/system/multi-user.target.wants/hermes.service

# Keep /opt/hermes read-only for the runtime user (writes go to HERMES_HOME).
RUN chmod -R a+rX /opt/hermes

# Clean up build artifacts to shrink the exported rootfs.
RUN rm -rf /tmp/* /root/.cache /var/cache/* /opt/hermes/.git 2>/dev/null || true
