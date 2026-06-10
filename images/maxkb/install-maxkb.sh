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

echo "[maxkb] Verifying config files..."
for f in "$MAXKB_RUN_BASE/conf/pgsql.env" "$MAXKB_RUN_BASE/conf/redis.env" "$MAXKB_RUN_BASE/conf/maxkb.env"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing $f"
        exit 1
    fi
    EMPTY_COUNT=$(grep -c '=$' "$f" || true)
    if [ "$EMPTY_COUNT" -gt 0 ]; then
        echo "ERROR: $f has empty values:"
        grep '=$' "$f"
        exit 1
    fi
done

echo "[maxkb] Starting services..."
cd "$MAXKB_RUN_BASE"
export COMPOSE_HTTP_TIMEOUT=180
docker-compose -f docker-compose.yml \
    -f docker-compose-pgsql.yml \
    -f docker-compose-redis.yml up -d

echo "[maxkb] Waiting for containers to stabilize..."
for i in $(seq 1 30); do
    sleep 5
    PGSQL_STATUS=$(docker inspect --format='{{.State.Status}}' pgsql 2>/dev/null || echo "missing")
    REDIS_STATUS=$(docker inspect --format='{{.State.Status}}' redis 2>/dev/null || echo "missing")
    MAXKB_STATUS=$(docker inspect --format='{{.State.Status}}' maxkb 2>/dev/null || echo "missing")
    echo "[maxkb] attempt $i: pgsql=$PGSQL_STATUS redis=$REDIS_STATUS maxkb=$MAXKB_STATUS"

    if [ "$PGSQL_STATUS" = "restarting" ] || [ "$REDIS_STATUS" = "restarting" ]; then
        if [ $i -eq 3 ]; then
            echo "[maxkb] Containers are restarting, showing logs..."
            docker logs pgsql 2>&1 | tail -20 || true
            docker logs redis 2>&1 | tail -20 || true
        fi
    fi

    if [ "$PGSQL_STATUS" = "running" ] && [ "$REDIS_STATUS" = "running" ] && [ "$MAXKB_STATUS" = "running" ]; then
        break
    fi
done

echo "[maxkb] Checking HTTP..."
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
echo "[maxkb] Final container status:"
docker ps -a
echo "[maxkb] MaxKB logs:"
docker logs maxkb 2>&1 | tail -20 || true
touch "$MARKER"
