# Unified Splunk Architecture — Multi-Site Lab

![CI](https://github.com/ozgunozcetin/unified-splunk-architecture/actions/workflows/ci.yml/badge.svg)

## Architecture

![Architecture](docs/architecture.png)

The lab implements three logical sites with five Docker networks modelling
trust boundaries. Source: [`docs/architecture.drawio`](docs/architecture.drawio)
(open in https://app.diagrams.net).

A Docker Compose lab that demonstrates the case study **"Unified Splunk
Architecture for a Multi-Site, Sovereignty-Constrained Organization"**.

## What this lab proves

| Requirement | How this lab demonstrates it |
|---|---|
| **Single Pane of Glass** | One Search Head dispatches federated search across all sites simultaneously |
| **Data Sovereignty (Sites B & D)** | Site B indexer is on an isolated Docker network — raw data never leaves; only search results return |
| **Zero Data Loss for 24h** | Site A Heavy Forwarder uses persistent queue + indexer ACK; survives WAN outages |
| **Syslog reliability** | Dedicated rsyslog tier with disk-assisted queue, file-tail by UF (eliminates UDP loss) |
| **Configuration as Code** | All `.conf` files in Git, GitHub Actions CI lints + dry-runs before deploy |

## Scope

| Production | This Lab |
|---|---|
| 6 sites (A, B, C, D, E, F) | 3 representative sites (Core DC, Site A open, Site B restricted) |
| Indexer Cluster (RF=2/SF=2, 3+ peers per site) | 1 indexer per site (single peer) |
| Search Head Cluster (3 members + Deployer) | 1 search head |
| Production WAN | Docker bridge networks simulating WAN |

## Prerequisites
- **Docker Desktop** (or Docker Engine + Compose v2) — Linux/macOS/Windows
- **8 GB RAM** minimum (12 GB recommended for Day 2+)
- **20 GB free disk space** (for Splunk volumes)
- **Internet access** (for pulling the Splunk image, ~2 GB)

### Access points

| URL | Role | Login |
|---|---|---|
| http://localhost:8000 | Core Search Head — SOC entry point | `admin` / see `.env` |
| http://localhost:8001 | Core Indexer — admin only | `admin` / see `.env` |
| http://localhost:8002 | Site B Indexer — admin only | `admin` / see `.env` |

**`verify.sh` says peers not registered**
Splunk Ansible adds peers at startup. If the SH started before the IDXs
were ready, peers may be missing. Restart the SH only:
```bash
docker compose restart core-shd
```
**Port conflicts (8000, 8089, 9997 already in use)**
Edit the `ports:` section in `docker-compose.yml` to use different host
ports (e.g. `9000:8000` instead of `8000:8000`).

## License & legal

This lab uses **Splunk Enterprise Trial** (60-day full feature). The Splunk
software is subject to the [Splunk General Terms](https://www.splunk.com/en_us/legal/splunk-general-terms.html).
By starting the containers, you accept these terms.
