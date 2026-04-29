# Day 1 — Step-by-Step Checklist

Goal: bring up the foundation (3 containers) and confirm distributed search
works between the Search Head and both indexers.

**Time budget:** ~2 hours (most of it waiting for Splunk to initialize).

---

## Pre-flight

- [ ] Docker Desktop is running and you can run `docker version` without errors
- [ ] At least 8 GB RAM free (`docker info | grep "Total Memory"`)
- [ ] Ports 8000, 8001, 8002, 8089, 8189, 8289, 9997, 9998 are not in use
  (`lsof -i:8000` returns nothing on macOS/Linux; `netstat -ano | findstr 8000` on Windows)
- [ ] At least 20 GB free disk space

---

## Step 1 — Bootstrap

```bash
cd unified-splunk-architecture
chmod +x scripts/*.sh
./scripts/start.sh
```

Expected:
- First run pulls the Splunk image (~2 GB, can take 5-10 min on slow internet)
- Containers start, but report `health: starting` for ~3 minutes while
  splunk-ansible provisions them inside

- [ ] `docker compose ps` shows 3 containers running

---

## Step 2 — Watch Splunk initialize

```bash
docker compose logs -f core-shd
```

Look for these milestones in the logs:
- `TASK [splunk_common : Generate user-prefs.conf]` — Ansible has started
- `TASK [splunk_search_head : Set as search head]` — role being applied
- `TASK [splunk_search_head : Configure default search peers]` — peers added
- `Ansible playbook complete` — done!

Press `Ctrl+C` to stop following logs once you see the playbook complete.

- [ ] All 3 containers eventually report `health: healthy` (`docker compose ps`)

If a container is stuck `unhealthy` after 10+ minutes:
```bash
docker compose logs core-shd | tail -100
```
Common cause: not enough RAM. Lower the `memory: 1500M` limits.

---

## Step 3 — First login

Open http://localhost:8000 in a browser.
- Username: `admin`
- Password: see your `.env` file (`Splunk-Lab-2026!` if you didn't change it)

- [ ] You see the Splunk Home page

Click **Settings → Distributed Environment → Distributed Search → Search peers**.
- [ ] You see two peers listed: `core-idx:8089` and `siteb-idx:8089`
- [ ] Both peers show status `Up`

> If status is `Down`, click on the peer name → check
> "Authentication" — the certificate exchange happened during ansible
> setup but can fail on first run. Easiest fix: restart the SH container:
> `docker compose restart core-shd`

---

## Step 4 — First federated search

In the Splunk Web search bar (Apps → Search & Reporting), paste:

```spl
| rest /services/server/info splunk_server=*
| table splunk_server, version, os_name
```

This is a **federated search** — `splunk_server=*` means "ask every search
peer for their server info". You should see THREE rows:
- `core-shd` (the SH itself)
- `core-idx`
- `siteb-idx`

- [ ] All three rows are present

This proves: a single search dispatched from the SH produced results
sourced from both indexers — **single pane of glass** is working.

---

## Step 5 — Run automated acceptance tests

```bash
./scripts/verify.sh
```

- [ ] All four tests pass with green checkmarks

If any fail, fix before proceeding to Day 2. The Day 2+ work assumes
this foundation is solid.

---

## Step 6 — Initial Git commit (lay the governance foundation)

```bash
git init
git add .
git status   # confirm .env is NOT in the staged files
git commit -m "feat: Day 1 — foundation stack with distributed search"
```

- [ ] Repo initialized, first commit created
- [ ] `.env` is gitignored (NEVER commit secrets)

If you want to push to GitHub now, create the repo there and:
```bash
git remote add origin git@github.com:YOUR_USER/unified-splunk-architecture.git
git push -u origin main
```

---

## Day 1 done when

- [ ] All 3 containers healthy
- [ ] Splunk Web reachable on http://localhost:8000
- [ ] Both indexers visible as connected search peers in Settings
- [ ] Federated search returns results from both indexers
- [ ] `verify.sh` passes 100%
- [ ] First commit pushed to Git

**You can now demo "single pane of glass" to the interviewer.**
The remaining days add the case study's harder requirements (sovereignty
enforcement, buffering, syslog, CI/CD).

---

## What to write in your interview notes for Day 1

> "I started by validating the architectural foundation: a Search Head
> and two Indexers (one Core, one Restricted-Site-B) on segmented Docker
> networks. I confirmed federated search works end-to-end before adding
> any of the harder constraints. The `verify.sh` script gives me a 30-second
> repeatable health check I can run in front of you during the demo."
