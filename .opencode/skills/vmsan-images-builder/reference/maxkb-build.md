# MaxKB Base Image Build Reference

## 概述

MaxKB 镜像是一个**纯基础 Docker 环境**（Ubuntu 24.04 + systemd + Docker + compose），不嵌入任何应用程序。用户获取 VM 后自行上传 `mkb-pro.tar.gz` 离线安装包手动安装 MaxKB Pro。

## 架构：Base-Only 镜像模式

不同于 1Panel 镜像（嵌入 Docker 镜像 + 预装应用），MaxKB 采用最简模式：

| 对比 | 1Panel | MaxKB |
|------|--------|-------|
| SOURCE_REPO | 上游 GitHub 仓库 | `""` (空) |
| 源码目录 | git clone | `/tmp/maxkb-source` (空目录) |
| Dockerfile | 多阶段编译 Go+Node | 单阶段运行时 |
| post-extract.sh | docker pull/save, 复制脚本 | 空操作 |
| IMAGE_SIZE | 12288MB | 2048MB |
| VM 内存 | 4096MB+ | 2048MB |

### config.sh 关键设置

```bash
SOURCE_REPO=""          # 不需要源码
SOURCE_REF=""
IMAGE_SIZE=2048         # 基础镜像 2GB 足够
TAG="maxkb-rootfs:latest"
OUTPUT_FILENAME="maxkb-rootfs.ext4"
```

**构建命令**：
```bash
./build.sh --image maxkb --source-dir /tmp/maxkb-source --size 2048 --no-docker-cache
```

## Dockerfile 详解

单阶段 `ubuntu:24.04` 运行时：

```dockerfile
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus sudo \
    ca-certificates curl wget \
    iptables iproute2 procps \
    vim-tiny nano jq strace lsof less \
    containerd docker.io tzdata gettext-base \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone
```

**关键包**：
- `gettext-base`：提供 `envsubst` 命令，mkb-pro 的 `install.sh` 用它生成配置文件
- `containerd docker.io`：Docker CE（apt 安装，非 mkb-pro 自带二进制）
- `iptables`：Docker 网络必需

**docker compose 插件**：ubuntu:24.04 默认源没有 `docker-compose-plugin`，用 `ADD` 从 GitHub Releases 下载。

## mkb-pro.tar.gz 离线安装包结构

用户手动上传的离线包内容：

```
maxkb-pro-v2.10.1-lts-x86_64-offline-installer/
├── install.sh          # 主安装脚本
├── install.conf        # 配置变量（密码、端口等）
├── mkctl               # CLI 工具（docker-compose wrapper）
├── docker/             # Docker 二进制（不使用，VM 已有 Docker）
├── maxkb/
│   ├── docker-compose.yml         # MaxKB 主服务
│   ├── docker-compose-pgsql.yml   # PostgreSQL 服务
│   ├── docker-compose-redis.yml   # Redis 服务
│   ├── templates/                 # envsubst 模板文件
│   │   ├── pgsql.env
│   │   ├── redis.env
│   │   └── maxkb.env
│   └── cache/
│       └── maxkb-pro.tar          # Docker 镜像 tar（~1.2GB）
└── local/
    └── python-packages/           # Python 离线包
```

**关键点**：三个容器（pgsql、redis、maxkb）使用**同一个镜像** `registry.fit2cloud.com/maxkb/maxkb-pro:v2.10.1-lts`，只是 entrypoint 不同。

## install.conf 变量映射

```bash
# install.conf 中的变量 → 通过 envsubst 注入到 templates/*.env
MAXKB_IMAGE_REPOSITORY=registry.fit2cloud.com/maxkb
PGSQL_PASSWORD=Password123@postgres    →  templates/pgsql.env: POSTGRES_PASSWORD=${PGSQL_PASSWORD}
REDIS_PASSWORD=Password123@redis       →  templates/redis.env: REDIS_PASSWORD=${REDIS_PASSWORD}
MAXKB_DB_PASSWORD=Password123@postgres →  templates/maxkb.env: MAXKB_DB_PASSWORD=${PGSQL_PASSWORD}
```

## 关键 Gotcha：`set -a` + `envsubst`

**问题**：mkb-pro 的 `install.sh` 用 `envsubst` 从模板生成配置文件。`source install.conf` 加载变量后，变量必须被 `export` 才能被 `envsubst` 读取。原始脚本用 `set -a`（自动 export 所有后续赋值的变量）。

**现象**：如果变量未 export，`envsubst` 会将 `${PGSQL_PASSWORD}` 替换为空字符串，导致：
- PostgreSQL 容器启动失败："Database is uninitialized and superuser password is not specified"
- Redis 容器启动失败："'requirepass' wrong number of arguments"（密码为空）

**修复**：在 `source install.conf` 前加 `set -a`：
```bash
set -a
source "$SRC/install.conf"
set +a
```

## Docker 网络配置

- mkb-pro 创建网络 `maxkb_maxkb-network`
- 子网：`172.31.250.192/26`
- 需要自定义 Docker 内核（标准 Firecracker 内核缺少 VXLAN、IPVS、部分 NETFILTER_XT_* 配置）

## vmsan 中使用

```bash
# 下载 Docker 兼容内核
curl -fSL -o /tmp/vmlinux-6.1-docker \
  "https://github.com/lu9944/firecracker/releases/download/docker-kernel-6.1.172-20260610012612/vmlinux-6.1.172-docker"

# 启动 VM（至少 2GB 内存）
sudo env "PATH=$PATH" vmsan create \
  --kernel /tmp/vmlinux-6.1-docker \
  --rootfs maxkb-base-rootfs.ext4 \
  --memory 2048 \
  --vcpus 2 \
  --publish-port 8080

# VM 启动后手动安装
sudo docker load -i maxkb-pro-v2.10.1-lts-x86_64-offline-installer/maxkb/cache/maxkb-pro.tar
cd maxkb-pro-v2.10.1-lts-x86_64-offline-installer
sudo bash install.sh
```

## 在 1Panel VM 内安装的额外问题

在已有的 1Panel VM 内运行 mkb-pro 的 `install.sh` 需要注意：

| 问题 | 说明 |
|------|------|
| `gettext-base` 缺失 | 1Panel Dockerfile 未安装，需手动 `apt install gettext-base` |
| 端口冲突 | PG 5432、Redis 6379、MaxKB 8080 可能与 1Panel 已有服务冲突 |
| 内存压力 | 6+ 容器共存在 4096MB 内存中可能紧张 |
| Docker 网络子网冲突 | mkb-pro 用 `172.31.250.192/26`，需确认不与 1Panel 网络重叠 |
