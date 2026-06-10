# MaxKB Pro vmsan 镜像构建任务

## 目标

将 MaxKB Pro v2.10.1-lts 离线安装包打包为 vmsan 兼容的 ext4 rootfs 镜像，VM 启动后自动部署 MaxKB Pro（含 PostgreSQL + Redis），用户无需手动操作即可访问 Web UI。

## 离线安装包分析

### 源文件

`docker-images/mkb-pro.tar.gz` (1.3GB)，解压后为 `maxkb-pro-v2.10.1-lts-x86_64-offline-installer/`：

```
├── install.sh                       # 主安装脚本（190行）
├── install.conf                     # 安装配置（端口、数据库密码等）
├── uninstall.sh                     # 卸载脚本
├── mkctl                            # 管理CLI（start/stop/restart/status/reload）
├── docker/
│   ├── bin/                         # 自带 Docker 全套二进制（共 ~251MB）
│   │   ├── docker, dockerd          # Docker Engine
│   │   ├── containerd, containerd-shim-runc-v2, ctr
│   │   ├── runc
│   │   ├── docker-compose           # docker-compose 独立二进制（61MB）
│   │   ├── docker-proxy, docker-init
│   ├── service/
│       └── docker.service           # systemd 服务文件
├── images/
│   └── maxkb-pro.tar.gz             # Docker 镜像（1.2GB，含 maxkb/pgsql/redis）
└── maxkb/
    ├── docker-compose.yml           # 主服务（maxkb容器，端口8080）
    ├── docker-compose-pgsql.yml     # PostgreSQL 服务
    ├── docker-compose-redis.yml     # Redis 服务
    └── templates/
        ├── maxkb.env                # MaxKB 环境变量模板
        ├── pgsql.env                # PostgreSQL 环境变量模板
        └── redis.env                # Redis 环境变量模板
```

### install.sh 核心流程

1. 检查 `/usr/bin/mkctl` 判断是否为升级
2. 读取 `install.conf` 配置
3. 创建 `${MAXKB_BASE}/maxkb/` 目录，复制 docker-compose 文件
4. 用 `envsubst` 从 templates 生成配置文件
5. 安装 mkctl 到 `/usr/local/bin/`
6. **安装 Docker**：复制二进制到 `/usr/bin/`，启用 systemd 服务
7. **安装 docker-compose**：复制到 `/usr/bin/`
8. **加载镜像**：`docker load -i images/maxkb-pro.tar.gz`
9. 执行 `mkctl reload` 启动服务（docker-compose up -d）
10. 等待 HTTP 200 响应确认服务就绪

### 关键配置（install.conf）

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| MAXKB_BASE | /opt | 安装根目录 |
| MAXKB_PORT | 8080 | Web 端口 |
| MAXKB_DOCKER_SUBNET | 172.31.250.192/26 | Docker 网络 |
| MAXKB_EXTERNAL_PGSQL | false | 使用内置 PG |
| MAXKB_EXTERNAL_REDIS | false | 使用内置 Redis |
| PGSQL_PASSWORD | Password123@postgres | PG 密码 |
| REDIS_PASSWORD | Password123@redis | Redis 密码 |
| MAXKB_VERSION | v2.10.1-lts | 镜像版本 |

### 架构约束

- **单镜像多进程**：pgsql / redis / maxkb 全部由同一个 Docker 镜像 `registry.fit2cloud.com/maxkb/maxkb-pro:v2.10.1-lts` 启动，分别用不同 entrypoint（`start-postgres.sh`、`start-redis.sh`、`start-maxkb.sh`）
- **bridge 网络**：三个容器共用 `maxkb-network` bridge 网络，使用自定义子网
- **healthcheck**：pgsql 用 `pg_isready`，redis 用 `redis-cli ping`，maxkb 用 `curl localhost:8080`
- **docker-compose**：使用独立二进制 `docker-compose`（非 plugin），mkctl 中会降级尝试 `docker compose`

