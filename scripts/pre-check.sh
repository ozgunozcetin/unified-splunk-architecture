#!/usr/bin/env bash
# =============================================================================
# Pre-flight check — run this BEFORE the interview demo
# =============================================================================
# Verifies:
#   1. All 6 containers up (incl. sitea-syslog)
#   2. Both search peers reachable
#   3. Loadgen producing events (http_code=200)
#   4. HF forwarding to Core IDX (Active forwards)
#   5. Recent events flowing into sitea_buffer
#   6. Syslog tier — UF active + rsyslog running
# =============================================================================

set -u

SPLUNK_PWD="${SPLUNK_PASSWORD:-Splunk-Lab-2026!}"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

ALL_OK=1

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
bad()  { echo -e "  ${RED}✗${NC} $1"; ALL_OK=0; }

echo ""
echo -e "${BOLD}Pre-flight check — Unified Splunk Architecture demo${NC}"
echo ""

# 1. Containers
echo -e "${YELLOW}[1/6] Container fleet${NC}"
for c in core-shd core-idx siteb-idx sitea-hf sitea-loadgen sitea-syslog; do
    if docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
        ok "$c is running"
    else
        bad "$c is NOT running"
    fi
done
echo ""

# 2. Search peers
echo -e "${YELLOW}[2/6] Distributed search peers${NC}"
peers=$(docker exec -u splunk core-shd /opt/splunk/bin/splunk list search-server -auth "admin:${SPLUNK_PWD}" 2>/dev/null | grep -c "status as \"Up\"")
if [ "$peers" -ge 2 ]; then
    ok "$peers search peers Up"
else
    bad "Only $peers search peers Up (expected 2)"
fi
echo ""

# 3. Loadgen producing
echo -e "${YELLOW}[3/6] Loadgen producing events${NC}"
recent_200=$(docker logs sitea-loadgen --tail 20 2>/dev/null | grep -c "http_code=200")
if [ "$recent_200" -ge 1 ]; then
    ok "Loadgen recently sent $recent_200 events with http_code=200"
else
    bad "Loadgen not sending successfully — check 'docker logs sitea-loadgen'"
fi
echo ""

# 4. HF forwarding active
echo -e "${YELLOW}[4/6] HF forwarding to Core IDX${NC}"
fwd=$(docker exec -u splunk sitea-hf /opt/splunk/bin/splunk list forward-server -auth "admin:${SPLUNK_PWD}" 2>/dev/null)
if echo "$fwd" | grep -A2 "Active forwards" | grep -q "core-idx:9997"; then
    ok "Active forward to core-idx:9997"
else
    bad "core-idx:9997 NOT in active forwards"
fi
echo ""

# 5. Events flowing
echo -e "${YELLOW}[5/6] Recent events in sitea_buffer (last 60 seconds)${NC}"
recent=$(docker exec -u splunk core-shd /opt/splunk/bin/splunk search 'index=sitea_buffer LOADGEN earliest=-60s | stats count' -auth "admin:${SPLUNK_PWD}" -maxout 0 -preview false 2>/dev/null | tail -1 | awk '{print $1}')
if [ -n "${recent:-}" ] && [ "$recent" -gt 0 ] 2>/dev/null; then
    ok "$recent events arrived in last 60 seconds"
else
    bad "No recent events — pipeline may be stuck"
fi
echo ""

# 6. Syslog tier
echo -e "${YELLOW}[6/6] Syslog tier (rsyslog + UF)${NC}"
# rsyslog process
if docker exec sitea-syslog pgrep rsyslogd > /dev/null 2>&1; then
    ok "rsyslog daemon running"
else
    bad "rsyslog daemon NOT running"
fi

# UF process
uf_status=$(docker exec -u splunk sitea-syslog /opt/splunkforwarder/bin/splunk status 2>/dev/null | grep -c "splunkd is running")
if [ "$uf_status" -ge 1 ]; then
    ok "UF (splunkd) running"
else
    bad "UF NOT running"
fi

# UF forwarding
uf_fwd=$(docker exec -u splunk sitea-syslog /opt/splunkforwarder/bin/splunk list forward-server -auth "admin:${SPLUNK_PWD}" 2>/dev/null)
if echo "$uf_fwd" | grep -A2 "Active forwards" | grep -q "sitea-hf:9997"; then
    ok "UF forwarding to sitea-hf:9997"
else
    bad "UF forward to sitea-hf:9997 NOT active"
fi
echo ""

# Summary
if [ $ALL_OK -eq 1 ]; then
    echo -e "${GREEN}${BOLD}  All checks passed. Ready to run demo.sh${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}${BOLD}  Some checks failed. Investigate before running demo.${NC}"
    echo ""
    exit 1
fi
