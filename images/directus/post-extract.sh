#!/bin/bash
set -euo pipefail

ROOTFS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[post-extract] Installing directus-start.sh"
cp "$SCRIPT_DIR/directus-start.sh" "$ROOTFS/usr/local/bin/directus-start.sh"
chmod +x "$ROOTFS/usr/local/bin/directus-start.sh"
