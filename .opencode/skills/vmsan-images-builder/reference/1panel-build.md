# 1Panel Image Build Reference

## Architecture

1Panel 由两个 Go 二进制文件组成：
- **`1panel-core`** — Web UI 服务器（内嵌前端资源），监听配置端口
- **`1panel-agent`** — 代理服务

配置通过 `/usr/local/bin/1pctl` shell 脚本加载（不是 YAML/JSON）：
```bash
BASE_DIR=/opt
ORIGINAL_PORT=8888
ORIGINAL_VERSION=v2.0.0
ORIGINAL_ENTRANCE=1panel
ORIGINAL_USERNAME=1panel
ORIGINAL_PASSWORD=1panel
LANGUAGE=zh
```

数据目录：`/opt/1panel/{conf,db,log,cache,tmp,data,resource,secret,geo}`

## 三阶段 Dockerfile 构建

### Stage 1: 前端 (node:20-slim)
```dockerfile
WORKDIR /build
COPY frontend/package.json frontend/package-lock.json ./frontend/
RUN cd frontend && npm install        # 不能用 npm ci（上游 lock 文件不同步）
COPY frontend/ ./frontend/
RUN cd frontend && npm run build:pro  # 生产环境构建
```

### Stage 2: Go 二进制 (golang:1.25-bookworm)
```dockerfile
COPY core/go.mod core/go.sum ./core/
COPY agent/go.mod agent/go.sum ./agent/
RUN cd core && go mod download && cd /build/agent && go mod download
COPY core/ ./core/
COPY agent/ ./agent/
COPY --from=frontend-builder /build/core/cmd/server/web/ ./core/cmd/server/web/
# 注意：不能加 -tags=xpack（企业版闭源代码不在公开仓库）
RUN cd /build/core && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags '-s -w' -o /build/1panel-core ./cmd/server/main.go
RUN cd /build/agent && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags '-s -w' -o /build/1panel-agent ./cmd/server/main.go
```

### Stage 3: 运行时 (ubuntu:24.04)
- 安装 `systemd systemd-sysv dbus sudo` + Docker (`containerd docker.io`)
- 创建 ubuntu 用户并加入 docker 组：`usermod -aG docker ubuntu`
- 两个 systemd service：`1panel-core.service` + `1panel-agent.service`

## 已知 Gotcha 及解决方案

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `npm ci` 报错找不到 cosmiconfig | 上游 package-lock.json 与 package.json 不同步 | 用 `npm install` 替代 `npm ci` |
| Go 编译要求 >= 1.25.7 | 最新版 go.mod 升级了 Go 版本 | `golang:1.25-bookworm`（不是 1.24） |
| `-tags=xpack` 编译失败 | xpack 是企业版闭源包，公开仓库没有 | 去掉 `-tags=xpack`，使用社区版 `community.go` |
| 前端产物不在 `/app/dist` | vite `outDir: '../core/cmd/server/web'` | COPY 路径用 `/build/core/cmd/server/web/` |
| systemctl "Failed to connect to bus" | 缺少 `dbus` 包 | 在 apt install 中加 `dbus` |
| docker.sock permission denied | `vmsan exec` 以 ubuntu 用户运行 | VM 内用 `sudo docker`，Dockerfile 中 `usermod -aG docker ubuntu` |

## config.sh

```bash
SOURCE_REPO="https://github.com/1Panel-dev/1Panel.git"
SOURCE_REF="latest-release"  # CI 中通过 GitHub API 解析为实际 tag
IMAGE_SIZE=4096               # Docker-in-VM 需要更大空间
TAG="1panel-rootfs:latest"
OUTPUT="1panel-rootfs.ext4"
```

## CI Workflow 特殊步骤

1. **Resolve latest release** — 调用 GitHub API 获取 1Panel 最新 release tag
2. **Download Docker-capable kernel** — 从 `lu9944/firecracker` Release 下载自定义内核到 `/tmp/`
3. **VM 测试使用 `--kernel`** — `vmsan create --kernel /tmp/vmlinux-6.1-docker --memory 2048`
4. **检查三个 systemd 服务** — `1panel-core`, `containerd`, `docker` 全部要 active
5. **VM 内 sudo docker** — `vmsan exec "$VM_ID" sudo docker info`

## 关键文件位置

| 文件 | 路径 |
|------|------|
| 配置脚本 | `/usr/local/bin/1pctl` |
| Core 二进制 | `/usr/local/bin/1panel-core` |
| Agent 二进制 | `/usr/local/bin/1panel-agent` |
| 数据目录 | `/opt/1panel/` |
| Systemd 服务 | `/etc/systemd/system/1panel-core.service` |
| Systemd 服务 | `/etc/systemd/system/1panel-agent.service` |
