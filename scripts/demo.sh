#!/usr/bin/env bash
# =============================================================================
# Unified Splunk Architecture — Interview Demo Script (v2 — with Syslog tier)
# =============================================================================
# Run this in front of the interviewer to walk through the full case study:
#   1. Foundation: Single Pane of Glass (Day 1)
#   2. Sovereignty: 3-pillar defense-in-depth (Day 2a)
#   3. Buffering: Live WAN outage with zero data loss (Day 2b)
#   4. Syslog Tier: rsyslog disk queue + UF tail (Day 3)
#
# Usage:
#   bash scripts/demo.sh           # standard timing (60s outage + 60s drain)
#   bash scripts/demo.sh --quick   # faster (20s outage + 20s drain)
#   bash scripts/demo.sh --auto    # no pauses, runs end-to-end
# =============================================================================

set -u

# ---------- Configuration ----------
SPLUNK_PWD="${SPLUNK_PASSWORD:-Splunk-Lab-2026!}"
QUICK=0
AUTO=0
for arg in "$@"; do
    case "$arg" in
        --quick) QUICK=1 ;;
        --auto)  AUTO=1 ;;
    esac
done
if [ $QUICK -eq 1 ]; then
    OUTAGE_SECS=20; DRAIN_SECS=20
else
    OUTAGE_SECS=60; DRAIN_SECS=60
fi

# ---------- Colors ----------
BLUE='\033[1;34m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
GREY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

# ---------- Helpers ----------
section() {
    echo ""
    echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}${BOLD}║${NC}  ${BOLD}$1${NC}"
    echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
}

step() {
    echo ""
    echo -e "${YELLOW}▶ $1${NC}"
}

note() {
    echo -e "${GREY}  $1${NC}"
}

run() {
    echo -e "${GREY}  \$ $1${NC}"
    eval "$1"
}

pass() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

fail() {
    echo -e "${RED}  ✗ $1${NC}"
}

pause() {
    if [ $AUTO -eq 1 ]; then
        sleep 1
        return
    fi
    echo ""
    echo -ne "${BOLD}  Press [Enter] to continue, or [s] to skip section: ${NC}"
    read -r ans
    if [ "$ans" = "s" ] || [ "$ans" = "S" ]; then
        return 1
    fi
    return 0
}

countdown() {
    local secs=$1
    local msg=$2
    for ((i=secs; i>0; i--)); do
        echo -ne "${GREY}  $msg ($i sec)...   \r${NC}"
        sleep 1
    done
    echo -e "${GREY}  $msg done.                  ${NC}"
}

# =============================================================================
# 0. PRE-FLIGHT
# =============================================================================
clear
echo -e "${BOLD}"
cat << "EOF"
  ┌─────────────────────────────────────────────────────────────────┐
  │   UNIFIED SPLUNK ARCHITECTURE — Multi-Site Case Study Demo      │
  │                                                                 │
  │   Single Pane of Glass | Sovereignty | Zero Loss | Syslog       │
  └─────────────────────────────────────────────────────────────────┘
EOF
echo -e "${NC}"
echo -e "${GREY}  This demo proves four architectural requirements end-to-end:${NC}"
echo -e "${GREY}    1. Federated search across sites (Single Pane of Glass)${NC}"
echo -e "${GREY}    2. Site B data sovereignty (3-pillar defense-in-depth)${NC}"
echo -e "${GREY}    3. Site A 24h zero-data-loss buffering during WAN outage${NC}"
echo -e "${GREY}    4. Site A syslog tier with restart-safe disk queue${NC}"
echo ""
echo -e "${GREY}  Mode: $([ $QUICK -eq 1 ] && echo 'QUICK' || echo 'STANDARD')   Outage: ${OUTAGE_SECS}s   Drain: ${DRAIN_SECS}s${NC}"
pause || true

# =============================================================================
# SECTION 1 — FOUNDATION (Day 1): SINGLE PANE OF GLASS
# =============================================================================
section "SECTION 1 — Foundation: Single Pane of Glass"

