---
post_title: "MultiChain Docker Deployment"
author1: "leodyversemilla07"
post_slug: multichain-docker-deployment
microsoft_alias: leodyver
featured_image: https://www.multichain.com/img/multichain-logo.png
categories: [blockchain, docker]
tags: [multichain, blockchain, docker, explorer, compose]
ai_note: "Content assisted by AI; validated by author."
summary: "Production-focused MultiChain 2.3.3 Docker stack (master creator, auto‑joining peers, legacy Python explorer) featuring integrity verification, secrets pattern, healthchecks, and smoke test."
post_date: 2025-08-19
---

## Overview

This stack provides:
- Base image (Ubuntu 22.04) with MultiChain 2.3.3 binaries, optional SHA256 integrity enforcement, non-root runtime, and shared helpers (`mc-common.sh`).
- Master (creator) node image: creates chain directory (if `AUTO_CREATE=1`), patches `params.dat` (ports & `anyone-can-connect`), generates secure RPC credentials (unless provided / secret injected), then delegates to the base entrypoint.
- Peer node image: resilient auto-join logic against a hostname and a candidate port list; optional fixed listen/RPC ports per peer.
- Legacy MultiChain Explorer container (may require legacy Python dependencies) with defensive patches and optional fast-start.
- Compose file: brings up 1 master + 2 peers + explorer with named volumes, restart policies, and resource limits examples.
- Healthchecks (CLI & HTTP), secrets pattern (`*_FILE`), smoke test automation.

## Recent changes

- Explorer connection issue resolved: explorer now uses the injected RPC secret and the correct RPC host so the UI shows "Connected" instead of "No Connection".
- Secrets-first approach: RPC passwords are no longer stored in the repository `.env`; use Docker secrets or file-backed `*_FILE` env vars (example: `RPC_PASSWORD_FILE=/run/secrets/rpc_password`).
- Healthcheck robustness: added a trimmed, file-aware RPC healthcheck script and tightened healthcheck logic to avoid CRLF-related failures.
- Repository hygiene: `secrets/` files are intended to be created locally and are ignored from git; do not commit plaintext credentials.

| Image | Role | Purpose | Tags (example) |
|-------|------|---------|----------------|
| `leodyversemilla07/multichain-base` | Base | MultiChain binaries + chain auto-create entrypoint | `2.3.3`, `latest` |
| `leodyversemilla07/multichain-master` | Core | Chain creator (requires CHAIN_NAME; generates RPC config) | `2.3.3`,  `latest` |
| `leodyversemilla07/multichain-node` | Peer | Generic runtime peer joining existing chain | `2.3.3`, `latest` |
| `leodyversemilla07/multichain-explorer` | Tooling | Legacy Python explorer (MCE) | `2.3.3-mce-master`, `latest` |

Pin to an immutable version or commit tag in production rather than `latest`.

## Architecture Summary

| Layer | Image | Key Responsibilities | Notable Environment Variables |
|-------|-------|----------------------|-------------------------------|
| Base | `multichain-base` | Install binaries, enforce (optional) tarball integrity, create non-root user, generic entrypoint | `MULTICHAIN_VERSION`, `MULTICHAIN_SHA256`, `REQUIRE_HASH`, `CHAIN_NAME`, `AUTO_CREATE`, `START_FLAGS` |
| Master | `multichain-master` | Chain genesis / first node, generate RPC config, patch `params.dat` | `CHAIN_NAME`, `RPC_USER`, `RPC_PASSWORD(_FILE)`, `RPC_ALLOWIP(_FILE)`, `RPC_PORT(_FILE)`, `ANYONE_CAN_CONNECT`, `P2P_PORT` |
| Peer | `multichain-node` | Discover and join master via hostname + port scan, optional custom listen/RPC ports | `CHAIN_NAME`, `MASTER_HOST`, `MASTER_PORT`, `MASTER_PORT_CANDIDATES`, `RETRIES`, `SLEEP_SECONDS`, `NODE_P2P_PORT`, `NODE_RPC_PORT`, `START_FLAGS` |
| Explorer | `multichain-explorer` | Light local daemon + web UI, on-the-fly explorer.conf, legacy indexer | `CHAIN_NAME`, `MASTER_HOST`, `MASTER_PORT`, `RPC_*`, `EXPLORER_PORT`, `EXPLORER_BIND`, `GENERATE_EXPLORER_CONF`, `FAST_START`, `COMMIT_BYTES`, `EXPLORE_FLAGS`, `RETRIES` |

