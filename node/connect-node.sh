#!/usr/bin/env bash
set -euo pipefail

source /usr/local/bin/mc-common.sh

: "${CHAIN_NAME:=procuchain}"
: "${MASTER_HOST:=masternode}"
: "${MASTER_PORT:=}"
: "${MASTER_PORT_CANDIDATES:=7447 7448 7449 8000 6303 9717 8341 2661}"
: "${RETRIES:=30}"
: "${SLEEP_SECONDS:=2}"
: "${START_FLAGS:=-printtoconsole -shrinkdebugfilesize}"
: "${NODE_P2P_PORT:=0}"          # Optional: set to fixed listen port; 0 lets daemon choose
: "${NODE_RPC_PORT:=0}"          # Optional: set to fixed rpc port; 0 lets daemon choose

resolve_master() { getent hosts "$MASTER_HOST" | awk '{print $1}' | head -n1; }
attempt=0
ip=""
chosen_port=""
mc_log "[NODE] Candidate master ports: ${MASTER_PORT:-${MASTER_PORT_CANDIDATES}}"
while [[ $attempt -lt $RETRIES ]]; do
	if ip=$(resolve_master) && [[ -n $ip ]]; then
		ports_to_try="${MASTER_PORT:-$MASTER_PORT_CANDIDATES}"
		for p in $ports_to_try; do
			if (echo >/dev/tcp/$ip/$p) >/dev/null 2>&1; then
				chosen_port=$p
				mc_log "[NODE] Master reachable at $ip:$chosen_port"
				break 2
			fi
		done
	fi
	mc_log "[NODE] Waiting for master ($((attempt+1))/$RETRIES)"
	attempt=$((attempt+1))
	sleep "$SLEEP_SECONDS"
done
[[ -z "$ip" || -z "$chosen_port" ]] && { mc_log "[NODE][ERROR] Master not reachable on any candidate port"; exit 1; }

read -r -a FLAG_ARR <<<"${START_FLAGS}"
if [[ "$NODE_P2P_PORT" != 0 ]]; then FLAG_ARR+=( "-port=${NODE_P2P_PORT}" ); fi
if [[ "$NODE_RPC_PORT" != 0 ]]; then FLAG_ARR+=( "-rpcport=${NODE_RPC_PORT}" ); fi
mc_log "[NODE] Starting multichaind join to ${ip}:${chosen_port} (flags: ${FLAG_ARR[*]})"
exec multichaind "${CHAIN_NAME}@${ip}:${chosen_port}" "${FLAG_ARR[@]}"