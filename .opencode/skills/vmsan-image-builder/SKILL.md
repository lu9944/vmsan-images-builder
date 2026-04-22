---
name: vmsan-image-builder
description: Build vmsan-compatible ext4 rootfs images from Docker containers. Use when: packaging applications for Firecracker microVMs, creating systemd-based VM images.
---

## Core Patterns

**Multi-stage Docker Build**
- Stage 1 (`node:20-slim`): Builds React frontends with `npm ci` + `npm run build`
- Stage 2 (`ubuntu:24.04`): Runtime rootfs with systemd, systemd-sysv required
- Build context: QwenPaw source directory (default `../QwenPaw`), Dockerfile in this project

**ext4 Rootfs Creation Pipeline**
1. `docker build` → `docker create` → `docker export` → extract tar
2. Image size calculation: `tar_bytes / 1024 / 1024 + 512` (min 1024MB, min flag override)
3. `mkfs.ext4 -q -d <rootfs-dir>` creates image directly from directory
4. `tune2fs -m 0` removes root reserved space (critical for space efficiency)

**Systemd Service Pattern**
- Service file: `/etc/systemd/system/<name>.service`
- Enable with symlink: `/etc/systemd/system/multi-user.target.wants/<name>.service`
- `After=network.target` for network-dependent services
- `Type=simple` with `Restart=always` for auto-restart

**User Creation Pattern**
```bash
useradd -m -s /bin/bash ubuntu
mkdir -p /etc/sudoers.d
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu
chmod 440 /etc/sudoers.d/ubuntu
```

## Reference Files
| File | Content | When to load |
|------|---------|--------------|
| `reference/build-workflow.md` | Step-by-step build process, Dockerfile stages, verification | Modifying build pipeline, adding packages |

## Key Workflows

**Build rootfs image**
```bash
./build.sh --qwenpaw-dir ../QwenPaw --output ./rootfs.ext4 --size 2048
```
- Validates deps: docker, mkfs.ext4, tune2fs, tar, stat
- Builds Docker image with multi-stage Dockerfile
- Exports container filesystem, creates ext4 image
- Cleans up temporary containers and build directories

**Verify rootfs offline**
```bash
./verify.sh ./rootfs.ext4
```
- Mounts ext4 image as loop device (requires sudo)
- Checks critical paths, dev tools, systemd services
- Verifies qwenpaw binary version
- Pass/fail count summary

**Launch VM with vmsan**
```bash
sudo env "PATH=$PATH" vmsan create \
  --rootfs ./rootfs.ext4 \
  --vcpus 2 \
  --memory 1024 \
  --publish-port 8088
```
- Returns VM ID, Guest IP, Host IP
- systemd init required (vmsan-agent dependency)
- Service auto-starts on `multi-user.target`

## Gotchas

**Image Size Calculation**
- Formula adds 512MB buffer to tar size (line 89 in build.sh)
- Enforces 1024MB minimum even for smaller roots
- `--size` flag sets minimum, not exact size

**Docker Build Context**
- Dockerfile location: this project directory
- Build context: QwenPaw source directory (line 78: `-f "$DOCKERFILE" "$QWENPAW_DIR"`)
- COPY paths in Dockerfile are relative to context, not Dockerfile

**Cleanup on Error**
- Uses `trap cleanup EXIT` for guaranteed cleanup
- Removes container and build directories even on failure
- Script uses `set -euo pipefail` for strict error handling

**Sensitive Files**
- `.github_key` contains SSH keys, `.ftp` has credentials
- Both excluded via .gitignore
- Never commit these files

**Python Venv Integration**
- Venv at `/opt/qwenpaw-venv/` (not in /home/ubuntu)
- CLI symlinked to `/usr/local/bin/qwenpaw`
- Config initialized as ubuntu user (lines 56-59 in Dockerfile)
