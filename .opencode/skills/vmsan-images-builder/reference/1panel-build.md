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
- 安装 `systemd systemd-sysv dbus sudo ca-certificates tzdata sqlite3` + Docker (`containerd docker.io`)
- **docker compose 插件**：用 `ADD` 指令从 GitHub Releases 下载到 `/usr/local/lib/docker/cli-plugins/`
- 创建 ubuntu 用户并加入 docker 组：`usermod -aG docker ubuntu`
- 设置时区：`ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime` + `echo "Asia/Shanghai" > /etc/timezone`
- 四个 systemd service：`1panel-core`、`1panel-agent`、`preinstall-containers`、`register-apps`

## 预装应用架构 (MySQL + OpenResty)

### 三阶段启动流程

VM 启动时按顺序执行：

1. **containerd + docker** 启动
2. **preinstall-containers.service** (After=docker, Before=1panel-core, Type=oneshot):
   - 等待 Docker 就绪（最多 120s）
   - 创建 `1panel-network` Docker 网络
   - `docker load` 从本地缓存加载 MySQL 和 OpenResty 镜像
   - `docker compose up -d` 启动两个容器
   - 删除 tar 缓存文件释放磁盘空间
   - 写入 marker 文件 `/opt/1panel/.preinstall-containers-done`
3. **1panel-core.service + 1panel-agent.service** 启动
   - 1Panel 将应用商店同步到 SQLite 数据库（`apps` + `app_details` 表）
4. **register-apps.service** (After=1panel-core, Type=oneshot):
   - 等待数据库和应用同步完成
   - 向 `app_installs` 表插入 MySQL 和 OpenResty 安装记录
   - 向 `databases` 表插入 MySQL 数据库记录
   - 写入 marker 文件 `/opt/1panel/.register-apps-done`

### Docker 镜像嵌入 rootfs（post-extract.sh）

`post-extract.sh` 在宿主机上（build.sh 的 Docker 构建后）执行：
```bash
docker pull mysql:8.0.46
docker save mysql:8.0.46 -o "$ROOTFS/opt/1panel/cache/mysql-8.0.46.tar"

docker pull 1panel/openresty:1.31.1.1-0-noble
docker save 1panel/openresty:1.31.1.1-0-noble -o "$ROOTFS/opt/1panel/cache/openresty-1.31.1.1-0-noble.tar"
```

同时将 `register-apps.sh` 复制到 rootfs（避免 Dockerfile 内复杂脚本的引号问题）：
```bash
cp "$SCRIPT_DIR/register-apps.sh" "$ROOTFS/usr/local/bin/register-apps.sh"
```

### 应用商店资源下载

从 `1Panel-dev/appstore` GitHub 仓库下载 docker-compose.yml、配置文件等到 `/opt/1panel/resource/apps/remote/`。

MySQL 的 docker-compose.yml 从官方商店复制后，需要用 `sed` 去掉 `/etc/timezone` 和 `/etc/localtime` 的 bind mount 行，并插入 `TZ: Asia/Shanghai` 环境变量。

OpenResty 的 docker-compose.yml 是在 Dockerfile 中内嵌生成的（不包含 build 段，直接用预构建镜像）。

### 预装默认设置

| 应用 | 容器名 | 端口 | 凭据 |
|------|--------|------|------|
| MySQL 8.0.46 | `1Panel-mysql-ppre` | 3306 | root / `mysql123456` |
| OpenResty 1.31.1.1-0-noble | `1Panel-openresty-opre` | 80/443 (host network) | N/A |

### register-apps.sh 数据库注册

脚本操作 1Panel 的 SQLite 数据库 `/opt/1panel/db/agent.db`：
1. 等待 `apps` 表中 mysql 和 openresty 记录出现（1Panel 同步应用商店后写入）
2. 查询 `app_details` 获取对应版本的 detail_id
3. 向 `app_installs` 插入安装记录（包含 docker-compose 内容、env 参数）
4. MySQL 还需要向 `databases` 表插入数据库连接信息

所有 SQL 插入都用 marker 文件保证幂等性。

## config.sh

```bash
SOURCE_REPO="https://github.com/1Panel-dev/1Panel.git"
SOURCE_REF="latest-release"  # CI 中通过 GitHub API 解析为实际 tag
IMAGE_SIZE=12288             # 嵌入 Docker 镜像 tar 需要更大空间
TAG="1panel-rootfs:latest"
OUTPUT="1panel-rootfs.ext4"
```

## 关键文件位置

| 文件 | 路径 |
|------|------|
| 配置脚本 | `/usr/local/bin/1pctl` |
| Core 二进制 | `/usr/local/bin/1panel-core` |
| Agent 二进制 | `/usr/local/bin/1panel-agent` |
| 数据目录 | `/opt/1panel/` |
| Docker 镜像缓存 | `/opt/1panel/cache/` (启动后自动删除) |
| Systemd 服务 (core) | `/etc/systemd/system/1panel-core.service` |
| Systemd 服务 (agent) | `/etc/systemd/system/1panel-agent.service` |
| Systemd 服务 (预装容器) | `/etc/systemd/system/preinstall-containers.service` |
| Systemd 服务 (注册应用) | `/etc/systemd/system/register-apps.service` |
| 预装容器脚本 | `/usr/local/bin/preinstall-containers.sh` |
| 注册应用脚本 | `/usr/local/bin/register-apps.sh` |

## 已知 Gotcha 及解决方案

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `npm ci` 报错找不到 cosmiconfig | 上游 package-lock.json 与 package.json 不同步 | 用 `npm install` 替代 `npm ci` |
| Go 编译要求 >= 1.25.7 | 最新版 go.mod 升级了 Go 版本 | `golang:1.25-bookworm`（不是 1.24） |
| `-tags=xpack` 编译失败 | xpack 是企业版闭源包，公开仓库没有 | 去掉 `-tags=xpack`，使用社区版 `community.go` |
| 前端产物不在 `/app/dist` | vite `outDir: '../core/cmd/server/web'` | COPY 路径用 `/build/core/cmd/server/web/` |
| systemctl "Failed to connect to bus" | 缺少 `dbus` 包 | 在 apt install 中加 `dbus` |
| docker.sock permission denied | `vmsan exec` 以 ubuntu 用户运行 | VM 内用 `sudo docker`，Dockerfile 中 `usermod -aG docker ubuntu` |
| curl HTTPS exit code 77 | `ubuntu:24.04` 基础镜像缺少 `ca-certificates` | apt install 加 `ca-certificates`，放在第一个 apt 层 |
| docker-compose-plugin 不可用 | ubuntu:24.04 默认源没有这个包 | 用 `ADD` 指令从 GitHub Releases 下载二进制 |
| `mkdir -p path/{a,b,c}` 静默失败 | Docker RUN 用 `/bin/sh` 不支持 bash brace expansion | 展开为独立的 `mkdir -p path/a path/b path/c` |
| MySQL 容器 bind mount `/etc/localtime` 失败 | Docker-in-Firecracker overlay 不支持 bind mount 文件 | 用 `TZ` 环境变量替代，`sed` 删除 docker-compose 中的 mount 行 |
| Dockerfile 内复杂脚本引号问题 | `printf` 内嵌 SQL、变量、引号极易出错 | 脚本放单独文件，通过 `post-extract.sh` 复制进 rootfs |
