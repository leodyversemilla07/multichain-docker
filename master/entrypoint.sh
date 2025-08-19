#!/usr/bin/env bash
set -euo pipefail

source /usr/local/bin/mc-common.sh

: "${CHAIN_NAME:=}"
: "${RPC_USER:=multichainrpc}"
: "${RPC_PASSWORD:=}"
: "${RPC_ALLOWIP:=127.0.0.1}"
: "${RPC_PORT:=8000}"
: "${ANYONE_CAN_CONNECT:=1}"   # Default to open connectivity for internal dev network
: "${P2P_PORT:=7447}"          # Stable P2P port
: "${P2P_PORT:=7447}"  # Desired stable network (P2P) port (will patch params.dat on first run)
export START_FLAGS="${START_FLAGS:--printtoconsole -shrinkdebugfilesize}"

DATA_ROOT="/home/multichain/.multichain"
CHAIN_DIR="${DATA_ROOT}/${CHAIN_NAME}"
CONF_FILE="${CHAIN_DIR}/multichain.conf"

mc_load_file_env
if [[ -z "$CHAIN_NAME" ]]; then
  mc_log "[MASTER][ERROR] CHAIN_NAME not set. Provide -e CHAIN_NAME=<name>."; exit 1
fi
mc_log "[MASTER] Preparing master node for chain '${CHAIN_NAME}'"
mc_ensure_chain_dir "$CHAIN_NAME" "$DATA_ROOT"

# Unconditionally patch params.dat BEFORE any daemon start.
PARAMS_FILE="$CHAIN_DIR/params.dat"
if [[ -f "$PARAMS_FILE" ]]; then
  patch_needed=0
  patch_line(){
    local key="$1" val="$2"
    if grep -q "^${key}" "$PARAMS_FILE"; then
      sed -i "s/^${key}.*/${key} = ${val}/" "$PARAMS_FILE" && patch_needed=1 || true
    fi
  }
  patch_line default-network-port "$P2P_PORT"
  patch_line default-rpc-port "$RPC_PORT"
  if [[ "$ANYONE_CAN_CONNECT" == "1" ]]; then
    patch_line anyone-can-connect true
  fi
  if (( patch_needed )); then
    mc_log "[MASTER] params.dat patched to enforce ports & connectivity:";
    grep -E '^(default-network-port|default-rpc-port|anyone-can-connect)' "$PARAMS_FILE" | sed 's/^/[MASTER]   /' >&2 || true
  else
    mc_log "[MASTER] params.dat already aligned"
  fi
else
  mc_log "[MASTER][WARN] params.dat not found (unexpected before genesis)"
fi

# Force deterministic START_FLAGS overriding any inherited value.
export START_FLAGS="-printtoconsole -shrinkdebugfilesize -port=${P2P_PORT} -rpcport=${RPC_PORT}"
mc_log "[MASTER] START_FLAGS=${START_FLAGS}"

#!/usr/bin/env bash
set -euo pipefail

source /usr/local/bin/mc-common.sh

: "${CHAIN_NAME:=}"
: "${RPC_USER:=multichainrpc}"
: "${RPC_PASSWORD:=}"
: "${RPC_ALLOWIP:=127.0.0.1}"
: "${RPC_PORT:=8000}"
export START_FLAGS="${START_FLAGS:--printtoconsole -shrinkdebugfilesize}"

DATA_ROOT="/home/multichain/.multichain"
CHAIN_DIR="${DATA_ROOT}/${CHAIN_NAME}"
CONF_FILE="${CHAIN_DIR}/multichain.conf"

mc_load_file_env
if [[ -z "$CHAIN_NAME" ]]; then
  mc_log "[MASTER][ERROR] CHAIN_NAME not set. Provide -e CHAIN_NAME=<name>."; exit 1
fi
mc_log "[MASTER] Preparing master node for chain '${CHAIN_NAME}'"
mc_ensure_chain_dir "$CHAIN_NAME" "$DATA_ROOT"

if [[ ! -f $CONF_FILE ]]; then
  mc_log "[MASTER] Generating multichain.conf (rpcallowip=${RPC_ALLOWIP})"
  mkdir -p "$CHAIN_DIR"
  # Auto-generate a secure password if not provided
  if [[ -z $RPC_PASSWORD ]]; then
    RPC_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)
    if [[ "${QUIET_SECRET_LOGGING:-0}" != "1" ]]; then
      mc_log "[MASTER] Auto-generated RPC password (store this securely): $RPC_PASSWORD"
    else
      mc_log "[MASTER] Auto-generated RPC password (suppressed; see multichain.conf)"
    fi
  fi
  cat >"$CONF_FILE" <<EOF
rpcuser=${RPC_USER}
rpcpassword=${RPC_PASSWORD}
rpcallowip=${RPC_ALLOWIP}
rpcport=${RPC_PORT}
EOF
else
  mc_log "[MASTER] Using existing multichain.conf"
fi

# Export expected hash if available for base entrypoint self-check
if [[ -f "${BASE_ENTRYPOINT_SHA256_FILE:-}" ]]; then
  export BASE_ENTRYPOINT_SHA256=$(<"$BASE_ENTRYPOINT_SHA256_FILE")
fi

# Delegate actual daemon startup to the original base entrypoint for consistency
exec /usr/local/bin/entrypoint.base.sh
