# 构建流程详细参考

## build.sh 参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--qwenpaw-dir` | QwenPaw 源码目录 | `../QwenPaw` |
| `--output` | 输出 ext4 镜像路径 | `./rootfs.ext4` |
| `--size` | 最小镜像大小（MB） | `2048` |
| `--tag` | Docker 镜像标签 | `qwenpaw-rootfs:latest` |
| `--no-docker-cache` | 不使用 Docker 构建缓存 | 关闭 |

## build.sh 执行步骤

1. 解析命令行参数
2. 验证依赖命令：docker, mkfs.ext4, tune2fs, tar, stat
3. 创建临时构建目录
4. `docker build` 构建镜像（Dockerfile 在本项目目录，构建上下文为 QwenPaw 目录）
5. `docker create` 创建临时容器
6. `docker export` 导出容器文件系统为 tar
7. 解压 tar 到 rootfs 目录
8. 根据 tar 大小计算所需镜像大小（tar MB + 512，最小 1024）
9. `mkfs.ext4 -q -d` 创建 ext4 镜像
10. `tune2fs -m 0` 移除 root 保留空间
11. 清理：删除临时容器和构建目录

## Dockerfile 构建阶段

### Stage 1: console-builder (node:20-slim)
- 复制 QwenPaw 前端 package.json/package-lock.json
- `npm ci` 安装依赖
- 复制 console/ 源码
- `npm run build` 构建前端

### Stage 2: runtime (ubuntu:24.04)
- 安装系统包：systemd, python3, pip, venv, 编译工具, 网络工具等
- 创建 ubuntu 用户（无密码 sudo）
- 复制 QwenPaw Python 源码和构建好的前端
- 创建 Python venv 并安装 QwenPaw
- 创建 CLI 符号链接
- 以 ubuntu 用户初始化 QwenPaw 配置
- 创建 systemd service 文件并启用
- 清理构建产物

## verify.sh 检查项

- 关键路径：systemd service, ubuntu 用户, qwenpaw 二进制, venv
- 开发工具：curl, git, ping, ip, ss, nc, jq, wget, vi, strace, lsof, less, dig
- qwenpaw --version 输出
- systemd service 文件内容
- 镜像大小

## 镜像内关键路径

| 路径 | 说明 |
|---|---|
| `/opt/qwenpaw-venv/` | Python 虚拟环境 |
| `/usr/local/bin/qwenpaw` | CLI 符号链接 |
| `/usr/local/bin/copaw` | CLI 符号链接 |
| `/home/ubuntu/.qwenpaw/config.json` | QwenPaw 配置 |
| `/etc/systemd/system/qwenpaw.service` | systemd 服务文件 |
| `/etc/sudoers.d/ubuntu` | sudo 配置 |
