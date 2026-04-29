#!/usr/bin/env bash
# =============================================================================
# verify.sh — Day 1 acceptance tests
# =============================================================================
# Validates:
#   1. All 3 containers are healthy
#   2. Each Splunk instance is responsive
#   3. Search Head has both indexers as distributed search peers
#   4. A search dispatched from SH returns results from BOTH indexers
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

PASS="\033[0;32m✓\033[0m"
FAIL="\033[0;31m✗\033[0m"
INFO="\033[0;34mℹ\033[0m"

echo ""
echo "============================================================"
echo "  Day 1 Acceptance Tests — Unified Splunk Architecture"
echo "============================================================"

# ---------------------------------------------------------------------------
# Test 1: Container health
# ---------------------------------------------------------------------------
echo ""
echo "[1/4] Container health..."
for c in core-shd core-idx siteb-idx; do
  status=$(docker inspect --format '{{.State.Health.Status}}' "$c" 2>/dev/null || echo "missing")
  if [[ "$status" == "healthy" ]]; then
    echo -e "  $PASS $c  →  $status"
  else
    echo -e "  $FAIL $c  →  $status"
    echo -e "  $INFO Containers may still be initializing. Wait 60s and retry."
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Test 2: Splunk responsiveness via management API
# ---------------------------------------------------------------------------
echo ""
echo "[2/4] Splunk management API responsive on each instance..."
for port in 8089 8189 8289; do
  if curl -sfk "https://localhost:${port}/services/server/info" -u "admin:${SPLUNK_PASSWORD}" -o /dev/null; then
    echo -e "  $PASS port ${port}  →  responding"
  else
    echo -e "  $FAIL port ${port}  →  not responding"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Test 3: Distributed search peers configured on the SH
# ---------------------------------------------------------------------------
echo ""
echo "[3/4] Search Head distributed search peers..."
peers_xml=$(curl -sk "https://localhost:8089/services/search/distributed/peers" \
  -u "admin:${SPLUNK_PASSWORD}")

for peer in core-idx siteb-idx; do
  if echo "$peers_xml" | grep -q "name=\".*${peer}.*\""; then
    echo -e "  $PASS $peer  →  registered as search peer"
  else
    echo -e "  $FAIL $peer  →  NOT registered"
    echo -e "  $INFO Check: docker exec -it core-shd /opt/splunk/bin/splunk list search-server -auth admin:\$SPLUNK_PASSWORD"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Test 4: Federated search returns results from both indexers
# ---------------------------------------------------------------------------
echo ""
echo "[4/4] Federated search across both indexers..."
search='| rest /services/server/info splunk_server=* | table splunk_server'
sid=$(curl -sk -u "admin:${SPLUNK_PASSWORD}" \
  -d "search=${search}" \
  -d "exec_mode=blocking" \
  -d "output_mode=json" \
  "https://localhost:8089/services/search/jobs" | grep -oE '"sid":"[^"]+"' | cut -d'"' -f4 || true)

if [[ -z "${sid:-}" ]]; then
  echo -e "  $FAIL Could not dispatch search (got no SID)"
  exit 1
fi

results=$(curl -sk -u "admin:${SPLUNK_PASSWORD}" \
  "https://localhost:8089/services/search/jobs/${sid}/results?output_mode=json")

for peer in core-idx siteb-idx; do
  if echo "$results" | grep -q "$peer"; then
    echo -e "  $PASS $peer  →  contributed results"
  else
    echo -e "  $FAIL $peer  →  no results returned"
    exit 1
  fi
done

echo ""
echo "============================================================"
echo -e "  $PASS  All Day 1 acceptance tests passed!"
echo "============================================================"
echo ""
echo "  Single Pane of Glass works: SH dispatched a search"
echo "  to BOTH indexers (Core + Site B) and got results back."
echo ""
echo "  Next: Day 2 — implement sovereignty enforcement and"
echo "        intermediate forwarder buffering for Site A."
echo ""
