# Docker-in-Firecracker 内核参考

## 问题背景

1Panel 核心功能是管理 Docker 容器，但 Firecracker microVM 的官方精简内核缺少 Docker 运行所需的若干网络模块。

## 官方内核已有功能

Firecracker 官方内核配置（`microvm-kernel-ci-x86_64-6.1.config`，3556 行）已包含 Docker 大部分需求：

| 功能 | 内核配置项 | 状态 |
|------|-----------|------|
| cgroups v2 | `CONFIG_CGROUPS=y` | ✅ 已有 |
| overlayfs | `CONFIG_OVERLAY_FS=y` | ✅ 已有 |
| bridge | `CONFIG_BRIDGE=y` | ✅ 已有 |
| veth | `CONFIG_VETH=y` | ✅ 已有 |
| namespaces | user/pid/net/mount/uts/ipc | ✅ 已有 |
| seccomp | `CONFIG_SECCOMP=y` | ✅ 已有 |
| iptables basic | `CONFIG_IP_NF_IPTABLES=y` | ✅ 已有 |
| NAT | `CONFIG_IP_NF_NAT=y` | ✅ 已有 |
| conntrack | `CONFIG_NF_CONNTRACK=y` | ✅ 已有 |

## 缺失的关键配置

| 缺失项 | 内核配置 | 影响 |
|--------|---------|------|
| TUN/TAP | `CONFIG_TUN` | Docker 网络无法创建 TUN 设备 |
| DUMMY | `CONFIG_DUMMY` | 网络桥接辅助功能缺失 |
| MACVLAN | `CONFIG_MACVLAN` | Docker MACVLAN 网络驱动不可用 |
| IPVLAN | `CONFIG_IPVLAN` | Docker IPVLAN 网络驱动不可用 |
| VXLAN | `CONFIG_VXLAN` | overlay 网络不可用 |
| IP Virtual Server | `CONFIG_IP_VS` | 负载均衡不可用 |
| 多个 NETFILTER_XT_* | `NETFILTER_XT_MATCH_*`, `NETFILTER_XT_TARGET_*` | iptables 规则不完整，Docker NAT 不工作 |

## 自定义内核编译方案

**核心思路**：不修改 Firecracker VMM 本身，只改 guest 内核配置。

### 构建流程

1. 基于 Firecracker 官方配置文件创建 `docker.config` 叠加文件
2. 在官方配置基础上增量启用缺失的 Docker 相关配置项
3. 编译为 monolithic 内核（`CONFIG_MODULES=n`，所有功能内建）

### 发布产物

- 仓库：`https://github.com/lu9944/firecracker`
- Tag：`docker-kernel-6.1.172-20260610012612`
- 文件：`vmlinux-6.1.172-docker`（~43MB）
- 同时发布 `.config` 文件供参考

### CI 中使用

```yaml
- name: Download Docker-capable kernel
  run: |
    curl -fSL -o /tmp/vmlinux-6.1-docker \
      "https://github.com/lu9944/firecracker/releases/download/docker-kernel-6.1.172-20260610012612/vmlinux-6.1.172-docker"

- name: Test VM boot
  run: |
    sudo env "PATH=$PATH" vmsan create \
      --kernel /tmp/vmlinux-6.1-docker \
      --rootfs ./rootfs.ext4 \
      --memory 2048 \
      --json
```

**注意**：下载到 `/tmp/` 而非 `~/.vmsan/kernels/`（后者被 root 拥有，runner 用户无写入权限）。

## 验证 Docker 运行

VM 内需验证：
```bash
systemctl is-active 1panel-core containerd docker  # 三个服务都要 active
sudo docker info                                    # 确认 Server 端运行
sudo docker ps                                      # 确认可列出容器
```

`vmsan exec` 以 ubuntu 用户运行，必须加 `sudo` 才能访问 docker.sock。

## 开发文档

完整的二次开发文档在 `/home/ubuntu/github_code/firecracker-task.md`，包含：
- 缺失配置项完整列表
- 内核编译步骤
- 验证方法
