---
post_title: "multichain-docker README"
author1: "leodyver"
post_slug: "multichain-docker-readme"
microsoft_alias: "leodyver"
featured_image: ""
categories: ["docker"]
tags: ["multichain","docker","blockchain","explorer"]
ai_note: "AI-assisted"
summary: "Docker-based Multichain setup with master, peers and an explorer; includes build/run instructions, healthchecks and troubleshooting."
post_date: "2025-08-24"
---

# multichain-docker

This repository contains Dockerfiles, entrypoints and helper scripts to run a small Multichain network locally (a masternode, two peers and an explorer). It's intended for development, demos and CI smoke tests.

## What is included

- `docker-compose.yaml` — top-level compose file that builds and runs the services.
- `base/` — shared base image artifacts (`Dockerfile`, `entrypoint.sh`, `mc-common.sh`).
- `master/` — masternode Dockerfile and entrypoint.
- `node/` — peer node Dockerfile and `connect-node.sh` helper.
- `explorer/` — explorer Dockerfile and `run-services.sh` that launches the web UI and backend indexer.
- `scripts/` — repository helper scripts (`healthcheck_rpc.sh`, `setup.sh`, `smoke-test.sh`).

## Services, ports and volumes (concrete)

Services defined in `docker-compose.yaml`:
- `masternode` (build: `./master`)
  - Ports: 7447 (P2P), 8000 (RPC)
  - Volume: `master_data` mapped to `/home/multichain/.multichain`
- `explorer` (build: `./explorer`)
  - Port: 2750 (web UI)
  - Shares `master_data` so explorer can read chain files
- `peer1`, `peer2` (build: `./node`)
  - Each has its own volume: `peer1_data`, `peer2_data`

Named volumes (in the compose file): `master_data`, `peer1_data`, `peer2_data`.

## Important environment variables

Set these via an `.env` file or your environment before running compose (the compose file references them):
- `CHAIN_NAME` — chain identifier (default in scripts: `procuchain` / `dockerchain` in some helpers)
- `RPC_USER`, `RPC_PASSWORD` — RPC basic auth credentials for the masternode
- `RPC_ALLOWIP` — RPC allow list (if needed)
- `MASTER_PORT` — masternode P2P/management port (compose uses `7447` by default)
- `RPC_HOST`, `RPC_PORT` — used by explorer to contact the masternode (defaults: `masternode`, `8000`)

The repository's shell helpers (`base/mc-common.sh` and `explorer/run-services.sh`) support loading secrets from files via `*_FILE` env vars (for example `RPC_PASSWORD_FILE`) and will trim CR/LF to be robust on Windows-created secret files.

## Quick start (recommended environment)

On Windows prefer WSL2 (or Git Bash) and Docker Desktop with the WSL2 backend to run the included POSIX shell scripts. The compose file and scripts are compatible with both `docker compose` (v2) and `docker-compose` (legacy), but some helper scripts call the `docker compose` subcommand (no hyphen).

From the repository root:

```powershell
# Build and start all services (detached)
docker compose up --build -d
# or with older Docker Compose:
docker-compose up --build -d
```

Check status:

```powershell
docker compose ps
```

Stop and remove containers and volumes (clean slate):

```powershell
docker compose down -v
```

## Setup (prerequisites and configuration)

Follow these steps once before first run to prepare your machine and the repository configuration.

1) Install prerequisites

- Docker Desktop (with WSL2 backend on Windows) or a Linux host with Docker Engine and the Compose plugin.
- Git (to clone the repo) and a POSIX shell for the provided scripts (WSL2, Git Bash, or similar on Windows).

2) Create a minimal `.env` at the repository root to provide runtime variables used by `docker-compose.yaml`.
Create a file named `.env` with contents similar to the example below. Adjust values before first run.

```powershell
# .env example (place in repository root)
CHAIN_NAME=procuchain
RPC_USER=multichain
RPC_PASSWORD=change_this_password
RPC_ALLOWIP=127.0.0.1/32
MASTER_PORT=7447
RPC_HOST=masternode
RPC_PORT=8000
# Optional: override explorer port
EXPLORER_PORT=2750
```

Security note: prefer using file-based secrets for sensitive values in CI or shared dev machines. The images and `base/mc-common.sh` support `*_FILE` variables (for example `RPC_PASSWORD_FILE`) and will load and trim contents safely.

Note: this repository already includes `.env.example` as a template; the real `.env` file is gitignored by default. Keep your generated `.env` private and do not commit it.


3) Make helper scripts executable (if needed) and run the interactive repo setup script

The provided `scripts/setup.sh` is interactive: it prompts for values (chain name, RPC user, RPC password — with an option to auto-generate), writes a locked `.env` at the repository root (mode 600) and then starts the `masternode` and `explorer` services.

On Windows with PowerShell (using WSL to execute POSIX scripts):

```powershell
wsl bash -lc "chmod +x ./scripts/*.sh ./explorer/run-services.sh ./node/connect-node.sh ./base/entrypoint.sh || true"
wsl ./scripts/setup.sh
```

Or from a POSIX shell (WSL/Git Bash/Linux):

```bash
chmod +x ./scripts/*.sh ./explorer/run-services.sh ./node/connect-node.sh ./base/entrypoint.sh || true
./scripts/setup.sh
```

