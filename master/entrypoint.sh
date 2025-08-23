#!/usr/bin/env bash
set -euo pipefail

source /usr/local/bin/mc-common.sh

: "${CHAIN_NAME:=}"
: "${RPC_USER:=multichainrpc}"
: "${RPC_PASSWORD:=}"
: "${RPC_ALLOWIP:=127.0.0.1}"
: "${RPC_PORT:=8000}"
: "${RPC_BIND:=0.0.0.0}"
: "${ANYONE_CAN_CONNECT:=1}"
: "${P2P_PORT:=7447}"
export START_FLAGS="${START_FLAGS:--printtoconsole -shrinkdebugfilesize}"

DATA_ROOT="/home/multichain/.multichain"
CHAIN_DIR="${DATA_ROOT}/${CHAIN_NAME}"
CONF_FILE="${CHAIN_DIR}/multichain.conf"
PARAMS_FILE="$CHAIN_DIR/params.dat"

mc_load_file_env
if [[ -z "$CHAIN_NAME" ]]; then
  mc_log "[MASTER][ERROR] CHAIN_NAME not set. Provide -e CHAIN_NAME=<name>."; exit 1
fi
mc_log "[MASTER] Preparing master node for chain '${CHAIN_NAME}'"
mc_ensure_chain_dir "$CHAIN_NAME" "$DATA_ROOT"

# Patch params.dat for stable ports / connectivity if present
if [[ -f "$PARAMS_FILE" ]]; then
  patch_line(){ local key="$1" val="$2"; if grep -q "^${key}" "$PARAMS_FILE"; then sed -i "s/^${key}.*/${key} = ${val}/" "$PARAMS_FILE" || true; fi; }
  patch_line default-network-port "$P2P_PORT"
  patch_line default-rpc-port "$RPC_PORT"
  [[ "$ANYONE_CAN_CONNECT" == "1" ]] && patch_line anyone-can-connect true
  mc_log "[MASTER] params.dat state:"; grep -E '^(default-network-port|default-rpc-port|anyone-can-connect)' "$PARAMS_FILE" | sed 's/^/[MASTER]   /' || true
else
  mc_log "[MASTER][WARN] params.dat not found yet (will be created at genesis)"
fi

# Normalize RPC_ALLOWIP list (split on comma/semicolon/whitespace) and drop empties
read -r -a RPC_ALLOWIP_LIST < <(echo "$RPC_ALLOWIP" | tr ',;' ' ')
tmp_list=()
for ip in "${RPC_ALLOWIP_LIST[@]}"; do
  ip_trimmed=$(echo "$ip" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [[ -n "$ip_trimmed" ]] && tmp_list+=("$ip_trimmed")
done
RPC_ALLOWIP_LIST=("${tmp_list[@]}")

# Ensure multichain.conf exists and matches desired RPC settings (support multiple rpcallowip lines)
mkdir -p "$CHAIN_DIR"
if [[ ! -f "$CONF_FILE" ]]; then
  if [[ -z $RPC_PASSWORD ]]; then
    RPC_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)
    mc_log "[MASTER] Generated RPC password"
  fi
  mc_log "[MASTER] Writing new multichain.conf (rpcallowip entries: ${RPC_ALLOWIP_LIST[*]})"
  tmp_conf=$(mktemp)
  {
    echo "rpcuser=${RPC_USER}"
    echo "rpcpassword=${RPC_PASSWORD}"
    echo "rpcport=${RPC_PORT}"
    for ip in "${RPC_ALLOWIP_LIST[@]}"; do
      [[ -n "$ip" ]] && echo "rpcallowip=${ip}"
    done
  } >"$tmp_conf" && mv "$tmp_conf" "$CONF_FILE"
else
  # Patch existing file if values diverge
  changed=0
  patch_conf(){ local key="$1" desired="$2"; if grep -q "^${key}=" "$CONF_FILE"; then
        current=$(grep "^${key}=" "$CONF_FILE" | head -1 | cut -d= -f2-)
        if [[ "$current" != "$desired" ]]; then
          sed -i "s#^${key}=.*#${key}=${desired}#" "$CONF_FILE" && changed=1
        fi
      else
        echo "${key}=${desired}" >>"$CONF_FILE" && changed=1
      fi }
  patch_conf rpcuser "$RPC_USER"
  [[ -n "$RPC_PASSWORD" ]] && patch_conf rpcpassword "$RPC_PASSWORD"
  patch_conf rpcport "$RPC_PORT"
  # Extract existing rpcallowip lines, splitting any comma-separated lists into individual entries
  mapfile -t existing_raw < <(grep '^rpcallowip=' "$CONF_FILE" | cut -d= -f2- | tr ',;' '\n' | sed '/^$/d' || true)
  # Build associative sets for comparison (order insensitive)
  declare -A want_set have_set
  for ip in "${RPC_ALLOWIP_LIST[@]}"; do want_set["$ip"]=1; done
  for ip in "${existing_raw[@]}"; do have_set["$ip"]=1; done
  rebuild=0
  # Detect commas in any original line (invalid format for MultiChain)
  if grep -q '^rpcallowip=.*,' "$CONF_FILE"; then rebuild=1; fi
  # Size / membership comparison
  if [[ ${#existing_raw[@]} -ne ${#RPC_ALLOWIP_LIST[@]} ]]; then rebuild=1; else
    for ip in "${RPC_ALLOWIP_LIST[@]}"; do [[ -z ${have_set[$ip]:-} ]] && { rebuild=1; break; }; done
  fi
  if (( rebuild )); then
    # Rebuild rpcallowip entries atomically
    tmp_conf=$(mktemp)
    sed '/^rpcallowip=/d' "$CONF_FILE" >"$tmp_conf" || true
    for ip in "${RPC_ALLOWIP_LIST[@]}"; do
      [[ -n "$ip" ]] && echo "rpcallowip=${ip}" >>"$tmp_conf"
    done
    mv "$tmp_conf" "$CONF_FILE" && mc_log "[MASTER] Rewrote rpcallowip lines: ${RPC_ALLOWIP_LIST[*]}"
    changed=1
  fi
  if (( changed )); then
    mc_log "[MASTER] Patched existing multichain.conf to reflect current environment"
  else
    mc_log "[MASTER] Using existing multichain.conf (no changes needed)"
  fi
fi

# Force deterministic START_FLAGS and bind RPC to configured address
export START_FLAGS="-printtoconsole -shrinkdebugfilesize -port=${P2P_PORT} -rpcport=${RPC_PORT} -rpcbind=${RPC_BIND}"
mc_log "[MASTER] START_FLAGS=${START_FLAGS} (rpcbind=${RPC_BIND})"

# Export expected hash if available for base entrypoint self-check
if [[ -f "${BASE_ENTRYPOINT_SHA256_FILE:-}" ]]; then
  export BASE_ENTRYPOINT_SHA256=$(<"$BASE_ENTRYPOINT_SHA256_FILE")
fi

exec /usr/local/bin/entrypoint.base.sh
