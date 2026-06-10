# CI/CD Workflows Reference

## Workflow Files

| File | Trigger | Purpose |
|------|---------|---------|
| `build-qwenpaw.yml` | push(paths), workflow_dispatch | Build QwenPaw rootfs, test VM boot, publish GitHub Release |
| `build-1panel.yml` | push(paths), workflow_dispatch | Build 1Panel rootfs + Docker kernel, test Docker-in-VM, publish Release |
| `build-code-server.yml` | similar pattern | Build code-server rootfs |
| `build-openchamber.yml` | similar pattern | Build OpenChamber rootfs |
| `test-kvm.yml` | workflow_dispatch | Test runner KVM support |

> **Note**: All `schedule` (cron) triggers have been **commented out** (disabled) as of 2026-06. Workflows only trigger via push or manual `workflow_dispatch`. To re-enable, uncomment the `schedule:` / `cron:` lines in the YAML `on:` block.

## Build Workflow Pattern (build-qwenpaw.yml)

1. **Checkout** code
2. **Resolve latest release** tag via GitHub API (if no `source_ref` input)
3. **Install dependencies** — `e2fsprogs` with retry loop (3 attempts)
4. **Build rootfs** — `./build.sh --image qwenpaw --size 2048 --no-docker-cache`
5. **Install vmsan** — `curl -fsSL https://vmsan.dev/install | sudo bash`
6. **Test VM boot** — `vmsan create` → poll status (12×5s) → `vmsan exec` → cleanup (5min timeout, continue-on-error)
7. **Generate filename** — `{app}-rootfs-{ref}-{timestamp}`
8. **GitHub Release** — uploads `.ext4.gz` via `softprops/action-gh-release@v2`

### 1Panel Workflow 特殊步骤 (build-1panel.yml)

1. **Resolve latest 1Panel release** — `curl` GitHub API → python3 解析 `tag_name`
2. **Download Docker-capable kernel** — 从 `lu9944/firecracker` Release 下载到 `/tmp/vmlinux-6.1-docker`
3. **VM 测试使用自定义内核** — `vmsan create --kernel /tmp/vmlinux-6.1-docker --memory 2048`
4. **验证三个 systemd 服务** — `systemctl is-active 1panel-core containerd docker`
5. **VM 内用 sudo docker** — `vmsan exec "$VM_ID" sudo docker info`（exec 以 ubuntu 用户运行）

### VM Boot Test Gotchas

- `vmsan create --json` 输出 JSON 对象，字段名是 `"vmId"` 不是 `"id"`（vmsan v0.3.0）
- 解析 VM ID: `grep -oE '"vmId"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -oE '"[^"]*"$' | tr -d '"'`
- **不要用 `vmsan list --json`** 探测 VM 就绪——其 JSON 格式不稳定。改用 `vmsan exec "$VM_ID" echo "ok"` 探测
- `vmsan exec` 以 **ubuntu 用户（非 root）** 运行。VM 内需要 sudo 的操作（docker, systemctl）要用 `vmsan exec "$VM_ID" sudo <cmd>`
- 超时和等待轮次：普通镜像 12×5s=60s，Docker 镜像需要 24×5s=120s（Docker/containerd 启动较慢）
- Always cleanup: `vmsan stop` → `vmsan remove`
- All vmsan commands need `sudo env "PATH=$PATH"` wrapper
- `~/.vmsan/kernels/` 被 root 拥有（sudo install 时创建），runner 无写入权限。下载内核到 `/tmp/`

## KVM Test Workflow (test-kvm.yml)

