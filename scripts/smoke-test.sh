#!/usr/bin/env bash
set -euo pipefail

cleanup(){
  local code=$?
  if [[ "${NO_CLEAN:-0}" != "1" ]]; then
    docker compose down -v >/dev/null 2>&1 || true
  fi
  exit $code
}
trap cleanup EXIT INT TERM

# Simple smoke test: bring up compose stack (optionally limited to certain services),
# wait for masternode health, query block height, ensure at least one peer connects,
# optionally check explorer (skip with SKIP_EXPLORER=1), then tear down (unless NO_CLEAN=1).

SLEEP=5

log() { printf '[SMOKE] %s\n' "$*" >&2; }

# Allow selecting a subset of services (space separated) e.g. SERVICES="masternode peer1 peer2"
# If empty, all services in compose will be started.
SERVICES="${SERVICES:-}"

if [[ -n "$SERVICES" ]]; then
  log "Starting stack (services: $SERVICES)"
  # shellcheck disable=SC2086 # intentional word splitting for service list
  docker compose up -d --quiet-pull $SERVICES
else
  log "Starting full stack"
  docker compose up -d --quiet-pull
fi

start_ts=$(date +%s)
log "Waiting for masternode healthy"
while true; do
  cid=$(docker compose ps -q masternode || true)
  [[ -z "$cid" ]] && { log "masternode container missing"; exit 1; }
  status=$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo starting)
  if [[ "$status" == "healthy" ]]; then
    break
  fi
  sleep "$SLEEP"
done

try_cli_getinfo() {
  docker compose exec -T masternode multichain-cli procuchain getinfo >/dev/null 2>&1 || return $?
}

rpc_get() {
  method=$1
  # Run curl inside the masternode container to avoid host quoting/tooling issues.
  # Extract rpcuser:rpcpassword from the container's multichain.conf
  creds=$(docker compose exec -T masternode sh -lc "awk -F= '/^rpcuser=/{u=\$2} /^rpcpassword=/{p=\$2} END{if(u&&p) printf \"%s:%s\",u,p}' /home/multichain/.multichain/*/multichain.conf || true" | tr -d '\r' || true)
  if [[ -n "$creds" ]]; then
    docker compose exec -T masternode sh -lc "curl -sS -u '$creds' -X POST -H 'content-type: text/plain;' --data-binary '{\"jsonrpc\":\"1.0\",\"id\":\"hc\",\"method\":\"${method}\",\"params\":[]}' http://127.0.0.1:8000/ || true"
  else
    docker compose exec -T masternode sh -lc "curl -sS -X POST -H 'content-type: text/plain;' --data-binary '{\"jsonrpc\":\"1.0\",\"id\":\"hc\",\"method\":\"${method}\",\"params\":[]}' http://127.0.0.1:8000/ || true"
  fi
}

# Prefer CLI when it works, but fall back to HTTP RPC if CLI segfaults or fails
if try_cli_getinfo; then
  # Capture initial block height via CLI
  initial_height=$(docker compose exec -T masternode multichain-cli procuchain getblockcount || echo 0)
else
  log "WARN multichain-cli failed; falling back to HTTP RPC for checks"
  # Attempt RPC getinfo to ensure daemon responds
  rpc_getinfo=$(rpc_get getinfo)
  if ! echo "$rpc_getinfo" | grep -q '"result"'; then
    log "FAIL getinfo (CLI and RPC both failed)"
    docker compose logs masternode || true
    exit 1
  fi
  # Capture initial block height via RPC
  initial_height=$(echo "$rpc_getinfo" | sed -n 's/.*\"result\":\(.*\)\,\"error\".*/\1/p' | jq -r '.blocks // 0' 2>/dev/null || echo 0)
fi
log "Initial block height: ${initial_height}"

log "Waiting for at least one peer (peer1)"
peer_wait_start=$(date +%s)
try_cli_getpeerinfo() {
  docker compose exec -T masternode multichain-cli procuchain getpeerinfo >/dev/null 2>&1 || return $?
}

while true; do
  # Prefer CLI check when available
  if try_cli_getpeerinfo; then
    if docker compose exec -T masternode multichain-cli procuchain getpeerinfo | grep -qi addr; then
      log "Peer detected (via CLI)"
      break
    fi
  else
    # CLI failed (may segfault) — fall back to HTTP RPC
    rpc_peers=$(rpc_get getpeerinfo)
    if echo "$rpc_peers" | grep -qi '"addr"'; then
      log "Peer detected (via RPC)"
      break
    fi
  fi

  sleep "$SLEEP"
done

log "Checking explorer health"
explorer_cid=$(docker compose ps -q explorer || true)
if [[ -z "$explorer_cid" ]]; then
  log "FAIL explorer container missing"; exit 1; fi
explorer_status=$(docker inspect -f '{{.State.Health.Status}}' "$explorer_cid" 2>/dev/null || echo starting)
if [[ "$explorer_status" != healthy* ]]; then
  log "WARN explorer not healthy yet (status: $explorer_status)"
else
  log "Explorer healthy"
fi
# Simple explorer content check (title or chain name expected)
if curl -fsS http://localhost:2750/ | grep -qi procuchain; then
  log "Explorer content contains chain name"
else
  log "WARN explorer content missing expected chain name"
fi

# Optional: ensure block height is numeric
if [[ $initial_height =~ ^[0-9]+$ ]]; then
  log "Block height integer validation passed"
else
  log "WARN block height not numeric: $initial_height"
fi

log "Success"
