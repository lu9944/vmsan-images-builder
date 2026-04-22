# vmsan-image-builder

将应用打包为 vmsan 兼容的 ext4 rootfs 镜像，通过 vmsan 以 Firecracker microVM 方式启动。支持多镜像构建，每个应用独立目录、独立 CI workflow。

## 前置条件

- Docker
- `mkfs.ext4`、`tune2fs`（来自 `e2fsprogs` 包）
- vmsan CLI（安装：`curl -fsSL https://vmsan.dev/install | bash`）

## 目录结构

```
vmsan-image-builder/
├── build.sh                  # 通用构建脚本（--image <名称> 选择镜像）
├── verify.sh                 # 离线镜像验证
├── images/
│   └── qwenpaw/              # QwenPaw 镜像
│       ├── Dockerfile        # 多阶段构建（node:20 前端 + ubuntu:24.04 运行时）
│       └── config.sh         # 构建配置（源仓库、大小、标签等）
├── .github/workflows/
│   └── build-qwenpaw.yml     # QwenPaw 独立 CI workflow
└── qwenpaw-rootfs.ext4       # 产出镜像（构建后生成，已 gitignore）
```

## 使用方法

### 1. 构建镜像

```bash
# 构建 QwenPaw 镜像（自动从 config.sh 配置的 git 仓库 clone 源码）
./build.sh --image qwenpaw

# 使用本地源码目录
./build.sh --image qwenpaw --source-dir ../QwenPaw
```

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--image` | **（必填）** 镜像名称，对应 `images/<名称>/` | 无 |
| `--source-dir` | 应用源码目录（覆盖 config.sh 中的 git clone） | 自动 clone |
| `--output` | 输出 ext4 镜像路径 | config.sh 中的 `OUTPUT` |
| `--size` | 最小镜像大小（MB） | config.sh 中的 `IMAGE_SIZE` |
| `--tag` | Docker 镜像标签 | config.sh 中的 `TAG` |
| `--no-docker-cache` | 不使用 Docker 构建缓存 | 关闭 |

### 2. 验证镜像

```bash
./verify.sh ./qwenpaw-rootfs.ext4
```

检查项：关键路径、开发工具、systemd 服务、qwenpaw 二进制。

### 3. 启动虚拟机

```bash
sudo env "PATH=$PATH" vmsan create \
  --rootfs ./qwenpaw-rootfs.ext4 \
  --vcpus 2 \
  --memory 1024 \
  --publish-port 8088 \
  --timeout 30m
```

启动成功后，vmsan 会输出 **VM ID**、**Guest IP** 和 **Host IP**。

### 4. 虚拟机管理

```bash
# 查看所有虚拟机
sudo env "PATH=$PATH" vmsan list

# 连接到虚拟机 Shell（交互式）
sudo env "PATH=$PATH" vmsan connect <VM_ID>

# 停止
sudo env "PATH=$PATH" vmsan stop <VM_ID>

# 删除
sudo env "PATH=$PATH" vmsan remove <VM_ID>
```

## 添加新镜像

按以下 3 步即可添加一个新的 rootfs 镜像构建配置。

### 第 1 步：创建镜像目录

在 `images/` 下新建以镜像名称命名的目录，放入 `Dockerfile` 和 `config.sh`：

```
images/
└── myapp/              # 新镜像名称
    ├── Dockerfile      # 应用的多阶段构建
    └── config.sh       # 构建配置
```

`config.sh` 模板：

```bash
#!/usr/bin/env bash
SOURCE_REPO="https://github.com/org/myapp.git"   # 应用源码仓库（公开仓库直接填 URL）
SOURCE_REF="main"                                  # 分支 / tag / commit
IMAGE_SIZE=2048                                    # 默认镜像大小 MB
TAG="myapp-rootfs:latest"                          # Docker 镜像标签
FTP_SUBDIR="myapp"                                 # FTP 上传子目录
```

| 变量 | 必填 | 说明 |
|---|---|---|
| `SOURCE_REPO` | 是（或使用 `--source-dir`） | 应用源码 git 仓库地址 |
| `SOURCE_REF` | 否 | Git ref，默认 `main` |
| `IMAGE_SIZE` | 否 | 最小镜像大小 MB，默认 `2048` |
| `TAG` | 否 | Docker 镜像标签，默认 `<名称>-rootfs:latest` |
| `FTP_SUBDIR` | 否 | FTP 上传目标子目录，默认镜像名称 |

### 第 2 步：创建 CI workflow

复制已有 workflow 并修改对应字段：

```bash
cp .github/workflows/build-qwenpaw.yml .github/workflows/build-myapp.yml
```

需要修改的内容：

| 位置 | 改为 |
|---|---|
| `name:` | `Build myapp rootfs` |
| `paths:` 触发路径 | `images/myapp/**` |
| `--image` 参数 | `--image myapp` |
| `source_ref` 描述 | 对应的 git ref 说明 |
| FTP 上传目录 | 与 `config.sh` 中 `FTP_SUBDIR` 一致 |

### 第 3 步：本地测试

```bash
./build.sh --image myapp
```

构建成功后可上传到仓库，push 到 main 分支即可触发 CI。

## GitHub Actions CI

每个镜像拥有独立的 workflow，互不影响：

- **自动触发**：push 到 `main` 且对应 `images/<名称>/` 目录有变更
- **手动触发**：workflow_dispatch，可指定源码 ref 和镜像大小
- **产物上传**：构建完成后自动上传到 FTP，文件名含时间戳（如 `qwenpaw-rootfs-20260422-153000.ext4`）

需要在仓库 **Settings → Secrets and variables → Actions** 中配置：

| Secret | 说明 |
|---|---|
| `FTP_HOST` | FTP 服务器地址 |
| `FTP_PORT` | FTP 端口 |
| `FTP_USER` | FTP 用户名 |
| `FTP_PWD` | FTP 密码 |