### Runtime Flow
1. Master starts, creates chain dir (if absent), patches `params.dat` (enforcing `default-network-port`, `default-rpc-port`, and optionally `anyone-can-connect=true`).
2. Peers loop until master hostname resolves and a reachable port is found among `MASTER_PORT` or `MASTER_PORT_CANDIDATES` (default list includes `7447 7448 7449 8000 ...`).
3. Explorer waits for master reachability, seeds a minimalist local `multichain.conf`, optionally starts a lightweight daemon join, then serves the web UI.
4. Healthchecks surface readiness: CLI `getinfo` for nodes, HTTP `/` 200 for explorer.

## Prerequisites

- Docker (24+ recommended)
- Docker Compose plugin (Compose V2)
- (Optional) Bash for running helper script `deploy-multichain.sh`
- (Optional) Internet access to download official MultiChain tarball (or host a mirror via `MULTICHAIN_DOWNLOAD_BASE`)

## Integrity & Supply-Chain Verification

The base image can verify the downloaded tarball:
- Provide `--build-arg MULTICHAIN_SHA256=<official_hash>` (from MultiChain release site) and keep `REQUIRE_HASH=1` (default) to enforce integrity.
- For local experimentation without a hash, set `--build-arg REQUIRE_HASH=0` (NOT recommended for production CI).
- Mirror hosting: `--build-arg MULTICHAIN_DOWNLOAD_BASE=https://your.mirror.example/download`.

Example:
```bash
docker build --build-arg MULTICHAIN_VERSION=2.3.3 \
   --build-arg MULTICHAIN_SHA256="<expected_sha256>" \
   -t leodyversemilla07/multichain-base:2.3.3 ./base
```

## Quick Start (Compose Network)

Bring up the full stack (master, 2 peers, explorer):

```bash
docker compose up -d
```

Check logs for the master:

```bash
docker compose logs -f masternode
```

Access explorer UI after sync: http://localhost:2750/

Stop & remove containers (keeps named volumes):

```bash
docker compose down
```

Remove everything including volumes:

```bash
docker compose down -v
```

## Deploy Script (Optional Single Node)

The helper `deploy-multichain.sh` script can launch a single master node quickly (run with `-h` for usage). Prefer Compose for multi-node development.

## Environment Variables (Expanded)

