#!/usr/bin/env bash
# =============================================================================
# start.sh — Bring up the Splunk lab
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "[!] .env not found. Copying from .env.example..."
  cp .env.example .env
  echo "[i] Edit .env if you want to change the default password, then re-run."
fi

echo "[*] Pulling Splunk image (first run can take 5-10 minutes)..."
docker compose pull

echo "[*] Starting containers..."
docker compose up -d

echo ""
echo "[*] Containers starting. Splunk takes ~3 minutes to fully initialize."
echo "[*] Watch progress with:  docker compose logs -f"
echo ""
echo "[*] Once healthy, access:"
echo "      Core SH (SOC view):  http://localhost:8000   (admin / see .env)"
echo "      Core IDX (admin):    http://localhost:8001"
echo "      Site B IDX (admin):  http://localhost:8002"
echo ""
echo "[*] Run scripts/verify.sh after ~3 minutes to validate distributed search."
