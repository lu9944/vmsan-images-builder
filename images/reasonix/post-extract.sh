#!/usr/bin/env bash
set -euo pipefail
ROOTFS="$1"

rm -f "$ROOTFS/etc/resolv.conf"
printf 'nameserver 223.5.5.5\nnameserver 10.0.10.10\n' > "$ROOTFS/etc/resolv.conf"
