# QwenPaw Runtime Patching

Dockerfile (`images/qwenpaw/Dockerfile`) 在构建时对 QwenPaw 上游源码进行 patch，包括 sed 修改源码、补装依赖、写入配置文件。

## 当前活跃 Patch（截至 2026-06）

### Patch A: 技能 ZIP 解压后大小限制 200MB → 1GB（第 62-64 行）

```bash
RUN sed -i '/^_MAX_ZIP_BYTES/s/= .*/= 1024 * 1024 * 1024/' \
    src/qwenpaw/agents/skill_system/store.py
```

`_MAX_ZIP_BYTES` 检查 zip **解压后**的总大小（不是压缩包大小）。上游 `store.py:47` 仍是 `200 * 1024 * 1024`。位置：Stage 2，COPY src 之后、pip install 之前。

### Patch B: 补装 python-multipart（第 72 行）

```bash
RUN /opt/qwenpaw-venv/bin/pip install --no-cache-dir python-multipart
```

FastAPI 0.103+ 将 `python-multipart` 从核心依赖移除，但文件上传 (`UploadFile = File(...)`) 需要它。QwenPaw 的 `pyproject.toml` 未声明此依赖。缺少时返回 `400: There was an error parsing the body`。位置：pip install . 之后（必须在 venv 创建后）。

### Patch C: 上传大小限制 — 环境变量替代（第 101 行）

```ini
Environment=QWENPAW_UPLOAD_MAX_SIZE_MB=512
```

写在 systemd service 的 `[Service]` 段中。上游已重构上传限制机制：前端不再有硬编码常量，改为通过 `useUploadLimitStore` 从后端 API `settingsApi.getUploadLimit()` 动态获取；后端读取环境变量 `QWENPAW_UPLOAD_MAX_SIZE_MB`，默认 `None`（无限制）。

### Patch D: 默认语言中文（第 82 行）

```bash
printf '{"language":"zh"}' > /home/ubuntu/.qwenpaw/settings.json
```

### Patch E: 预配置 BITZH vLLM provider + Qwen 3.5 27B 默认模型（第 83-87 行）

直接写入 `~/.qwenpaw.secret/providers/custom/bitzh-vllm.json` 和 `active_model.json`。

## 已删除 Patch 历史

| # | 描述 | 删除原因 | 替代方案 |
|---|------|----------|----------|
| 前端 `MAX_UPLOAD_SIZE_MB` 100→512 | 上游重构为动态 API 获取，默认无限制 | 环境变量 `QWENPAW_UPLOAD_MAX_SIZE_MB` |
| 前端 `SKILL_POOL_ZIP_MAX_MB` 100→512 | 同上 | 同上 |
| 后端 `_MAX_UPLOAD_BYTES` → 512MB | 上游改为 `constant.py` + 环境变量机制 | 同上 |
| 模拟 git 仓库 (`git init && git add -A && git commit`) | vite + tsc build 不需要 git；`git add -A` 导致 node_modules 全部入 git（大量 120000 symlink 输出） | 无需替代 |

## sed Patch 写法最佳实践

**推荐模式**：行首锚定 + 通配替换
```bash
RUN sed -i '/^_MAX_ZIP_BYTES/s/= .*/= 1024 * 1024 * 1024/' file.py
```

**避免精确字符串匹配**：`sed -i 's/200 \* 1024 \* 1024/...'` 上游格式可能不同，且多条 sed 操作同文件会互相干扰。

**Patch 顺序注意**：
- 源码 sed patch 必须在 COPY 之后、pip install 之前
- pip 补装包必须在 venv 创建之后
- 配置文件写入必须在 `qwenpaw init` 之后