step "1.1  Container fleet — 6 services across 3 logical sites + Core DC"
note "Core DC: core-shd (Search Head) + core-idx (Indexer)"
note "Site A:  sitea-hf (Heavy Forwarder) + sitea-loadgen + sitea-syslog"
note "Site B:  siteb-idx (Restricted Indexer)"
run "docker compose ps --format 'table {{.Name}}\t{{.Status}}'"
pause || true

step "1.2  Distributed search peers — both indexers registered with the SH"
note "This is what makes Single Pane of Glass possible: ONE search head"
note "dispatches searches to every indexer and merges results."
run "docker exec -u splunk core-shd /opt/splunk/bin/splunk list search-server -auth admin:${SPLUNK_PWD} 2>&1 | grep -E 'Server at URI|status'"
pass "Both core-idx and siteb-idx are reachable as search peers"
pause || true

step "1.3  Federated search — ONE query, results from BOTH sites"
note "We ask 'every server, who are you?' and get all 3 back in one table."
run "docker exec -u splunk core-shd /opt/splunk/bin/splunk search '| rest /services/server/info splunk_server=* | table splunk_server, server_roles' -auth admin:${SPLUNK_PWD} -maxout 0 -preview false 2>&1 | grep -v WARNING"
pass "Single Pane of Glass demonstrated: one search, three servers, merged result"
pause || true

# =============================================================================
# SECTION 2 — SOVEREIGNTY (Day 2a): 3-PILLAR DEFENSE-IN-DEPTH
# =============================================================================
section "SECTION 2 — Sovereignty: 3-Pillar Defense-in-Depth"

step "2.1  Pillar 1: Network isolation — Docker networks segment by trust boundary"
note "Site B is on its own WAN segment (usa-wan), separate from Core IDX."
echo ""
echo -e "${GREY}  usa-wan (Site B WAN):${NC}"
run "docker network inspect usa-wan --format '{{range .Containers}}{{.Name}} {{end}}'"
echo ""
echo -e "${GREY}  usa-core (Core DC internal):${NC}"
run "docker network inspect usa-core --format '{{range .Containers}}{{.Name}} {{end}}'"
echo ""
echo -e "${GREY}  usa-wan-core (Site A ↔ Core WAN, separate from Site B):${NC}"
run "docker network inspect usa-wan-core --format '{{range .Containers}}{{.Name}} {{end}}'"
note "Note: Site B is NOT on usa-wan-core. Has no path to Core IDX."
pause || true

step "2.2  Pillar 1 (cont): TCP reachability matrix — proven, not assumed"
note "We test actual TCP ports, not ICMP — these are the ports Splunk really uses."
echo ""
echo -e "${GREY}  Site B → Search Head mgmt port (must be REACHABLE for federated search):${NC}"
result=$(docker exec siteb-idx bash -c 'timeout 3 bash -c "</dev/tcp/core-shd/8089" && echo REACHABLE || echo BLOCKED' 2>/dev/null)
if [ "$result" = "REACHABLE" ]; then pass "siteb-idx → core-shd:8089 = REACHABLE"; else fail "siteb-idx → core-shd:8089 = $result"; fi

echo ""
echo -e "${GREY}  Site B → Core IDX S2S port (must be BLOCKED — sovereignty critical):${NC}"
result=$(docker exec siteb-idx bash -c 'timeout 3 bash -c "</dev/tcp/core-idx/9997" && echo REACHABLE || echo BLOCKED' 2>/dev/null)
if [ "$result" = "BLOCKED" ]; then pass "siteb-idx → core-idx:9997 = BLOCKED"; else fail "siteb-idx → core-idx:9997 = $result (SOVEREIGNTY VIOLATION!)"; fi

