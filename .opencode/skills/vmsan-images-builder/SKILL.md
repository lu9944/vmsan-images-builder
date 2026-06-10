---
name: vmsan-image-builder
description: Build vmsan-compatible ext4 rootfs images from Docker containers. Use when: packaging applications for Firecracker microVMs, creating systemd-based VM images, adding new image types, CI/CD pipeline tasks, Docker-in-Firecracker kernel work.
---

## Core Patterns

**Multi-Image Architecture**: Each image lives in `images/<name>/` with `config.sh` (SOURCE_REPO, SOURCE_REF, IMAGE_SIZE, TAG), `Dockerfile`, and optional `post-extract.sh`. `build.sh --image <name>` discovers and builds from that directory. Adding a new image = create `images/<name>/` + `.github/workflows/build-<name>.yml`.

**Docker Build Context Gotcha**: Dockerfile is at `images/<name>/Dockerfile`, but build context is the application source directory (cloned by `build.sh`). COPY paths in Dockerfile are relative to the source context, not the Dockerfile directory.

**Multi-stage Docker Build**: Typical pattern — Stage 1 builds frontend (node:20-slim), Stage 2 optionally builds backend binaries (golang), Stage 3 is runtime (ubuntu:24.04 + systemd). vmsan-agent requires systemd.

**ext4 Image Size**: `tar_bytes / 1024 / 1024 + 512` MB, minimum 1024MB. `--size` flag sets minimum, not exact size. Docker-in-VM images need 4096MB+.

**Systemd Service Pattern**: Service file at `/etc/systemd/system/<app>.service`, enabled via symlink in `multi-user.target.wants/`. Type=simple, Restart=always, After=network.target. **Must install `dbus` package** — without it `systemctl` fails with "Failed to connect to bus: No such file or directory".

**vmsan API (v0.3.0)**:
- `vmsan create --json` outputs `{"vmId": "vm-xxx", ...}` — field is `"vmId"`, not `"id"`
- `vmsan exec <vmId> <cmd>` runs as **ubuntu user (non-root)** — use `sudo docker` for docker.sock access
- `vmsan create --kernel <path>` specifies custom guest kernel
- Kernel resolution: `--kernel` param > `~/.vmsan/kernels/` (latest vmlinux* by name)
- `~/.vmsan/kernels/` is owned by root (created during `sudo` install) — download kernels to `/tmp/` instead

**GitHub Actions KVM Support**: GitHub-hosted `ubuntu-latest` runners have KVM (AMD svm, kvm_amd, ~16GB RAM). Runner user NOT in kvm group; `sudo usermod -aG kvm runner` has no effect in same shell. Use `sudo` for all KVM/vmsan operations.

**Docker-in-Firecracker**: Official Firecracker kernel has most Docker features (cgroups, overlayfs, bridge, veth, namespaces, seccomp) but **missing**: TUN, DUMMY, MACVLAN, IPVLAN, VXLAN, IPVS, several NETFILTER_XT_* targets. Monolithic kernel (`CONFIG_MODULES=n`). Custom kernel as overlay config on official `microvm-kernel-ci-x86_64-6.1.config`.

## Reference Files

| File | Content | When to load |
|------|---------|--------------|
| `reference/ci-cd-workflows.md` | GitHub Actions workflows: build pipeline, KVM test, VM boot test, CI failures & fixes, vmsan API patterns | Working with CI/CD pipelines, adding new image workflows, debugging Actions |
| `reference/qwenpaw-patching.md` | Active Dockerfile patches for QwenPaw: `_MAX_ZIP_BYTES` sed, python-multipart, env var upload limit, default config | Modifying Dockerfile patches, debugging upload size issues |
| `reference/1panel-build.md` | 1Panel image build: 3-stage Dockerfile, Go+Node build, config from 1pctl script, Docker-in-VM, all gotchas | Building/modifying 1Panel image, adding similar Go+frontend apps |
| `reference/docker-firecracker-kernel.md` | Docker-in-Firecracker kernel requirements, missing config items, custom kernel build process | Enabling Docker in Firecracker VMs, kernel compilation, adding kernel modules |

## Key Workflows

**Build rootfs image locally**
```bash
./build.sh --image <name> [--source-dir ../app] [--output ./rootfs.ext4] [--size 2048] [--no-docker-cache]
```

**Verify image offline** (requires sudo)
```bash
./verify.sh ./rootfs.ext4
```

**Launch VM with vmsan**
```bash
sudo env "PATH=$PATH" vmsan create --rootfs ./rootfs.ext4 --vcpus 2 --memory 1024 --publish-port 8088
# With custom Docker kernel:
sudo env "PATH=$PATH" vmsan create --kernel /tmp/vmlinux-6.1-docker --rootfs ./rootfs.ext4 --memory 2048
```

**Add a new image type**: Create `images/<name>/config.sh` + `images/<name>/Dockerfile` + `.github/workflows/build-<name>.yml`. Follow existing pattern (e.g., `images/1panel/`).

## Dependencies

- Docker
- `mkfs.ext4`, `tune2fs` (e2fsprogs)
- vmsan CLI: `curl -fsSL https://vmsan.dev/install | bash`
- Application source code (cloned from `SOURCE_REPO` in `config.sh`)

## Cleanup on Error

- Uses `trap cleanup EXIT` for guaranteed cleanup
- Removes container and build directories even on failure
- Scripts use `set -euo pipefail` for strict error handling