Core (all roles unless noted):
- `CHAIN_NAME` (required for master; peers/explorer default to `procuchain` if omitted).
- `AUTO_CREATE=1|0` (base/master): create chain directory on first run if missing.
- `START_FLAGS` appended to daemon start (avoid `-daemon` inside containers except where explicitly used for explorer's local helper daemon).

Master-specific:
- `RPC_USER`, `RPC_PASSWORD`, `RPC_ALLOWIP`, `RPC_PORT` (+ each supports `*_FILE` secret indirection).
- `ANYONE_CAN_CONNECT=1|0` toggles `anyone-can-connect=true` in `params.dat` on first run.
- `P2P_PORT` patches `default-network-port` in `params.dat` and sets `-port` in `START_FLAGS`.

Peer-specific:
- `MASTER_HOST` (default `masternode`).
- `MASTER_PORT` (single preferred port) OR fallback scanning of `MASTER_PORT_CANDIDATES` list.
- `MASTER_PORT_CANDIDATES="7447 7448 7449 8000 6303 9717 8341 2661"` (adjust to reduce noise).
- `NODE_P2P_PORT` / `NODE_RPC_PORT` (set to non-zero to pin specific listen/RPC ports per peer).
- `RETRIES`, `SLEEP_SECONDS` control join loop.

Explorer-specific additions:
- `FAST_START=1|0` (skip pre-index pass for quicker UI availability).
- `COMMIT_BYTES` initial index commit size.
- `EXPLORE_FLAGS` extra args to `Mce.abe` (e.g., `--reverse`).

Secret pattern: define `RPC_PASSWORD_FILE=/run/secrets/rpc_password` (Compose) or any mounted file path; the script will overwrite the corresponding env value.

## Environment Variables (.env consumption)

Required at runtime:
* `CHAIN_NAME` (no built-in default now; choose your network name)

Additional quality-of-life:
- `QUIET_SECRET_LOGGING=1` suppresses revealing sensitive strings in logs.
- `FAST_START` (explorer) avoids an up-front partial index pass.
- `MASTER_PORT_CANDIDATES` broadens peer discovery if the canonical port is not yet open.

Applications connecting to the chain (e.g., Laravel) can use values from an `.env` file (see `.env.example`):

```env
MULTICHAIN_HOSTNAME=masternode
MULTICHAIN_HOST=127.0.0.1
MULTICHAIN_CHAIN_NAME=procuchain
MULTICHAIN_P2P_PORT=7447
MULTICHAIN_RPC_PORT=8000
MULTICHAIN_RPC_USER=multichainrpc
# MULTICHAIN_RPC_PASSWORD=REPLACE_WITH_STRONG_PASSWORD  # do NOT commit real passwords
# Prefer using file-based secrets: MULTICHAIN_RPC_PASSWORD_FILE=/run/secrets/rpc_password
```

Note: this repository has removed `MULTICHAIN_RPC_PASSWORD` from the tracked `.env` to avoid accidental commits; please use the `*_FILE` pattern or Docker secrets instead.

Adjust host/ports to match your deployment environment.

## Manual Image Build Examples

Build base image:

```bash
docker build -t leodyversemilla07/multichain-base:2.3.3 ./base
```

Build node image (uses pushed base):

```bash
docker build --build-arg MULTICHAIN_BASE_VERSION=2.3.3 -t leodyversemilla07/multichain-node:2.3.3 -f node/Dockerfile .
```

Build master (use directory as context so COPY works):

```bash
docker build --build-arg MULTICHAIN_BASE_VERSION=2.3.3 -t leodyversemilla07/multichain-master:2.3.3 master
```

Build explorer (may require legacy Python dependencies) – pin the tag to include version + ref:

```bash
docker build --build-arg MULTICHAIN_EXPLORER_REF=master \
   -t leodyversemilla07/multichain-explorer:2.3.3-mce-master explorer
```

Optionally append the short commit for an immutable tag:

```bash
COMMIT=$(git rev-parse --short HEAD)
docker tag leodyversemilla07/multichain-explorer:2.3.3-mce-master \
   leodyversemilla07/multichain-explorer:2.3.3-mce-master-$COMMIT
```

## Multi-Server Deployment (Peer Joining)

1. Launch master on Server A (Compose sets `CHAIN_NAME` automatically). Logs include a connect string like `multichaind procuchain@<IP>:7447` once ready.
2. On Server B, run a peer container referencing Server A IP & port (the entrypoint resolves hostnames and will scan candidates if needed):
```bash
docker run -d --name peer1 \
   -e CHAIN_NAME=procuchain \
   -e MASTER_HOST=<ServerA_IP_or_hostname> \
   -e MASTER_PORT=7447 \
   leodyversemilla07/multichain-node:2.3.3
```
3. Verify peers from master:
   ```bash
   docker exec -it <master_container> multichain-cli procuchain getpeerinfo
   ```

## Explorer Notes

The explorer image uses the legacy MultiChain Explorer (may require legacy Python dependencies). Runtime behavior:

* Waits for master reachability (hostname `MASTER_HOST`, port `MASTER_PORT`).
* Seeds a minimal `multichain.conf` (inserting `rpcport` and optional credentials) before starting.
* Starts a lightweight local daemon (if not already running) with `START_FLAGS` and a bounded RPC wait loop.
* Optionally generates `explorer.conf` (`GENERATE_EXPLORER_CONF=1`).
* Optional pre-index is skipped with `FAST_START=1` for near-immediate UI.
* Defensive monkey-patching guards against `NoneType` `.endswith` errors in upstream `Mce.abe`.

For production security & longevity:

- Restrict access to port 2750 behind a reverse proxy / VPN.
- Consider migrating to a maintained explorer or building a custom indexer (Python 3 / Go).
- Regenerated RPC credentials should be injected via secrets or environment instead of baking into images.

## Security & Hardening Checklist

- Use firewall rules to limit RPC (port 8000) to trusted IPs.
- Override default `rpcuser` / `rpcpassword` via environment or config volume.
- All runtime processes drop to an unprivileged `multichain` user (root only for build / initial setup).
- Use commit or version tags (avoid `latest`) for deterministic deploys.
- Enable resource limits in Compose (e.g., `deploy.resources.limits`) if using Swarm/Kubernetes.
- Inject sensitive RPC credentials via Docker secrets or *_FILE env vars (see below).
- Consider a reverse proxy with TLS termination (Caddy / Nginx) for RPC if exposed.
- Provide tarball hash (`MULTICHAIN_SHA256`) at build time for supply-chain assurance.
- Restrict explorer port (2750) access; treat legacy explorer code as untrusted surface.

## Updating Images

Recommended tagging pattern (avoid only using latest in production):

1. Base (includes MultiChain binaries)
    ```bash
    export VERSION=2.3.3
    docker build -t leodyversemilla07/multichain-base:$VERSION ./base
    docker push leodyversemilla07/multichain-base:$VERSION
    ```
2. Master / Node (pin to same base version)
    ```bash
    docker build --build-arg MULTICHAIN_BASE_VERSION=$VERSION \
       -t leodyversemilla07/multichain-master:$VERSION master
    docker build --build-arg MULTICHAIN_BASE_VERSION=$VERSION \
       -t leodyversemilla07/multichain-node:$VERSION -f node/Dockerfile .
    docker push leodyversemilla07/multichain-master:$VERSION
    docker push leodyversemilla07/multichain-node:$VERSION
    ```
3. Explorer (legacy MCE; ref can be a branch, tag, or commit of the explorer source)
    ```bash
    export EXPLORER_REF=master
    docker build --build-arg MULTICHAIN_EXPLORER_REF=$EXPLORER_REF \
       -t leodyversemilla07/multichain-explorer:${VERSION}-mce-${EXPLORER_REF} explorer
    COMMIT=$(git rev-parse --short HEAD)
    docker tag leodyversemilla07/multichain-explorer:${VERSION}-mce-${EXPLORER_REF} \
       leodyversemilla07/multichain-explorer:${VERSION}-mce-${EXPLORER_REF}-$COMMIT
    docker push leodyversemilla07/multichain-explorer:${VERSION}-mce-${EXPLORER_REF}
    docker push leodyversemilla07/multichain-explorer:${VERSION}-mce-${EXPLORER_REF}-$COMMIT
    ```
4. (Optional) Update compose file to move from an older explorer tag to the newly pushed one and commit.

Use the commit-suffixed tags for immutable deployments; keep a floating `${VERSION}-mce-${EXPLORER_REF}` for convenient development updates.

### Smoke Test Before Push

Run the provided smoke test to validate multi-service health locally:
```bash
bash scripts/smoke-test.sh            # full stack
SERVICES="masternode peer1" bash scripts/smoke-test.sh  # subset
SKIP_EXPLORER=1 bash scripts/smoke-test.sh               # skip explorer checks
```
Exits non-zero on failures (health, peer join, basic RPC). Set `NO_CLEAN=1` to retain containers for inspection.
## Secrets & *_FILE Environment Pattern

`master/entrypoint.sh` (backed by `mc-common.sh`) supports loading RPC related variables from files for use with Docker secrets or mounted files. For any of `RPC_USER`, `RPC_PASSWORD`, `RPC_ALLOWIP`, `RPC_PORT`, define a corresponding `*_FILE` env variable pointing to a file whose contents should override the plain value. Set `QUIET_SECRET_LOGGING=1` to suppress revealing file paths / passwords.

Example (Docker secret):

1. Create secret file:
   ```bash
   echo 'S3cureP@ss' > secrets/rpc_password.txt
   ```
2. Uncomment the `secrets:` section in `docker-compose.yaml` and provide path.
3. Set `RPC_PASSWORD_FILE=/run/secrets/rpc_password` (Compose sets this automatically when using secrets syntax).

At startup the entrypoint logs which variables were loaded from secret files.

Note: the repository includes `scripts/healthcheck_rpc.sh` and the explorer startup script reads the RPC password from the mounted secret path (commonly `/run/secrets/rpc_password`). Place your local secret under `secrets/rpc_password.txt` for local testing; this path is ignored by git by design.

## Healthchecks

All services define Docker healthchecks:
- Master & peer nodes: `multichain-cli <chain> getinfo` success (interval 30s, 5s timeout, 3 retries). If `CHAIN_NAME` is blank healthcheck is a no-op (master requires it; peer supplies default).
- Explorer: HTTP 200 from `/` on port 2750.

Use `docker compose ps` to view health state; automation can wait for `healthy`.

## Smoke Test Script

A lightweight script `scripts/smoke-test.sh` spins up the Compose stack, waits for health, performs a few RPC calls, then tears everything down. Run locally before pushing:

```bash
bash scripts/smoke-test.sh
```

## Explorer Deprecation & Modernization Plan

The bundled explorer relies on legacy dependencies which may require Python 2 (EOL) in some versions. Recommended migration steps:
1. Replace with a maintained fork or custom indexer in Python 3 / Go.
2. Expose a minimal REST gateway for chain queries used by UI.
3. Containerize a modern frontend (React/Vue) consuming the gateway.
4. Deprecate legacy explorer image once feature parity is reached.

Until migration, restrict explorer access to trusted networks.

Rebuild & retag with a new MultiChain version or explorer ref:

```bash
export VERSION=2.3.3
docker build --build-arg MULTICHAIN_VERSION=$VERSION -t leodyversemilla07/multichain-base:$VERSION ./base
docker push leodyversemilla07/multichain-base:$VERSION
```

Then rebuild dependent images with `--build-arg MULTICHAIN_BASE_VERSION=$VERSION` and push.

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Master image build fails copying `multichain.conf` | Wrong build context | Build with `master` dir as context. (Config is generated at runtime now.) |
| Peer cannot connect | DNS/service name mismatch | Use service name `masternode` in Compose or direct IP cross-host. |
| Explorer build fails on Python packages | Using deprecated Python 2 packages | Ensure Python 2 bootstrap step present (see explorer Dockerfile). |
| Empty explorer UI | Node still syncing or misconfigured RPC | Wait for sync; confirm `multichain.conf` has correct `rpcport`. |
| Peer slow to join | Master not yet listening on chosen port | Increase `RETRIES` / `SLEEP_SECONDS` or adjust `MASTER_PORT_CANDIDATES`. |
| Random peer ports | `NODE_P2P_PORT` unset (0) | Set `NODE_P2P_PORT` and `NODE_RPC_PORT` to pin deterministic ports. |
| Weak password printed | Forgot to set `QUIET_SECRET_LOGGING=1` | Enable to suppress plaintext in logs. |

## License

MIT License (see `LICENSE`). Previous Apache-2.0 references corrected; image labels updated accordingly.

## Original Script (Legacy) Reference

The older single-script deployment workflow is retained below for operators migrating from earlier revisions; prefer the Compose-based stack for multi-node setups.

For official protocol details see [MultiChain documentation](https://www.multichain.com/developers/).

## Project Structure

- `base/` base image (MultiChain binaries + shared scripts `mc-common.sh`, `entrypoint.sh`)
- `master/` master (creator) node (sources shared helpers)
- `node/` peer node image & resilient join script (sources shared helpers)
- `explorer/` legacy explorer (legacy dependencies)
- `deploy-multichain.sh` optional single-node helper
- `.env.example` environment sample
- `.dockerignore` build context pruning

Removed outdated `params.dat` referencing a different chain; the master image creates the `procuchain` genesis during its build.

## Service Names

`slavenode1`/`slavenode2` have been renamed to `peer1` / `peer2` for clarity and inclusivity. If you have existing named volumes, you may remove or rename them manually.

## Legacy Instructions

Legacy port and credential examples are consolidated here (no separate file yet). Modern defaults supersede these values; override cautiously.

## Quick Start

1. **Clone this repository**

   ```sh
   git clone https://github.com/leodyversemilla07/multichain-docker.git
   cd multichain-docker
   ```

2. **Make the deploy script executable:**

   ```sh
   chmod +x deploy-multichain.sh
   ```


3. **Deploy the Multichain node:**

    ```sh
    ./deploy-multichain.sh [hostname] <chain-name> [container-name] [data-volume] [p2p-port] [rpc-port] <rpcuser> <rpcpassword> [rpcallowip] [connect_peer]
    ```

    - Example (first node):
       ```sh
       ./deploy-multichain.sh myhost mychain mychain_container mychain_data 8000 8001 user pass 0.0.0.0/0
       ```
    - Example (join as peer):
       ```sh
       ./deploy-multichain.sh myhost2 mychain mychain_container2 mychain_data2 8002 9002 user pass 0.0.0.0/0 172.17.0.2:8000
       ```
       (Replace `172.17.0.2:8000` with the P2P address from the first node's logs)
    - Use `-` for hostname if you want to skip setting it.
    - **Defaults:**
       - `chain-name`: `yourchain`
       - `container-name`: `multichain`
       - `data-volume`: `multichain_data`
       - `p2p-port`: `8000`
       - `rpc-port`: `8001`
       - `rpcuser`: `rpcuser`
       - `rpcpassword`: `rpcpassword`
       - `rpcallowip`: `0.0.0.0/0`
    - The optional `rpcallowip` argument lets you control which IPs can access the RPC interface (for security, restrict this in production).
    - The optional `connect_peer` argument lets you join this node to an existing peer (multi-node setup).

4. **Environment Variables**
   - See `.env.example` for sample connection settings (useful for Laravel or other apps):
     ```env
     MULTICHAIN_HOSTNAME=multichain
     MULTICHAIN_HOST=128.199.67.162
     MULTICHAIN_CHAIN_NAME=yourchain
     MULTICHAIN_P2P_PORT=8000
     MULTICHAIN_RPC_PORT=8001
     MULTICHAIN_RPC_USER=rpcuser
     MULTICHAIN_RPC_PASSWORD=rpcpassword
     ```
   - `MULTICHAIN_HOSTNAME` is the internal Docker hostname (for use within Docker networks).
   - `MULTICHAIN_HOST` is the external/public IP or DNS name for connecting from outside Docker (e.g., from your app server or the internet).

## Docker Details

- The Docker image is built from Ubuntu 22.04 and installs Multichain 2.3.3.
- Data is persisted in a Docker volume (default: `multichain_data`, configurable via the deploy script).
- Ports `8000` (P2P) and `8001` (RPC) are exposed by default, but you can customize them.

## Example Docker Commands

**Build the image manually:**

```sh
docker build -t my-multichain:2.3.3 .
```

**Run the container manually:**

```sh
docker run -d \
   --name mychain_container \
   -v mychain_data:/root/.multichain \
   -p 8000:8000 -p 8001:8001 \
   my-multichain:2.3.3 \
   yourchain -rpcuser=rpcuser -rpcpassword=rpcpassword -daemon
```

## Multi-Server Deployment: Connecting Nodes Across Servers

To deploy one Multichain node on Server A and another on Server B, and connect them as peers:

### 1. Prepare Both Servers

- Install Docker and copy this `multichain-docker` project to both servers.

### 2. Deploy the First Node (Server A)

- On Server A, run the deploy script to create the chain and start the first node:
   ```sh
   ./deploy-multichain.sh nodeA mychain mychain_containerA mychain_dataA 8000 9001 userA passA 0.0.0.0/0
   ```
- Note the public IP of Server A and the P2P port (e.g., 8000).

### 3. Get the Connect String for Peers

- On Server A, get the connect string for other nodes:
   ```sh
   docker logs mychain_containerA
   ```
- Look for a line like:
   ```
   multichaind mychain@<ServerA_IP>:<P2P_PORT>
   ```

### 4. Deploy the Second Node (Server B) and Connect to Server A

- On Server B, run the deploy script, passing the connect string from Server A as the last argument:
   ```sh
   ./deploy-multichain.sh nodeB mychain mychain_containerB mychain_dataB 8000 9002 userB passB 0.0.0.0/0 <ServerA_IP>:8000
   ```
- This will start node B and connect it to node A as a peer.

### 5. Open Firewall Ports

- Ensure both servers allow inbound traffic on their P2P and RPC ports (e.g., 8000, 9001, 9002).

### 6. Validate Peer Connection

- On both servers, use the `getpeerinfo` RPC call to confirm they see each other as peers:
   ```sh
   curl --user <rpcuser>:<rpcpassword> --data-binary '{"method":"getpeerinfo","params":[],"id":1}' -H 'content-type:text/plain;' http://127.0.0.1:<rpcport>
   ```

**Notes:**
- Both servers must be able to reach each other’s P2P port (default 8000).
- Use the connect string from the first node’s logs when starting the second node.
- Credentials and chain name must match on both nodes.



---

## Security Notes

- Use the `rpcallowip` argument in the deploy script to restrict which IPs can access the RPC port. For production, only allow trusted sources.
- The `.env.example` now includes both internal (`MULTICHAIN_HOSTNAME`) and external (`MULTICHAIN_HOST`) host variables for clarity in different deployment scenarios.

For more information, see the official [Multichain documentation](https://www.multichain.com/developers/).
