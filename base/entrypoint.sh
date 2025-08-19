#!/usr/bin/env bash
set -euo pipefail

source /usr/local/bin/mc-common.sh

# Optional integrity check for callers that stash a copy (e.g., master wrapper)
if [[ -n "${BASE_ENTRYPOINT_SHA256:-}" ]]; then
  current_hash=$(sha256sum "$0" | awk '{print $1}')
  if [[ "$current_hash" != "$BASE_ENTRYPOINT_SHA256" ]]; then
    mc_log "WARNING: Base entrypoint hash mismatch (expected $BASE_ENTRYPOINT_SHA256 got $current_hash)"
  fi
fi

CHAIN_NAME="${CHAIN_NAME:-}"
START_FLAGS="${START_FLAGS:--printtoconsole -shrinkdebugfilesize}"
DATA_ROOT="/home/multichain/.multichain"

if [[ $# -gt 0 ]]; then
  mc_log "Executing custom command: $*"
  exec "$@"
fi

if [[ -z $CHAIN_NAME ]]; then
  mc_log "ERROR: CHAIN_NAME not set and no command provided. Set -e CHAIN_NAME=<name>."; exit 1
fi

mc_ensure_chain_dir "$CHAIN_NAME" "$DATA_ROOT"
mc_fix_perms /home/multichain

read -r -a FLAG_ARR <<<"${START_FLAGS}"
mc_log "Starting multichaind for chain '${CHAIN_NAME}' (flags: ${START_FLAGS})"
exec multichaind "${CHAIN_NAME}" "${FLAG_ARR[@]}"