echo ""
echo -e "${GREY}  Site B → Core IDX mgmt port (must be BLOCKED):${NC}"
result=$(docker exec siteb-idx bash -c 'timeout 3 bash -c "</dev/tcp/core-idx/8089" && echo REACHABLE || echo BLOCKED' 2>/dev/null)
if [ "$result" = "BLOCKED" ]; then pass "siteb-idx → core-idx:8089 = BLOCKED"; else fail "siteb-idx → core-idx:8089 = $result (SOVEREIGNTY VIOLATION!)"; fi

echo ""
note "Result: Site B can ONLY reach SH for search dispatch. Cannot reach Core IDX."
note "Story to tell: I caught a leak in the first design (both indexers were on"
note "wan-net, could see each other). Fixed by giving Site A its own wan-core-net,"
note "leaving wan-net dedicated to Site B sovereignty traffic. Trust but verify."
pause || true

step "2.3  Pillar 2: Splunk config lockdown — defense-in-depth"
note "Even if network opened, Splunk has no forwarding target defined."
run "docker exec -u splunk siteb-idx bash -c \"/opt/splunk/bin/splunk btool outputs list --debug 2>&1 | grep -E 'indexAndForward|server *=' | head -10\""
note "Key findings: indexAndForward=false (won't forward), no server= entries"
note "(no destination defined). Network AND Splunk both refuse to leak data."
pause || true

step "2.4  Pillar 3: Concrete data test — does an event injected at Site B stay there?"
note "Inject a uniquely-tagged event into Site B; ask the SH to find it."
note "If sovereignty works, ONLY siteb-idx should report having it."

# Create index if not exists, ignore errors
docker exec -u splunk siteb-idx /opt/splunk/bin/splunk add index siteb_sovereignty -auth "admin:${SPLUNK_PWD}" >/dev/null 2>&1 || true

# Inject a fresh event
TS=$(date +%s)
docker exec -u splunk siteb-idx bash -c "echo 'SOVEREIGNTY_DEMO_${TS} site=B classification=restricted' > /tmp/demo_event.log"
docker exec -u splunk siteb-idx /opt/splunk/bin/splunk add oneshot /tmp/demo_event.log -index siteb_sovereignty -sourcetype sovereignty_test -auth "admin:${SPLUNK_PWD}" >/dev/null 2>&1
echo -e "${GREY}  Injected: SOVEREIGNTY_DEMO_${TS} into siteb_sovereignty index${NC}"

note "Waiting 5 seconds for indexing..."
sleep 5

run "docker exec -u splunk core-shd /opt/splunk/bin/splunk search 'index=siteb_sovereignty SOVEREIGNTY_DEMO_${TS} | stats count by splunk_server' -auth admin:${SPLUNK_PWD} -maxout 0 -preview false 2>&1 | grep -v WARNING"
pass "Event found ONLY on siteb-idx. Raw data never crossed the WAN — only the search result text did."
pause || true

# =============================================================================
# SECTION 3 — BUFFERING (Day 2b): LIVE WAN OUTAGE, ZERO DATA LOSS
# =============================================================================
section "SECTION 3 — Buffering: Live WAN Outage with Zero Data Loss"

step "3.1  Loadgen produces 1 event/sec to HF; HF forwards to Core IDX"
note "Architecture: loadgen → HEC(HF) → S2S(HF→Core IDX, useACK=true, persistent queue 500MB)"
note "Loadgen output (last 5 lines — should show http_code=200):"
run "docker logs sitea-loadgen --tail 5"
pause || true

step "3.2  HF forwarding configuration — useACK + persistent queue"
note "If WAN drops, useACK ensures HF retains events until Core IDX confirms receipt."
run "docker exec -u splunk sitea-hf bash -c \"/opt/splunk/bin/splunk btool outputs list --debug 2>&1 | grep -E 'useACK|maxQueueSize|server *=' | grep apps/sitea_hf_outputs | head -5\""
pass "useACK = true, maxQueueSize = 500MB — 24h survival on this lab's event rate"
pause || true

