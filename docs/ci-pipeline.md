# CI Pipeline — Configuration-as-Code Gate

Every push and pull request triggers a six-job pipeline before any change can
be merged into `main`. The pipeline is the operational form of the case
study's "configuration-as-code with non-repudiation" requirement.

## Pipeline jobs

| Job | Tool | What it catches |
|---|---|---|
| YAML lint | `yamllint` | Indentation, quoting, structural issues in docker-compose.yml and workflow files |
| Dockerfile lint | `hadolint` | Common Dockerfile mistakes — missing pinning, root user, layer bloat |
| Splunk .conf validation | `splunk btool check` | Typos, unknown stanzas, invalid values in app configs |
| Markdown lint | `markdownlint-cli2` | Documentation consistency |
| Secret scan | `gitleaks` | Accidentally committed credentials |
| CI summary | (aggregator) | Overall pass/fail gate |

## Why each gate matters

**YAML lint** — `docker-compose.yml` is the topology source of truth.
A subtle indentation bug here can mean a service silently runs without a
network attachment, breaking sovereignty enforcement. Lint catches it
before deploy.

**Dockerfile lint** — Dockerfiles ship to production unchanged. A pinned
package version, a non-root user directive, a missing healthcheck — all
checked before merge.

**Splunk btool check** — The most important gate. Runs the real Splunk
binary inside an official container against our `.conf` files. Catches
the kinds of errors that only surface at runtime (which means after deploy)
without it: misspelled stanza names, deprecated keys, invalid values.

**Markdown lint** — Documentation is part of the deliverable. Inconsistent
markdown means the case study reads as carelessly written.

**Secret scan** — The lesson learned. During this lab's development a
`.enveso` file was accidentally committed (a typo of `.env.example`) which
contained the actual lab password and HEC token. The file was removed and
`.gitignore` was hardened, but the history retains it. Going forward,
gitleaks runs on every commit and fails the build if it detects secret-shaped
content.

## Non-repudiation chain

The pipeline produces three independent audit records that any compliance
reviewer can cross-reference:

1. **Git** — every commit is signed (GPG) and linked to a real identity.
   The diff is preserved forever.
2. **GitHub Actions** — every CI run logs which checks ran, when, on what
   commit, with what outcome. Run logs are retained for 90 days by default.
3. **Splunk `_audit` index** — when configuration is deployed via Cluster
   Manager / SHC Deployer / Deployment Server, Splunk records the bundle
   change in its own audit log, with the deploying user's identity.

A change that survives all three gates has been authored by an identified
developer, peer-reviewed, lint-passed, and applied through Splunk's own
deployment mechanism — three independent witnesses.

## Local pre-flight

Run the same checks locally before pushing:

```bash
bash scripts/lint.sh
```

Requires `yamllint`, `hadolint` to be installed locally.
The CI environment has them; locally you may need:

```bash
pip install yamllint
brew install hadolint    # or wget the binary on Linux/Windows
```

## Branch protection (production setup)

In a production deployment of this CI, the following branch protection rules
would be applied to `main`:

- Require at least one peer review before merge
- Require all status checks to pass (the `ci-summary` job above)
- Require signed commits
- Disallow force pushes
- Restrict who can push (deployment automation accounts only)

Together these turn `main` into the single source of truth — no path to
production exists that bypasses the gates.
