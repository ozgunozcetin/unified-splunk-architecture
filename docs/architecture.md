# Architecture Decisions

This document captures the **reasoning** behind each design choice, mapped
back to the case study requirements. Use this as your interview reference.

---

## 1. Logical Topology

### Decision: Distributed indexing + single Search Head + federated search

**Each site has its own indexer (or indexer cluster in production).** Data
is ingested and indexed locally. The Search Head dispatches searches to
all sites; each indexer searches its local data and returns only matching
results.

### Why not centralize all data into one DC?

- **Sovereignty:** Sites B and D legally cannot ship data out — centralizing
  is prohibited by design constraint.
- **WAN efficiency:** Centralizing 6 sites' raw logs over unstable WAN
  would require massive WAN bandwidth and would lose data during outages.
- **Search locality:** Most searches are scoped (e.g. "show me failed logins
  on Site C in last hour") and run faster when the data is local to the
  indexer.

### Why not put a Search Head at every site?

- The case study explicitly requires **one SHC** ("single pane of glass").
- Distributed search is the standard Splunk pattern for this — search heads
  dispatch to remote peers; only results travel back, never raw events.

---

## 2. Sovereignty Solution (Sites B & D)

### Decision: Federated search + network isolation + `outputs.conf` lockdown

**Three layers of enforcement:**

#### Layer 1 — Splunk-native federated search
The SH issues a search; the bundle is sent to Site B's indexer; the indexer
runs the search **locally** and returns only the result set. Raw events
and `.tsidx` buckets never traverse the WAN.

> **In Splunk 9.x+ specifically:** Federated Search for Splunk (FS-S) is
> available and provides a stricter, more auditable variant where the
> remote dataset is exposed as a federated provider rather than a search
> peer. For this lab we use classic distributed search; production should
> evaluate FS-S for compliance posture.

#### Layer 2 — Network isolation
In `docker-compose.yml`, Site B's indexer is on `siteb-net` (local) and
`wan-net` (mgmt only) — but **NOT** on `core-net`. There is no network
path from `core-idx` to `siteb-idx`, so even if someone configured
forwarding by mistake, it could not reach the core indexer.

In production this maps to firewall rules: Site B indexers' egress is
blocked at the perimeter except for inbound mgmt port from the SHC.

#### Layer 3 — `outputs.conf` empty
The Site B indexer ships with **no** outgoing forwarders configured.
Combined with `useACK=false` and a missing `[tcpout]` stanza, the indexer
has no instruction to push data anywhere.

### How the SOC searches Site B without violating sovereignty

```
User in SOC clicks "Search" on the SH
        │
        ▼
SH dispatches search to siteb-idx via mgmt port (8089)
        │
        ▼
siteb-idx runs the search on LOCAL buckets
        │
        ▼
siteb-idx returns RESULT SET (matching events) to SH
        │
        ▼
SH merges results and renders to user

What crosses the boundary: search query (text), result events (text)
What never crosses: bucket files, .tsidx files, raw indexed data
```

### Auditability
- Every search dispatched to Site B is logged in `_audit` index on Site B's
  indexer (lives locally, available to compliance auditors on-site).
- `tcpdump` on Site B's external interface during a search shows only
  HTTPS traffic on port 8089 — no S2S (9997) traffic outbound.

---

## 3. Buffering Strategy (24-hour zero data loss)

### Decision: Layered persistent queues with indexer ACK

#### Tier 1 — Universal Forwarders on endpoints
```ini
# outputs.conf on every UF
[tcpout]
defaultGroup = primary

[tcpout:primary]
server = sitea-hf:9997
useACK = true
maxQueueSize = 7GB
```
- `useACK = true` — UF retains events until the receiving indexer/HF
  acknowledges they're indexed.
- `maxQueueSize` — disk-backed persistent queue. Sized to hold **at least
  24 hours** of expected log volume per host.

#### Tier 2 — Intermediate Heavy Forwarder per open site
Each open site has a dedicated HF that aggregates UF traffic and forwards
to Core indexer. The HF has its own large persistent queue.
```ini
# inputs.conf on the HF
[splunktcp://9997]
queueSize = 1GB
persistentQueueSize = 50GB     # ~24h buffer for the entire site
```

**Why not have UFs forward directly to Core?**
- Single TCP connection per UF over WAN = thousands of concurrent flows,
  high overhead.
- HF aggregates: 1 outbound flow from site to core.
- HF buffer is centralized at the site = easier to monitor and right-size.
- During WAN outage, all site UFs continue dumping to local HF (low-latency
  LAN), HF holds the queue.

#### Tier 3 — HEC for cloud-native apps
HEC endpoint exposed on the HF (with a TCP load balancer in front in
production). Clients use Splunk SDKs which retry with exponential backoff.
For higher resilience, **Cribl Stream** or **Apache Kafka** can be inserted
between HEC clients and the HF — this is a recommended Day-2 enhancement
for production but out of scope for this lab.

### Sizing math (per site)
```
Required buffer = peak_EPS × avg_event_size_bytes × 86400s × overhead(1.3)
Example:
  10,000 EPS × 800 bytes × 86,400s × 1.3 = ~900 GB

So Site A's HF needs ~1 TB of buffer-capable disk for 24h survival.
```

### What the lab demonstrates
On Day 2 we will:
1. Start the log generator → events flow → indexer counts increase.
2. `docker network disconnect usa-wan sitea-hf` → simulates WAN cut.
3. Generator keeps producing → HF queue fills (visible via `du -sh`).
4. `docker network connect usa-wan sitea-hf` → queue drains, indexer
   counts catch up.
5. Compare event counts before and after: **zero loss**.

---

## 4. Syslog Tier (UDP risk mitigation)

### Decision: Dedicated rsyslog tier with disk-assisted queue + file-tail UF

### Why NOT send syslog directly to Splunk?
- Splunk's UDP listener (`udp://514`) is a memory-only buffer. Restart
  the indexer/UF and **anything in flight is gone**.
- UDP itself has no retransmit. Network drops = data loss.
- Splunk's S2S forwarding doesn't apply to received UDP — there's no
  acknowledgment path from sender to Splunk.

### The pattern
```
Network device (router/firewall/switch)
        │
        │ UDP/514 or TCP/6514 (TLS)
        │
        ▼
Site-local rsyslog server (HA pair behind VIP)
   ↓
   Disk-assisted queue (rsyslog feature: $MainMsgQueueType LinkedList,
                                          $MainMsgQueueFileName syslog,
                                          $MainMsgQueueMaxDiskSpace 50G)
   ↓
   Writes to file: /var/log/network/<host>/<date>.log
        │
        ▼
Splunk UF on same host with monitor:// stanza
        │
        │ S2S 9997 with useACK=true
        │
        ▼
Site HF or Core indexer
```

### Why this works
- **rsyslog disk queue** — survives rsyslog restart and rsyslog server
  reboot. Production tooling for this exact problem.
- **File-tail by UF** — UF tracks position in file via `fishbucket`.
  Restart UF, it resumes from last byte read. Zero loss across restart.
- **HA with VIP** — keepalived/VRRP gives a single IP for devices to
  send to; if rsyslog-1 dies, rsyslog-2 takes over the VIP within 1-2s.
  Only worst-case 1-2s of UDP packets in flight could be lost (vs hours).
- **Co-location** — devices and rsyslog on same LAN. Network drops on
  the device→rsyslog hop are extremely rare (no WAN involvement).

---

## 5. Governance / Configuration as Code

### Decision: Git monorepo + GitHub Actions CI + native Splunk deployment mechanisms

### Repository structure
```
unified-splunk-architecture/
├── deployment-apps/          # Pushed to forwarders via Deployment Server
│   ├── all_uf_outputs/       # outputs.conf for all UFs
│   ├── linux_inputs/         # inputs.conf for Linux endpoints
│   └── ...
├── cluster-bundle/           # Pushed to indexer cluster via Cluster Manager
│   ├── indexes/              # indexes.conf — what indexes exist + retention
│   └── server_config/        # cluster-wide server.conf
├── shc-apps/                 # Pushed to SHC via SHC Deployer
│   ├── soc_dashboards/       # Saved searches, dashboards
│   └── soc_alerts/           # Scheduled alerts
└── ansible/                  # OS layer (Splunk binary install, OS tuning)
```

### CI/CD pipeline (GitHub Actions)
Every push triggers:

1. **Lint** — `splunk btool check` on every modified `.conf`
2. **AppInspect** — `splunk-appinspect` against the modified app
3. **Diff report** — what changed in human-readable form (PR comment)
4. **Manual gate** — at least one approver review required (branch protection)
5. **Deploy to staging** — `scripts/deploy-staging.sh` SSH's to the
   staging Deployment Server / Cluster Manager / SHC Deployer
6. **Smoke tests** — verify staging is healthy
7. **Production deploy** — gated by manual approval

### Non-repudiation chain
| Question | Answer |
|---|---|
| **Who?** | Git signed commits (GPG) — every change traceable to a real identity |
| **What?** | Git diff — exact line-level change visible in PR |
| **When?** | Git commit timestamp + GitHub Actions run timestamp |
| **Why?** | Conventional Commits format (e.g. `feat(siteb): add new indexes for ProjectX`) + linked ticket |
| **Did it deploy?** | GitHub Actions logs + Splunk's own `_audit` index logs the bundle change |

### Why this stack vs alternatives
- **Why Git?** Industry standard, already in every dev workflow,
  signed commits give cryptographic audit trail.
- **Why GitHub Actions?** Tight Git integration, simple syntax, free
  for many repos. Equivalent: GitLab CI, Azure DevOps Pipelines.
- **Why not Ansible-only?** Ansible is great for OS layer but doesn't
  understand Splunk's bundle/cluster mechanics. Use it for what it's
  good at; let Splunk's native deployment do the rest.
- **Why native Splunk deployment (DS / CM / SHC Deployer)?** They handle
  cluster-aware concerns: rolling restart, bundle validation, peer
  consistency. Reinventing this with Ansible would be brittle.

---

## Anti-patterns we explicitly avoided

| Anti-pattern | Why we avoided |
|---|---|
| Centralize all 6 sites' raw data into one DC | Violates sovereignty for B/D; consumes massive WAN |
| Send syslog UDP directly to Splunk indexer | Guaranteed loss on indexer restart |
| Use HEC without retry+ACK | Loss on network blip; no buffering |
| Manual `splunk add search-server` per peer | Doesn't scale, no audit trail, drift risk |
| Configure each indexer manually | Drift, no audit, breaks during DR |
| Search Heads at each site | Violates "single pane of glass" requirement |
| `outputs.conf` with `useACK=false` to save bandwidth | Trades data safety for marginal gain |