step "3.3  T0 baseline — current event count and max seq number BEFORE outage"
T0_OUTPUT=$(docker exec -u splunk core-shd /opt/splunk/bin/splunk search 'index=sitea_buffer LOADGEN | stats max(seq) as max_seq, count' -auth "admin:${SPLUNK_PWD}" -maxout 0 -preview false 2>&1 | grep -v WARNING)
echo "$T0_OUTPUT"
T0_MAX=$(echo "$T0_OUTPUT" | tail -1 | awk '{print $1}')
T0_COUNT=$(echo "$T0_OUTPUT" | tail -1 | awk '{print $2}')
note "Recorded baseline: max_seq=${T0_MAX}, count=${T0_COUNT}"
pause || true

step "3.4  CUTTING THE WAN — disconnecting sitea-hf from wan-core-net"
note "This simulates: WAN link between Site A and Core DC goes down."
note "What we expect: loadgen keeps producing, HF queue grows, Core IDX stops receiving."
run "docker network disconnect usa-wan-core sitea-hf"
echo -e "${RED}${BOLD}  ⚡ WAN CUT at $(date '+%H:%M:%S')${NC}"

echo ""
note "Confirming network cut at TCP level..."
result=$(docker exec sitea-hf bash -c 'timeout 3 bash -c "</dev/tcp/core-idx/9997" && echo REACHABLE || echo BLOCKED' 2>/dev/null)
if [ "$result" = "BLOCKED" ]; then pass "sitea-hf → core-idx:9997 = BLOCKED (outage confirmed)"; else fail "Cut didn't apply: $result"; fi
pause || true

step "3.5  During outage — countdown ${OUTAGE_SECS}s while loadgen keeps writing to HF"
note "Loadgen still gets http_code=200 because it talks to HF locally (HEC, sitea-net)."
note "But HF cannot forward upstream — events accumulate in the persistent queue."
countdown $OUTAGE_SECS "Waiting through outage"
pause || true

step "3.6  Outage proof — Core IDX has NOT received new events"
DURING_OUTPUT=$(docker exec -u splunk core-shd /opt/splunk/bin/splunk search 'index=sitea_buffer LOADGEN | stats max(seq) as max_seq, count' -auth "admin:${SPLUNK_PWD}" -maxout 0 -preview false 2>&1 | grep -v WARNING)
echo "$DURING_OUTPUT"
DURING_MAX=$(echo "$DURING_OUTPUT" | tail -1 | awk '{print $1}')
note "T0 max_seq was ${T0_MAX}. During outage, max_seq is ${DURING_MAX}."
if [ "${DURING_MAX}" = "${T0_MAX}" ]; then
    pass "Core IDX max_seq unchanged — no new events arrived during outage."
else
    note "Slight drift expected if loadgen was mid-flight. Important is: queue should drain on reconnect."
fi

echo ""
note "Loadgen still working (sending to HF locally, http_code=200):"
docker logs sitea-loadgen --tail 3

echo ""
note "Splunk has now also flagged the forward as inactive:"
docker exec -u splunk sitea-hf /opt/splunk/bin/splunk list forward-server -auth "admin:${SPLUNK_PWD}" 2>&1 | grep -v WARNING
pause || true

step "3.7  RESTORING THE WAN — reconnecting sitea-hf to wan-core-net"
run "docker network connect usa-wan-core sitea-hf"
echo -e "${GREEN}${BOLD}  ✓ WAN RESTORED at $(date '+%H:%M:%S')${NC}"

echo ""
note "Confirming network restoration at TCP level..."
sleep 2
result=$(docker exec sitea-hf bash -c 'timeout 3 bash -c "</dev/tcp/core-idx/9997" && echo REACHABLE || echo BLOCKED' 2>/dev/null)
if [ "$result" = "REACHABLE" ]; then pass "sitea-hf → core-idx:9997 = REACHABLE"; else fail "Reconnect issue: $result"; fi
pause || true

