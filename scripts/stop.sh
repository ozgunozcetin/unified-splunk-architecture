#!/usr/bin/env bash
# =============================================================================
# stop.sh — Stop containers (keeps volumes / data)
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[*] Stopping containers..."
docker compose stop

echo "[*] Containers stopped. Data is preserved in Docker volumes."
echo "[*] To restart:                scripts/start.sh"
echo "[*] To completely wipe data:   scripts/reset.sh"