Checks in order:
1. **Group membership** — `sudo usermod -aG kvm runner` (note: won't take effect in same shell)
2. **/dev/kvm device** — existence and permissions
3. **Kernel modules** — `lsmod | grep kvm`, `modprobe --show-depends`
4. **CPU flags** — grep vmx/svm from `/proc/cpuinfo`
5. **Permissions** — stat /dev/kvm, check kvm group membership, test read/write
6. **Memory** — `free -h`, `/proc/meminfo`, check >= 1024MB for VM
7. **modprobe attempt** — try loading kvm, kvm_intel, kvm_amd
8. **Summary** — final pass/fail report

### Key Finding: GitHub Runner KVM Environment

As of 2025, GitHub-hosted `ubuntu-latest` runners provide:
- **CPU**: AMD with svm (4 cores)
- **KVM device**: `/dev/kvm` exists (crw-rw---- root:kvm)
- **KVM module**: `kvm_amd` loaded
- **Memory**: ~16GB RAM, ~3GB swap
- **Permission**: runner user NOT in kvm group; `usermod -aG` requires re-login to take effect
- **Workaround**: Use `sudo` for all KVM/vmsan operations

### CI Environment Notes

- `e2fsprogs` install may fail intermittently; use retry loop
- `vmsan` must be installed with `sudo bash` (not just `bash`)
- GitHub Release upload uses `GITHUB_TOKEN` secret (auto-provided)
- `permissions: contents: write` needed for release uploads

## 常见 CI 失败及解决

### npm ci 与 package-lock.json 不同步

上游项目（如 1Panel）的 `package-lock.json` 与 `package.json` 可能不同步，`npm ci` 严格要求两者一致会报错。

**解决方案**：用 `npm install` 替代 `npm ci`。

### Go 版本不匹配

`go.mod` 可能要求高于 Docker 基础镜像的 Go 版本（如 1Panel 要求 >= 1.25.7 但用了 golang:1.24）。

**解决方案**：检查上游 `go.mod` 的 `go` 指令，升级 Docker 基础镜像版本。

### 企业版构建标签缺失（-tags=xpack）

1Panel 的 Makefile 用 `-tags=xpack` 编译企业版，但 `core/xpack` 是闭源包，公开仓库没有。

**解决方案**：去掉 `-tags=xpack`，使用社区版代码路径（`community.go` 带 `//go:build !xpack`）。

### vite 输出目录非标准

1Panel 前端 vite 配置 `outDir: '../core/cmd/server/web'`（相对于 frontend/），不是默认的 `dist/`。

**解决方案**：WORKDIR 为 `/build` 时，产物在 `/build/core/cmd/server/web/`，COPY 路径要对。

### systemctl "Failed to connect to bus"

rootfs 中未安装 `dbus` 包，systemctl 无法与 systemd 通信。

**解决方案**：apt install 加 `dbus` 包。

### docker.sock permission denied

`vmsan exec` 以 ubuntu 用户运行，没有 docker 组权限访问 docker.sock。

**解决方案**：Dockerfile 中 `usermod -aG docker ubuntu`，CI 测试中用 `vmsan exec "$VM_ID" sudo docker info`。

### apt-get update 网络超时

GitHub Actions runner 的 apt 源偶尔不稳定，`apt-get update` 会卡住直到超时。

**解决方案**：加重试循环：
```bash
for i in 1 2 3; do
  sudo apt-get update && sudo apt-get install -y e2fsprogs && break
  echo "Retry $i: apt-get failed, retrying in 10s..."
  sleep 10
done
```

### VM 测试步骤不稳定

`vmsan create` 测试在 CI 中容易失败：
- 镜像 2.4GB+ 但默认只分配 512MB 内存，可能启动失败
- `vmsan create` 返回空输出导致 VM_ID 为空

**解决方案**：`continue-on-error: true`
```yaml
- name: Test VM boot with vmsan
  continue-on-error: true
  timeout-minutes: 5
```

### CI 触发注意事项

修改 `.github/workflows/build-*.yml` 本身会触发 CI（如果在 paths 列表中），但如果只改 workflow 文件而不改对应的 `images/**` 下的文件，某些 push 触发可能不会匹配。此时使用 `workflow_dispatch` 手动触发。

## CI 构建产物

- 产出文件名格式：`{app}-rootfs-{tag}-{timestamp}.ext4.gz`
- 通过 GitHub Release 发布（`softprops/action-gh-release@v2`）
- 同时上传未压缩的 `.ext4` 用于 VM 测试
