#!/usr/bin/env bash
# =============================================================================
# verify.sh — Offline verification of a QwenPaw rootfs image
#
# Usage: ./verify.sh [path-to-rootfs.ext4]
#   Default: ./rootfs.ext4
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${1:-$SCRIPT_DIR/rootfs.ext4}"

[ -f "$IMAGE" ] || { echo "[error] Image not found: $IMAGE" >&2; exit 1; }

MNT="$(mktemp -d)"
cleanup() { sudo umount "$MNT" 2>/dev/null || true; rm -rf "$MNT"; }
trap cleanup EXIT

echo "[info] Mounting $IMAGE"
sudo mount -o loop "$IMAGE" "$MNT"

path_exists() {
    if [ -e "$MNT$1" ] || [ -L "$MNT$1" ]; then return 0; fi
    if [ -L "$MNT$1" ]; then
        local target
        target="$(readlink "$MNT$1")"
        [ -e "$MNT$target" ] && return 0
    fi
    return 1
}

echo ""
echo "=== Critical paths ==="
paths=(
    "/etc/systemd/system/qwenpaw.service"
    "/etc/systemd/system/multi-user.target.wants/qwenpaw.service"
    "/home/ubuntu"
    "/home/ubuntu/.qwenpaw/config.json"
    "/etc/sudoers.d/ubuntu"
    "/opt/qwenpaw-venv/bin/qwenpaw"
    "/usr/local/bin/qwenpaw"
    "/usr/bin/systemctl"
)
ok=0; fail=0
for p in "${paths[@]}"; do
    if path_exists "$p"; then
        printf "  OK   %s\n" "$p"; ok=$((ok+1))
    else
        printf "  MISS %s\n" "$p"; fail=$((fail+1))
    fi
done

echo ""
echo "=== Dev tools ==="
tools=(curl git ping ip ss nc jq wget vi strace lsof less dig)
for t in "${tools[@]}"; do
    if sudo chroot "$MNT" which "$t" >/dev/null 2>&1; then
        printf "  OK   %s\n" "$t"; ok=$((ok+1))
    else
        printf "  MISS %s\n" "$t"; fail=$((fail+1))
    fi
done

echo ""
echo "=== qwenpaw version ==="
sudo chroot "$MNT" /opt/qwenpaw-venv/bin/qwenpaw --version 2>&1 || true

echo ""
echo "=== systemd service content ==="
sudo cat "$MNT/etc/systemd/system/qwenpaw.service"

echo ""
echo "=== Image size ==="
du -h "$IMAGE"

echo ""
echo "Result: $ok passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
