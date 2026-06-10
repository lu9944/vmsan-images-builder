#!/bin/bash
set -euo pipefail

ROOTFS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "$SCRIPT_DIR/register-apps.sh" "$ROOTFS/usr/local/bin/register-apps.sh"
chmod +x "$ROOTFS/usr/local/bin/register-apps.sh"

echo "[post-extract] register-apps.sh installed"

CACHE_DIR="$ROOTFS/opt/1panel/cache"
mkdir -p "$CACHE_DIR"

echo "[post-extract] Pulling MySQL 8.0.46 image..."
docker pull mysql:8.0.46
docker save mysql:8.0.46 -o "$CACHE_DIR/mysql-8.0.46.tar"
echo "[post-extract] MySQL image saved ($(du -sh "$CACHE_DIR/mysql-8.0.46.tar" | cut -f1))"

echo "[post-extract] Pulling OpenResty 1.31.1.1-0-noble image..."
docker pull 1panel/openresty:1.31.1.1-0-noble
docker save 1panel/openresty:1.31.1.1-0-noble -o "$CACHE_DIR/openresty-1.31.1.1-0-noble.tar"
echo "[post-extract] OpenResty image saved ($(du -sh "$CACHE_DIR/openresty-1.31.1.1-0-noble.tar" | cut -f1))"

echo "[post-extract] Docker images cached for offline use"