---

## 构建方案

### 参考模式：1Panel 预装 Docker 应用模式

采用与 `images/1panel/` 相同的模式：

1. **Dockerfile**：构建 rootfs，安装 systemd + Docker + 基础工具
2. **post-extract.sh**：在宿主机上解压 mkb-pro.tar.gz，将 Docker 镜像 tar 放入 rootfs 缓存目录
3. **Systemd 服务链**：VM 启动后按序执行 Docker → 加载镜像 → 启动 MaxKB

### 文件结构

```
images/maxkb/
├── config.sh                  # 镜像配置
├── Dockerfile                 # rootfs 构建
├── post-extract.sh            # 宿主机后处理（复制文件到 rootfs）
└── install-maxkb.sh           # VM 内首次启动脚本（替代 install.sh 的功能）
```

---

## 已实现的文件

### 文件清单

```
images/maxkb/
├── config.sh              # 镜像配置（无 SOURCE_REPO，空构建上下文）
├── Dockerfile             # ubuntu:24.04 + systemd + Docker + 基础工具
├── post-extract.sh        # 宿主机后处理：解压 mkb-pro，注入 rootfs
└── install-maxkb.sh       # VM 内首次启动：docker load → compose up

.github/workflows/
└── build-maxkb.yml        # CI：下载 mkb-pro → 构建 → Docker 内核 → VM 测试 → Release
```

### config.sh

```bash
SOURCE_REPO=""       # 无需克隆源码
SOURCE_REF=""
IMAGE_SIZE=8192      # 嵌入 1.2GB Docker 镜像 tar
TAG="maxkb-rootfs:latest"
OUTPUT_FILENAME="maxkb-rootfs.ext4"
```

### Dockerfile

- `ubuntu:24.04` + `systemd systemd-sysv dbus sudo`
- `containerd docker.io` (apt 安装 Docker)
- `ca-certificates gettext-base` (HTTPS + envsubst)
- `docker compose` plugin (ADD from GitHub)
- 创建 `ubuntu` 用户，加入 `docker` 组
- **无 COPY 指令** — 构建上下文是空目录，所有内容由 `post-extract.sh` 注入

### post-extract.sh

在宿主机 `build.sh` 构建完 Docker 镜像后执行，将 mkb-pro 离线包内容注入 rootfs：

1. 解压 `docker-images/mkb-pro.tar.gz`
2. 复制 Docker 镜像 tar → `$ROOTFS/opt/cache/maxkb-pro.tar.gz`
3. 复制 docker-compose 文件 → `$ROOTFS/opt/maxkb/`
4. 用 `envsubst` 从 templates 生成配置文件 → `$ROOTFS/opt/maxkb/conf/`
5. 生成 `.env` 文件 → `$ROOTFS/opt/maxkb/.env`
6. 安装 mkctl → `$ROOTFS/usr/local/bin/mkctl`
7. 安装 docker-compose 独立二进制 → `$ROOTFS/usr/bin/docker-compose`
8. 创建 systemd service → `install-maxkb.service` (After=docker, Type=oneshot)

### install-maxkb.sh

VM 内首次启动时由 systemd 调用：

1. 等待 Docker 就绪（最多 120×2s）
2. `docker load -i /opt/cache/maxkb-pro.tar.gz`
3. 删除镜像缓存释放空间
4. `docker-compose -f ... up -d`（3 个 compose 文件）
5. 等待 HTTP 200 确认服务就绪（最多 30×3s）
6. 写入 marker 文件 `/opt/maxkb/.install-done`（幂等）

### CI 工作流 (build-maxkb.yml)

**触发条件**：
- `push` (main，paths: `images/maxkb/**`, `docker-images/mkb-pro.tar.gz`)
- `workflow_dispatch`（可指定 mkb-pro URL 和 image_size）

