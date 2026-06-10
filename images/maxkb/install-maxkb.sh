#!/bin/bash
set -euo pipefail

MARKER="/opt/maxkb/.install-done"
[ -f "$MARKER" ] && exit 0

MAXKB_BASE=/opt
MAXKB_RUN_BASE=$MAXKB_BASE/maxkb
CACHE_DIR=$MAXKB_BASE/cache

echo "[maxkb] Waiting for Docker..."
for i in $(seq 1 120); do
    docker info >/dev/null 2>&1 && break
    sleep 2
done
docker info >/dev/null 2>&1 || { echo "ERROR: docker not ready"; exit 1; }

echo "[maxkb] Loading image..."
docker load -i "$CACHE_DIR/maxkb-pro.tar.gz"

echo "[maxkb] Cleaning image cache..."
rm -f "$CACHE_DIR/maxkb-pro.tar.gz"

echo "[maxkb] Starting services..."
cd "$MAXKB_RUN_BASE"
docker-compose -f docker-compose.yml \
    -f docker-compose-pgsql.yml \
    -f docker-compose-redis.yml up -d

echo "[maxkb] Waiting for HTTP 200..."
for i in $(seq 1 30); do
    sleep 3
    http_code=$(curl -sILw "%{http_code}\n" http://127.0.0.1:8080 -o /dev/null 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ]; then
        echo "[maxkb] Service ready!"
        touch "$MARKER"
        exit 0
    fi
    echo "[maxkb] Waiting... (HTTP $http_code)"
done

echo "[maxkb] WARN: service did not become ready in time"
touch "$MARKER"
