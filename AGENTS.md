# vmsan-image-builder AGENTS.md

## Core Workflows

**Build rootfs image**
```bash
./build.sh [--qwenpaw-dir ../QwenPaw] [--output ./rootfs.ext4] [--size 2048] [--tag qwenpaw-rootfs:latest]
```

**Verify image offline** (requires sudo)
```bash
./verify.sh ./rootfs.ext4
```

**Launch VM with vmsan**
```bash
sudo env "PATH=$PATH" vmsan create --rootfs ./rootfs.ext4 --vcpus 2 --memory 1024 --publish-port 8088
```

## Critical Architecture

**Docker Build Context Gotcha**
- Dockerfile location: this project directory (`./Dockerfile`)
- Build context: QwenPaw source directory (default `../QwenPaw`)
- `docker build -f Dockerfile ../QwenPaw` (line 78 in build.sh)
- COPY paths in Dockerfile are relative to QwenPaw context, not Dockerfile directory

**Multi-stage Docker Build**
- Stage 1: `node:20-slim` builds React frontend
- Stage 2: `ubuntu:24.04` runtime with systemd (vmsan-agent requires systemd)
- QwenPaw Python venv at `/opt/qwenpaw-venv/` (not `/home/ubuntu`)
- CLI symlinked to `/usr/local/bin/qwenpaw`

**ext4 Image Size Calculation**
- Formula: `tar_bytes / 1024 / 1024 + 512` MB (line 89 in build.sh)
- Minimum enforced: 1024MB even for smaller roots
- `--size` flag sets minimum, not exact size

**Systemd Service Pattern**
- Service file: `/etc/systemd/system/qwenpaw.service`
- Enable via symlink: `/etc/systemd/system/multi-user.target.wants/qwenpaw.service`
- Type=simple, Restart=always, After=network.target

## Dependencies Required

- Docker
- `mkfs.ext4`, `tune2fs` (e2fsprogs)
- vmsan CLI: `curl -fsSL https://vmsan.dev/install | bash`
- QwenPaw source code (default `../QwenPaw`)

## Cleanup on Error

- Uses `trap cleanup EXIT` for guaranteed cleanup
- Removes container and build directories even on failure
- Scripts use `set -euo pipefail` for strict error handling

## Sensitive Files

- `.github_key` contains SSH keys
- `.ftp` has credentials
- Both excluded via .gitignore - never commit

## Verification

**verify.sh checks:**
- Critical paths (systemd service, qwenpaw binary, venv, ubuntu user)
- Dev tools (curl, git, jq, vim-tiny, strace, lsof, etc.)
- qwenpaw version output
- systemd service content
- Image size

Requires sudo for loop device mounting.