**步骤**：
1. Checkout
2. 下载 mkb-pro 离线包（如果不在仓库中）
3. 安装 e2fsprogs（重试 3 次）
4. 构建镜像：`./build.sh --image maxkb --source-dir /tmp/maxkb-source --size 8192`
5. 安装 vmsan
6. 下载 Docker 兼容内核：`lu9944/firecracker` Release `vmlinux-6.1.172-docker`
7. VM 测试（timeout 20min, continue-on-error）：
   - `vmsan create --kernel /tmp/vmlinux-6.1-docker --memory 4096`
   - 等待 VM 就绪（36×5s）
   - 验证 systemd 服务、Docker、容器、mkctl
   - 清理 VM
8. 生成文件名：`maxkb-rootfs-v2.10.1-lts-{timestamp}`
9. GitHub Release：上传 `.ext4.gz`，包含使用说明

---

## 风险与注意事项

### 1. 镜像体积

- mkb-pro.tar.gz = 1.3GB
- 内部 maxkb-pro.tar.gz（Docker 镜像）= 1.2GB
- rootfs 预估总大小 = 3-4GB（含 Docker 运行时）
- ext4 镜像压缩后预估 = 1.5-2GB
- **`IMAGE_SIZE` 建议 8192MB 起步**

### 2. Docker 网络兼容性

- MaxKB 使用自定义 bridge 网络 `maxkb-network` + 子网 `172.31.250.192/26`
- 必须使用 Docker 兼容的 Firecracker 内核
- 如果 bridge NAT 有问题，考虑改为 `network_mode: host`（需修改 docker-compose）

### 3. docker-compose 版本

- mkb-pro 自带 `docker-compose` 独立二进制（v1 模式）
- mkctl 会先尝试 `docker-compose`（独立二进制），再降级到 `docker compose`（plugin）
- **两种都安装**以确保兼容

### 4. install.sh 改造

原始 `install.sh` 不适合直接在 VM 内运行：
- 它会检查/安装 Docker（我们已通过 apt 预装）
- 它使用 `service docker start` 而非 `systemctl`
- 它的 `envsubst` 需要环境变量（我们在 post-extract 中预生成配置）

因此用 `install-maxkb.sh` 替代，只保留核心功能：加载镜像 + docker-compose up。

### 5. VM 内存

- MaxKB Pro 容器默认无内存限制
- PostgreSQL 限制 2GB
- Redis 无限制
- **建议 VM 最少 4GB 内存**

### 6. 启动时间

- `docker load` 加载 1.2GB 镜像：约 30-60s
- `docker-compose up -d` 拉起 3 个容器：约 10-20s
- PostgreSQL/Redis healthcheck 通过后 MaxKB 才启动：约 20-30s
- **总启动时间预估：1-2 分钟**

### 7. 持久化数据

- PG 数据：`/opt/maxkb/data/`
- Redis 数据：`/opt/maxkb/data/`
- MaxKB 日志：`/opt/maxkb/logs/`
- MaxKB 插件：`/opt/maxkb/python-packages/`
- 这些目录通过 docker-compose volumes 映射到宿主机（VM 内路径），数据随 ext4 镜像持久化

---

## 验证清单

VM 启动后，依次验证：

```bash
# 1. 基础服务
systemctl is-active docker containerd

# 2. 安装脚本执行
cat /opt/maxkb/.install-done

# 3. Docker 容器
sudo docker ps                           # 应看到 3 个容器
sudo docker ps --format '{{.Names}}'     # maxkb, pgsql, redis

# 4. MaxKB HTTP
curl -sf http://127.0.0.1:8080           # 应返回 200

# 5. mkctl 工具
mkctl status
mkctl version                            # v2.10.1-lts

# 6. 数据库连通性
sudo docker exec pgsql pg_isready         # PG 正常
sudo docker exec redis redis-cli -a 'Password123@redis' ping  # Redis PONG
```