Behavior notes:
- If `.env` already exists the script prompts to confirm overwrite (interactive shells). In non-interactive sessions the script will abort if `.env` exists.
- RPC passwords are either provided by you or auto-generated; the generated password is written to `.env` and the file is created with permissions 600. Keep this file private.
- The script detects whether to use `docker compose` or the older `docker-compose` and uses whichever is available.

4) Optional: create Docker secrets for CI or production-like setups

Example (create secrets from host files):

```powershell
wsl printf "%s" "$RPC_PASSWORD" > /tmp/rpc_password && docker secret create rpc_password /tmp/rpc_password
```

Then set `RPC_PASSWORD_FILE=/run/secrets/rpc_password` in container envs or compose overrides. The repository scripts and entrypoints support loading secrets via `*_FILE` environment variables.

5) File permissions and ownership on Windows

When using host-mounted volumes on Windows (without WSL), line endings or ownership may cause issues. Use WSL2 for a smoother experience: it preserves POSIX permissions and avoids CRLF issues in secret files.

After completing the setup steps above proceed to the Quick start section to launch the stack.

## Example RPC calls

The masternode exposes an HTTP JSON-RPC on port `8000` (container) mapped to the host. If you set `RPC_USER`/`RPC_PASSWORD`, use basic auth.

Example curl (host machine):

```bash
curl -sS -u "$RPC_USER:$RPC_PASSWORD" -X POST \
  -H 'content-type: text/plain;' \
  --data-binary '{"jsonrpc":"1.0","id":"curl","method":"getinfo","params":[]}' \
  http://127.0.0.1:8000/
```

If you don't provide credentials, the included `scripts/healthcheck_rpc.sh` and explorer will attempt unauthenticated RPCs when configured that way.

You can also run RPC calls from inside the masternode container (avoids host networking quirks):

```powershell
docker compose exec -T masternode sh -c "curl -sS -u \"$RPC_USER:$RPC_PASSWORD\" -X POST -H 'content-type: text/plain;' --data-binary '{\"jsonrpc\":\"1.0\",\"id\":\"hc\",\"method\":\"getinfo\",\"params\":[]}' http://127.0.0.1:8000/"
```

## Healthchecks and smoke tests

- `scripts/healthcheck_rpc.sh` — used by the masternode service healthcheck in `docker-compose.yaml`. It posts a `getinfo` RPC and checks for a `"result"` field.
- `scripts/smoke-test.sh` — orchestrates bringing the stack up, waiting for health, verifying peer connectivity and explorer responsiveness. The smoke test uses `docker compose` internally and cleans up the stack when finished (unless `NO_CLEAN=1`).

Note: the smoke test prefers `multichain-cli` but has fallbacks to HTTP RPC because `multichain-cli` may crash in some environments; logs and diagnostic output are printed on failure.

## Common tasks

- Rebuild a single image (example: `node`):

```powershell
docker build -t multichain-node:local ./node
```

- Execute a one-off shell in a running service:

```powershell
docker compose exec <service-name> /bin/bash
```

- Start only specific services (useful for development):

```powershell
docker compose up -d masternode explorer
```

## Troubleshooting notes

- Shell scripts are POSIX: on Windows run them from WSL2 or Git Bash, or prefix with `wsl` in PowerShell (for example `wsl ./scripts/smoke-test.sh`).
- If a build fails, inspect the service's `Dockerfile` (in `master/`, `node/`, or `explorer/`) and re-run with verbose output:

```powershell
docker compose build <service>
```

- View runtime logs:

```powershell
docker compose logs -f masternode
```

- If the explorer web UI doesn't show expected content, check the explorer container health and `explorer` logs. The explorer expects access to the masternode RPC (envs: `RPC_HOST`, `RPC_PORT`, `RPC_USER`, `RPC_PASSWORD`).

## Developer notes / internals

- `base/mc-common.sh` provides helpers used across images: logging (`mc_log`), ensuring chain directory creation (`mc_ensure_chain_dir`), fixing permissions, and loading secrets from `*_FILE` env vars.
- `explorer/run-services.sh` generates an `explorer.ini` at runtime (unless `GENERATE_EXPLORER_CONF=0`) and waits for the master RPC to respond before launching the Python-based explorer.
- Compose healthchecks:
  - masternode uses `/scripts/healthcheck_rpc.sh` (container path) to validate RPC readiness.
  - explorer checks HTTP on port 2750 using curl.
  - peers run an internal `multichain-cli getinfo` check inside the container.

## Suggested next steps

- Add an `env.example` listing the common env vars and sensible defaults.
- Add a `Makefile` or `tasks.json` to simplify common developer actions (`build`, `up`, `down`, `smoke-test`).
- Optionally wire `scripts/healthcheck_rpc.sh` into CI (e.g., GitHub Actions) as a fast integration check.

## License

See the `LICENSE` file in the repository root.

---

If you want, I can now:
- extract concrete env defaults and service port mappings into an `env.example` by parsing `docker-compose.yaml`,
- add a `Makefile` for common commands, or
- run the smoke test locally and report results (I will run the commands in a terminal if you want me to).

Tell me which of the above you'd like next.
