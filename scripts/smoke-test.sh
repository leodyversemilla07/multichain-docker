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

TIMEOUT=180
SLEEP=5

log() { printf '[SMOKE] %s\n' "$*" >&2; }

# Allow selecting a subset of services (space separated) e.g. SERVICES="masternode peer1 peer2"
# If empty, all services in compose will be started.
SERVICES="${SERVICES:-}"
SKIP_EXPLORER="${SKIP_EXPLORER:-0}"

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
  now=$(date +%s)
  if (( now - start_ts > TIMEOUT )); then
    log "FAIL timeout waiting for masternode health (last: $status)"
    docker compose logs masternode || true
    exit 1
  fi
  sleep "$SLEEP"
done

docker compose exec -T masternode multichain-cli procuchain getinfo >/dev/null || { log "FAIL getinfo"; exit 1; }

# Capture initial block height
initial_height=$(docker compose exec -T masternode multichain-cli procuchain getblockcount || echo 0)
log "Initial block height: ${initial_height}"

log "Waiting for at least one peer (peer1)"
peer_wait_start=$(date +%s)
while true; do
  if docker compose exec -T masternode multichain-cli procuchain getpeerinfo | grep -qi addr; then
    log "Peer detected"
    break
  fi
  now=$(date +%s)
  if (( now - peer_wait_start > TIMEOUT )); then
    log "FAIL no peer joined in time"
    exit 1
  fi
  sleep "$SLEEP"
done

if [[ "$SKIP_EXPLORER" != "1" ]]; then
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
else
  log "Skipping explorer checks (SKIP_EXPLORER=1)"
fi

# Optional: ensure block height is numeric
if [[ $initial_height =~ ^[0-9]+$ ]]; then
  log "Block height integer validation passed"
else
  log "WARN block height not numeric: $initial_height"
fi

log "Success"
