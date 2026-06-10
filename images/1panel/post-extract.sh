#!/bin/bash
set -euo pipefail

ROOTFS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "$SCRIPT_DIR/register-apps.sh" "$ROOTFS/usr/local/bin/register-apps.sh"
chmod +x "$ROOTFS/usr/local/bin/register-apps.sh"

echo "[post-extract] register-apps.sh installed"
