#!/usr/bin/env bash
# =============================================================================
# build.sh
# Build a vmsan-compatible ext4 rootfs image.
#
# Usage:
#   ./build.sh --image <name> [OPTIONS]
#
# Options:
#   --image <name>          Image name (must have images/<name>/ directory)
#   --source-dir <path>     Override source directory (instead of git clone)
#   --output <path>         Output ext4 image path (default from config)
#   --size <MB>             Minimum image size in MB (default from config)
#   --tag <name>            Docker image tag (default from config)
#   --no-docker-cache       Pass --no-cache to docker build
#   -h / --help             Show this help
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE_NAME=""
SOURCE_DIR_OVERRIDE=""
OUTPUT=""
MIN_SIZE_MB=""
IMAGE_TAG=""
DOCKER_CACHE_FLAG=""

usage() {
    sed -n '2,/^#.*====.*$/p' "$0" | sed 's/^# \?//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --image)         [ $# -ge 2 ] || { echo "--image requires a value" >&2; exit 1; }; IMAGE_NAME="$2"; shift 2 ;;
        --source-dir)    [ $# -ge 2 ] || { echo "--source-dir requires a value" >&2; exit 1; }; SOURCE_DIR_OVERRIDE="$2"; shift 2 ;;
        --output)        [ $# -ge 2 ] || { echo "--output requires a value" >&2; exit 1; }; OUTPUT="$2"; shift 2 ;;
        --size)          [ $# -ge 2 ] || { echo "--size requires a value" >&2; exit 1; }; MIN_SIZE_MB="$2"; shift 2 ;;
        --tag)           [ $# -ge 2 ] || { echo "--tag requires a value" >&2; exit 1; }; IMAGE_TAG="$2"; shift 2 ;;
        --no-docker-cache) DOCKER_CACHE_FLAG="--no-cache"; shift ;;
        -h|--help)       usage ;;
        *)               echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[ -z "$IMAGE_NAME" ] && { echo "[error] --image is required" >&2; exit 1; }

IMAGE_DIR="$SCRIPT_DIR/images/$IMAGE_NAME"
[ -d "$IMAGE_DIR" ] || { echo "[error] Image directory not found: $IMAGE_DIR" >&2; exit 1; }

DOCKERFILE="$IMAGE_DIR/Dockerfile"
[ -f "$DOCKERFILE" ] || { echo "[error] Dockerfile not found: $DOCKERFILE" >&2; exit 1; }

CONFIG_FILE="$IMAGE_DIR/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    _ENV_REPO="${SOURCE_REPO:-}"
    _ENV_REF="${SOURCE_REF:-}"
    source "$CONFIG_FILE"
    [ -n "$_ENV_REPO" ] && SOURCE_REPO="$_ENV_REPO"
    [ -n "$_ENV_REF" ] && SOURCE_REF="$_ENV_REF"
fi

: "${SOURCE_REPO:=}"
: "${SOURCE_REF:=main}"
: "${MIN_SIZE_MB:=${IMAGE_SIZE:-2048}}"
: "${IMAGE_TAG:=${TAG:-$IMAGE_NAME-rootfs:latest}}"
: "${OUTPUT:=$SCRIPT_DIR/${OUTPUT_FILENAME:-$IMAGE_NAME-rootfs.ext4}}"

info()  { printf '[info] %s\n' "$*"; }
error() { printf '[error] %s\n' "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || error "Required command not found: $1"; }

need_cmd docker
need_cmd mkfs.ext4
need_cmd tune2fs
need_cmd tar
need_cmd stat

BUILD_DIR="$(mktemp -d)"
CONTAINER_NAME="${IMAGE_NAME}-export-$$"
CLONE_DIR=""

cleanup() {
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    sudo rm -rf "$BUILD_DIR"
    [ -n "$CLONE_DIR" ] && sudo rm -rf "$CLONE_DIR"
}
trap cleanup EXIT

if [ -n "$SOURCE_DIR_OVERRIDE" ]; then
    SOURCE_DIR="$(cd "$SOURCE_DIR_OVERRIDE" 2>/dev/null && pwd)" || {
        error "Source directory not found: $SOURCE_DIR_OVERRIDE"
    }
elif [ -n "$SOURCE_REPO" ]; then
    CLONE_DIR="$(mktemp -d)"
    info "Cloning source: $SOURCE_REPO @ $SOURCE_REF"
    git clone --depth 1 --branch "$SOURCE_REF" "$SOURCE_REPO" "$CLONE_DIR"
    SOURCE_DIR="$CLONE_DIR"
else
    error "No source specified. Provide --source-dir or set SOURCE_REPO in config.sh"
fi

info "Image          : $IMAGE_NAME"
info "Source         : $SOURCE_DIR"
info "Dockerfile     : $DOCKERFILE"
info "Output         : $OUTPUT"
info "Min image size : ${MIN_SIZE_MB}MB"

info "Building Docker image: $IMAGE_TAG"
docker build $DOCKER_CACHE_FLAG -t "$IMAGE_TAG" -f "$DOCKERFILE" "$SOURCE_DIR"

info "Exporting filesystem from Docker image"
docker create --name "$CONTAINER_NAME" "$IMAGE_TAG" >/dev/null
docker export "$CONTAINER_NAME" -o "$BUILD_DIR/rootfs.tar" >/dev/null

info "Extracting filesystem"
mkdir -p "$BUILD_DIR/rootfs"
sudo tar -xf "$BUILD_DIR/rootfs.tar" -C "$BUILD_DIR/rootfs"

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

COMPRESSED="${OUTPUT}.gz"
info "Compressing: $COMPRESSED"
gzip -k -9 "$OUTPUT"
COMPRESSED_BYTES="$(stat -c %s "$COMPRESSED")"
info "Compressed: $COMPRESSED ($(( COMPRESSED_BYTES / 1024 / 1024 ))MB, $(( COMPRESSED_BYTES * 100 / OUTPUT_BYTES ))% of original)"
