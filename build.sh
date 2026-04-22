#!/usr/bin/env bash
# =============================================================================
# build-qwenpaw-rootfs.sh
# Build a vmsan-compatible ext4 rootfs image containing QwenPaw.
#
# Usage:
#   ./build-qwenpaw-rootfs.sh [OPTIONS]
#
# Options:
#   --qwenpaw-dir <path>    QwenPaw source directory (default: ../QwenPaw)
#   --output <path>         Output ext4 image path (default: ./rootfs.ext4)
#   --size <MB>             Minimum image size in MB (default: 2048)
#   --tag <name>            Docker image tag (default: qwenpaw-rootfs:latest)
#   --no-docker-cache       Pass --no-cache to docker build
#   -h / --help             Show this help
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
QWENPAW_DIR="$SCRIPT_DIR/../QwenPaw"
OUTPUT="$SCRIPT_DIR/rootfs.ext4"
MIN_SIZE_MB=2048
IMAGE_TAG="qwenpaw-rootfs:latest"
DOCKER_CACHE_FLAG=""

usage() {
    sed -n '2,/^#.*====.*$/p' "$0" | sed 's/^# \?//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --qwenpaw-dir)  [ $# -ge 2 ] || { echo "--qwenpaw-dir requires a value" >&2; exit 1; }; QWENPAW_DIR="$2"; shift 2 ;;
        --output)       [ $# -ge 2 ] || { echo "--output requires a value" >&2; exit 1; }; OUTPUT="$2"; shift 2 ;;
        --size)         [ $# -ge 2 ] || { echo "--size requires a value" >&2; exit 1; }; MIN_SIZE_MB="$2"; shift 2 ;;
        --tag)          [ $# -ge 2 ] || { echo "--tag requires a value" >&2; exit 1; }; IMAGE_TAG="$2"; shift 2 ;;
        --no-docker-cache) DOCKER_CACHE_FLAG="--no-cache"; shift ;;
        -h|--help)      usage ;;
        *)              echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

DOCKERFILE="$SCRIPT_DIR/Dockerfile"
QWENPAW_DIR="$(cd "$QWENPAW_DIR" 2>/dev/null && pwd)" || {
    echo "[error] QwenPaw directory not found: $QWENPAW_DIR" >&2; exit 1
}

info()  { printf '[info] %s\n' "$*"; }
error() { printf '[error] %s\n' "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || error "Required command not found: $1"; }

need_cmd docker
need_cmd mkfs.ext4
need_cmd tune2fs
need_cmd tar
need_cmd stat

[ -f "$DOCKERFILE" ] || error "Dockerfile not found: $DOCKERFILE"

BUILD_DIR="$(mktemp -d)"
CONTAINER_NAME="qwenpaw-export-$$"

cleanup() {
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

info "QwenPaw source : $QWENPAW_DIR"
info "Dockerfile      : $DOCKERFILE"
info "Output          : $OUTPUT"
info "Min image size  : ${MIN_SIZE_MB}MB"

info "Building Docker image: $IMAGE_TAG"
docker build $DOCKER_CACHE_FLAG -t "$IMAGE_TAG" -f "$DOCKERFILE" "$QWENPAW_DIR"

info "Exporting filesystem from Docker image"
docker create --name "$CONTAINER_NAME" "$IMAGE_TAG" >/dev/null
docker export "$CONTAINER_NAME" -o "$BUILD_DIR/rootfs.tar" >/dev/null

info "Extracting filesystem"
mkdir -p "$BUILD_DIR/rootfs"
tar -xf "$BUILD_DIR/rootfs.tar" -C "$BUILD_DIR/rootfs"

TAR_BYTES="$(stat -c %s "$BUILD_DIR/rootfs.tar")"
CALC_MB=$(( TAR_BYTES / 1024 / 1024 + 512 ))
[ "$CALC_MB" -lt 1024 ] && CALC_MB=1024
IMAGE_SIZE_MB="$MIN_SIZE_MB"
[ "$CALC_MB" -gt "$IMAGE_SIZE_MB" ] && IMAGE_SIZE_MB="$CALC_MB"

info "Creating ext4 image (${IMAGE_SIZE_MB}MB): $OUTPUT"
rm -f "$OUTPUT"
mkfs.ext4 -q -d "$BUILD_DIR/rootfs" "$OUTPUT" "${IMAGE_SIZE_MB}M"
tune2fs -m 0 "$OUTPUT" >/dev/null 2>&1

OUTPUT_BYTES="$(stat -c %s "$OUTPUT")"
info "Done: $OUTPUT ($(( OUTPUT_BYTES / 1024 / 1024 ))MB)"