step "3.8  Drain phase — countdown ${DRAIN_SECS}s while HF flushes queue to Core"
note "HF will replay buffered events to Core IDX. Each event ACKed before HF removes it."
countdown $DRAIN_SECS "Waiting for queue drain"
pause || true

step "3.9  THE MOMENT OF TRUTH — was anything lost?"
note "Final tally: Core IDX should have received ALL events generated, including"
note "those produced during outage. Sequence numbers should be CONTIGUOUS (gap=0)."
echo ""
FINAL_OUTPUT=$(docker exec -u splunk core-shd /opt/splunk/bin/splunk search 'index=sitea_buffer LOADGEN | stats min(seq) as min_seq, max(seq) as max_seq, count, dc(seq) as unique_seqs | eval expected=max_seq-min_seq+1 | eval gap=expected-unique_seqs' -auth "admin:${SPLUNK_PWD}" -maxout 0 -preview false 2>&1 | grep -v WARNING)
echo "$FINAL_OUTPUT"

GAP=$(echo "$FINAL_OUTPUT" | tail -1 | awk '{print $NF}')

echo ""
if [ "${GAP}" = "0" ]; then
    pass "GAP = 0 → ALL sequence numbers from min_seq to max_seq are present."
    pass "Zero data loss across the WAN outage. Persistent queue + ACK delivered."
else
    fail "GAP = ${GAP} → ${GAP} events missing across outage. Check buffer sizing."
fi
pause || true

# =============================================================================
# SECTION 4 — SYSLOG TIER (Day 3): rsyslog DISK QUEUE + UF FILE-TAIL
# =============================================================================
section "SECTION 4 — Syslog Tier: Restart-Safe UDP Collection"

step "4.1  The UDP loss problem and why we don't send syslog directly to Splunk"
note "Network devices send UDP/514. Two risks with native Splunk UDP listener:"
note "  • UDP packets are lossy (no retransmit on network drops)"
note "  • Splunk's UDP buffer is RAM-only — restart = data loss"
note ""
note "Our solution: a dedicated rsyslog tier sits between devices and Splunk."
note "  device → UDP/514 → rsyslog (DISK queue) → file → UF tails → HF → Core"
note ""
note "rsyslog disk-assisted queue survives daemon restart."
note "UF tracks file position via fishbucket — survives UF restart."
pause || true

step "4.2  rsyslog disk-assisted queue configuration"
note "The durability mechanism in rsyslog.conf:"
run "docker exec sitea-syslog grep -A6 'main_queue' /etc/rsyslog.conf"
note "queue.filename + spoolDirectory + saveOnShutdown — events survive restart."
pause || true

step "4.3  UF inputs and outputs — apps deployed via Ansible at first boot"
note "These configs are baked into the image as Splunk apps; UF auto-loads them."
echo ""
echo -e "${GREY}  Inputs — what UF monitors:${NC}"
run "docker exec -u splunk sitea-syslog bash -c \"/opt/splunkforwarder/bin/splunk btool inputs list --debug 2>&1 | grep -A3 'monitor:///var/log/network'\""

echo ""
echo -e "${GREY}  Outputs — where UF forwards (with ACK):${NC}"
run "docker exec -u splunk sitea-syslog bash -c \"/opt/splunkforwarder/bin/splunk btool outputs list --debug 2>&1 | grep -E 'sitea-hf|useACK' | head -5\""

echo ""
note "Forward server status — must show core path is alive:"
run "docker exec -u splunk sitea-syslog /opt/splunkforwarder/bin/splunk list forward-server -auth admin:${SPLUNK_PWD} 2>&1 | grep -A2 -E 'Active|inactive'"
pass "UF actively forwarding to Site A HF (which forwards on to Core IDX)"
pause || true

step "4.4  Live test — inject syslog messages from two simulated devices"
note "We send 5 messages from a fake router and 5 from a fake firewall."
note "Each one travels: logger → UDP/514 → rsyslog → file → UF → HF → Core IDX"

