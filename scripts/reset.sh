#!/usr/bin/env bash
# =============================================================================
# reset.sh — Complete teardown (DESTROYS ALL DATA)
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[!] This will DESTROY all Splunk data and volumes."
read -rp "Are you sure? Type 'yes' to confirm: " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "[*] Aborted."
  exit 0
fi

echo "[*] Removing containers, networks, and volumes..."
docker compose down -v

echo "[*] Done. Run scripts/start.sh to rebuild from scratch."
