#!/bin/bash
set -euo pipefail

ROOTFS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MKPRO="$REPO_ROOT/docker-images/mkb-pro.tar.gz"
[ -f "$MKPRO" ] || { echo "[post-extract] ERROR: $MKPRO not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[post-extract] Extracting mkb-pro offline installer..."
tar -xzf "$MKPRO" -C "$WORK"
SRC="$WORK"/maxkb-pro-v2.10.1-lts-x86_64-offline-installer

cp "$SCRIPT_DIR/install-maxkb.sh" "$ROOTFS/usr/local/bin/install-maxkb.sh"
chmod +x "$ROOTFS/usr/local/bin/install-maxkb.sh"

echo "[post-extract] Copying Docker image tar to cache..."
mkdir -p "$ROOTFS/opt/cache"
cp "$SRC/images/maxkb-pro.tar.gz" "$ROOTFS/opt/cache/maxkb-pro.tar.gz"
echo "[post-extract] Image cache: $(du -sh "$ROOTFS/opt/cache/maxkb-pro.tar.gz" | cut -f1)"

echo "[post-extract] Copying docker-compose files..."
cp "$SRC/maxkb/docker-compose.yml" "$ROOTFS/opt/maxkb/"
cp "$SRC/maxkb/docker-compose-pgsql.yml" "$ROOTFS/opt/maxkb/"
cp "$SRC/maxkb/docker-compose-redis.yml" "$ROOTFS/opt/maxkb/"

echo "[post-extract] Generating config from templates..."
source "$SRC/install.conf"

mkdir -p "$ROOTFS/opt/maxkb/conf"
envsubst < "$SRC/maxkb/templates/pgsql.env" > "$ROOTFS/opt/maxkb/conf/pgsql.env"
envsubst < "$SRC/maxkb/templates/maxkb.env" > "$ROOTFS/opt/maxkb/conf/maxkb.env"
envsubst < "$SRC/maxkb/templates/redis.env" > "$ROOTFS/opt/maxkb/conf/redis.env"

cat > "$ROOTFS/opt/maxkb/.env" <<EOF
MAXKB_IMAGE_REPOSITORY=$MAXKB_IMAGE_REPOSITORY
MAXKB_IMAGE=$MAXKB_IMAGE
MAXKB_VERSION=$MAXKB_VERSION
MAXKB_BASE=$MAXKB_BASE
MAXKB_PORT=$MAXKB_PORT
MAXKB_DOCKER_SUBNET=$MAXKB_DOCKER_SUBNET
MAXKB_EXTERNAL_PGSQL=$MAXKB_EXTERNAL_PGSQL
MAXKB_EXTERNAL_REDIS=$MAXKB_EXTERNAL_REDIS
PGSQL_HOST=$PGSQL_HOST
PGSQL_PORT=$PGSQL_PORT
PGSQL_DB=$PGSQL_DB
PGSQL_USER=$PGSQL_USER
PGSQL_PASSWORD=$PGSQL_PASSWORD
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
REDIS_DB=$REDIS_DB
REDIS_PASSWORD=$REDIS_PASSWORD
EOF

echo "[post-extract] Installing mkctl..."
sed -i "s#MAXKB_BASE=.*#MAXKB_BASE=$MAXKB_BASE#g" "$SRC/mkctl"
cp "$SRC/mkctl" "$ROOTFS/usr/local/bin/mkctl"
chmod +x "$ROOTFS/usr/local/bin/mkctl"

echo "[post-extract] Installing docker-compose standalone binary..."
cp "$SRC/docker/bin/docker-compose" "$ROOTFS/usr/bin/docker-compose"
chmod +x "$ROOTFS/usr/bin/docker-compose"

echo "[post-extract] Creating systemd service..."
mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants"

cat > "$ROOTFS/etc/systemd/system/install-maxkb.service" <<'SVCEOF'
[Unit]
Description=MaxKB Pro Install & Start
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
TimeoutStartSec=600
RemainAfterExit=yes
ExecStart=/usr/local/bin/install-maxkb.sh

[Install]
WantedBy=multi-user.target
SVCEOF

ln -sf /etc/systemd/system/install-maxkb.service \
    "$ROOTFS/etc/systemd/system/multi-user.target.wants/install-maxkb.service"

echo "[post-extract] MaxKB Pro files installed"