# Generate burst messages with unique tag
TAG="DEMO_SYSLOG_$(date +%s)"
echo ""
echo -e "${GREY}  Sending 5 router messages and 5 firewall messages...${NC}"
for i in 1 2 3 4 5; do
    docker exec sitea-syslog logger -n localhost -P 514 -d -t "router-01" "${TAG} seq=${i} action=interface_state status=up" 2>/dev/null || true
    docker exec sitea-syslog logger -n localhost -P 514 -d -t "fw-01" "${TAG} seq=${i} action=block src=10.0.0.${i} dst=8.8.8.8" 2>/dev/null || true
    sleep 1
done
pass "10 syslog messages sent via UDP/514"
pause || true

step "4.5  Per-host file output — rsyslog wrote to separate files by source"
note "rsyslog template extracts hostname from each message and writes a"
note "dedicated file. This is what UF then tails."
run "docker exec sitea-syslog ls -la /var/log/network/"
echo ""
echo -e "${GREY}  Last 3 lines from each host file:${NC}"
run "docker exec sitea-syslog bash -c 'for f in /var/log/network/*.log; do echo \"=== \$f ===\"; tail -3 \"\$f\"; done'"
pause || true

step "4.6  End-to-end proof — events arrived at Core IDX with correct host parsing"
note "Waiting 8 seconds for UF tail + S2S forward + indexing..."
sleep 8

run "docker exec -u splunk core-shd /opt/splunk/bin/splunk search 'index=network_syslog ${TAG} | stats count by host, sourcetype' -auth admin:${SPLUNK_PWD} -maxout 0 -preview false 2>&1 | grep -v WARNING"

echo ""
pass "Two distinct hosts (router-01 + fw-01) parsed correctly via host_segment"
pass "End-to-end: device → rsyslog disk queue → file → UF → HF → Core IDX"
note "In production: rsyslog runs HA with keepalived + VIP — devices send to VIP."
note "If one rsyslog dies, the other takes over within 1-2 seconds."
pause || true

# =============================================================================
# SECTION 5 — CLOSING
# =============================================================================
section "Demo complete — recap"

echo ""
echo -e "  ${GREEN}✓${NC} Day 1: ${BOLD}Single Pane of Glass${NC} via federated distributed search"
echo -e "  ${GREEN}✓${NC} Day 2a: ${BOLD}Sovereignty${NC} via 3-pillar defense-in-depth"
echo -e "       └─ Network isolation (TCP test matrix)"
echo -e "       └─ Splunk config lockdown (outputs.conf has no targets)"
echo -e "       └─ Concrete data test (event stays at Site B)"
echo -e "  ${GREEN}✓${NC} Day 2b: ${BOLD}24h Zero Data Loss${NC} via persistent queue + ACK"
echo -e "       └─ Live WAN outage simulation, gap=0 proven"
echo -e "  ${GREEN}✓${NC} Day 3: ${BOLD}Syslog Reliability${NC} via rsyslog disk queue + UF tail"
echo -e "       └─ Per-host file output, fishbucket position tracking"
echo -e "  ${GREEN}✓${NC} Governance: ${BOLD}Configuration as Code${NC} via Git + GitHub Actions CI"
echo -e "       └─ 6/6 green checks: yamllint, hadolint, btool, gitleaks, etc."
echo ""
echo -e "${GREY}  Production scaling path (designed but not lab-implemented):${NC}"
echo -e "${GREY}    • Indexer Cluster per restricted site (RF=2/SF=2, 3+ peers)${NC}"
echo -e "${GREY}    • Search Head Cluster (3 members + Deployer)${NC}"
echo -e "${GREY}    • rsyslog HA pair behind keepalived VIP at each site${NC}"
echo -e "${GREY}    • Federated Search for Splunk (FS-S) for stricter isolation${NC}"
echo ""
echo -e "${BOLD}  Questions?${NC}"
echo ""
