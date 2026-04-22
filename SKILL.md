# vmsan-image-builder

将 QwenPaw（Python + React AI 助手 Web 应用）打包为 vmsan 兼容的 ext4 rootfs 镜像，使其可以通过 vmsan 以 Firecracker microVM 方式启动。

## 项目概览

- **语言**: Bash (构建脚本), Dockerfile (多阶段构建)
- **用途**: 构建 vmsan 兼容的 ext4 rootfs 镜像
- **依赖**: Docker, mkfs.ext4, tune2fs, vmsan CLI, QwenPaw 源码

## 目录结构

```
vmsan-image-builder/
├── SKILL.md           # 本文件 - 项目技能描述
├── Dockerfile         # 多阶段构建（node:20 编译前端 + ubuntu:24.04 运行时）
├── build.sh           # 一键构建脚本
├── verify.sh          # 离线镜像验证
├── README.md          # 详细使用文档
├── .gitignore         # 忽略 ext4/img/log 等文件
├── .github_key        # GitHub SSH 密钥
├── .ftp               # FTP 部署配置
└── .skill/            # 技能参考文件
    └── reference/     # 详细参考文档
```

## 构建流程

1. **Docker 多阶段构建**:
   - Stage 1 (console-builder): `node:20-slim` 构建 QwenPaw React 前端
   - Stage 2 (runtime): `ubuntu:24.04` 安装 systemd、Python、QwenPaw、开发工具

2. **rootfs 导出**: 从 Docker 容器导出文件系统为 tar

3. **ext4 镜像创建**: 使用 `mkfs.ext4 -d` 创建 ext4 镜像，`tune2fs -m 0` 移除保留空间

## 关键命令

```bash
# 构建
./build.sh [--qwenpaw-dir <path>] [--output <path>] [--size <MB>] [--tag <name>] [--no-docker-cache]

# 验证
./verify.sh [path-to-rootfs.ext4]

# 启动 VM
sudo env "PATH=$PATH" vmsan create --rootfs ./rootfs.ext4 --vcpus 2 --memory 1024 --publish-port 8088
```

## 镜像内容

- Ubuntu 24.04 + systemd
- QwenPaw Python venv (`/opt/qwenpaw-venv`)
- QwenPaw CLI (`/usr/local/bin/qwenpaw`)
- systemd 服务 (qwenpaw.service, 监听 :8088)
- 开发工具: curl, wget, git, jq, vim-tiny, strace, lsof 等

## 注意事项

- 构建需要 QwenPaw 源码（默认在 `../QwenPaw`）
- 需要 root 权限执行 mount 操作（verify.sh）
- `.ftp` 和 `.github_key` 包含敏感信息，已在 .gitignore 中
- 输出文件 `rootfs.ext4` 约 2.1 GB
