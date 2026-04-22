# vmsan-image-builder

将 QwenPaw（Python + React AI 助手 Web 应用）打包为 vmsan 兼容的 ext4 rootfs 镜像，使其可以通过 vmsan 以 Firecracker microVM 方式启动，并自动提供 HTTP 服务。

## 前置条件

- Docker（建议安装 Buildx）
- `mkfs.ext4`、`tune2fs`（来自 `e2fsprogs` 包）
- vmsan CLI（安装：`curl -fsSL https://vmsan.dev/install | bash`）
- QwenPaw 源码位于 `../QwenPaw`（或通过 `--qwenpaw-dir` 指定）

## 目录结构

```
vmsan-image-builder/
├── Dockerfile        # 多阶段构建（node:20 编译前端 + ubuntu:24.04 运行时）
├── build.sh          # 一键构建脚本
├── verify.sh         # 离线镜像验证
└── rootfs.ext4       # 产出镜像（构建后生成）
```

## 使用方法

### 1. 构建镜像

```bash
./build.sh
```

自定义参数：

```bash
./build.sh --qwenpaw-dir ../QwenPaw --output ./rootfs.ext4 --size 2048 --no-docker-cache
```

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--qwenpaw-dir` | QwenPaw 源码目录 | `../QwenPaw` |
| `--output` | 输出 ext4 镜像路径 | `./rootfs.ext4` |
| `--size` | 最小镜像大小（MB） | `2048` |
| `--tag` | Docker 镜像标签 | `qwenpaw-rootfs:latest` |
| `--no-docker-cache` | 不使用 Docker 构建缓存 | 关闭 |

### 2. 验证镜像

```bash
./verify.sh ./rootfs.ext4
```

检查项：关键路径、开发工具、systemd 服务、qwenpaw 二进制。

### 3. 环境检查

```bash
sudo env "PATH=$PATH" vmsan doctor
```

所有检查项通过后方可继续。

### 4. 启动虚拟机

```bash
sudo env "PATH=$PATH" vmsan create \
  --rootfs ./rootfs.ext4 \
  --vcpus 2 \
  --memory 1024 \
  --publish-port 8088 \
  --timeout 30m
```

启动成功后，vmsan 会输出 **VM ID**、**Guest IP** 和 **Host IP**。

### 5. 验证 QwenPaw 是否运行

```bash
# 等待约 10 秒启动完成后检查进程
sleep 10
sudo env "PATH=$PATH" vmsan exec <VM_ID> ps aux | grep qwenpaw

# 从宿主机测试 HTTP 访问（使用 vmsan 输出的 Guest IP）
curl -sf http://<GUEST_IP>:8088 -o /dev/null -w '%{http_code}\n'
```

### 6. 虚拟机管理

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

## 镜像内容

### 系统

- **操作系统**：Ubuntu 24.04
- **Init 系统**：systemd（vmsan-agent 依赖）
- **用户**：`ubuntu`，支持无密码 sudo

### QwenPaw

- **版本**：从源码构建（`../QwenPaw`）
- **前端**：预编译的 React 应用（Node.js 20 构建阶段）
- **后端**：Python 3.12 虚拟环境，位于 `/opt/qwenpaw-venv`
- **命令行工具**：`/usr/local/bin/qwenpaw`（符号链接）
- **配置文件**：初始化于 `/home/ubuntu/.qwenpaw/`
- **服务**：systemd 开机自启，监听端口 `8088`

### 开发工具

`curl`、`wget`、`git`、`ping`、`ip`、`ss`、`nc`、`jq`、`dig`、`vim-tiny`、`strace`、`lsof`、`less`、`tcpdump`

### 架构示意

```
+---------------------------+
|        rootfs.ext4        |
|    (ext4, 约 2.1 GB)     |
|                           |
|  /sbin/init (systemd)    |
|  ├── qwenpaw.service     |  → qwenpaw app :8088
|  └── vmsan-agent.service |  → 启动时由 vmsan 自动注入
|                           |
|  /opt/qwenpaw-venv/      |  → Python + QwenPaw
|  /home/ubuntu/.qwenpaw/  |  → 配置和工作区
|  /usr/local/bin/qwenpaw  |  → CLI 符号链接
+---------------------------+
         │
         │  vmsan create --rootfs rootfs.ext4
         ▼
+---------------------------+
|    Firecracker microVM    |
|   vCPU: 2, 内存: 1024MB   |
|   端口: 8088 → 虚拟机      |
+---------------------------+
```

## 常见问题

| 现象 | 诊断命令 | 可能原因 |
|---|---|---|
| 虚拟机立即退出 | 查看内核日志 | init 缺失/损坏，内核不兼容 |
| QwenPaw 未监听 | `vmsan exec <ID> ps aux \| grep qwenpaw` | Python 依赖缺失，配置错误 |
| 虚拟机内无网络 | `vmsan exec <ID> ip addr show eth0` | TAP 设备配置异常 |
| 端口无法访问 | 检查 `--publish-port` 参数和 nftables | 端口映射配置错误 |
| `vmsan doctor` KVM 失败 | `ls -la /dev/kvm` | KVM 未启用 |
