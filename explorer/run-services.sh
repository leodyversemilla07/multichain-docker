#!/usr/bin/env bash
set -euo pipefail
set -o errtrace
trap 'mc_log "[EXPLORER][DEBUG] Error at line $LINENO exit $?"' ERR

# Reuse common helpers (mc_log) from base image.
if [[ -f /usr/local/bin/mc-common.sh ]]; then
	# shellcheck disable=SC1091
	source /usr/local/bin/mc-common.sh
else
	mc_log() { echo "$@" >&2; }
fi

# ==========================
# Environment Configuration
# ==========================
# Core runtime variables
: "${CHAIN_NAME:=procuchain}"
: "${MASTER_HOST:=masternode}"
# RPC host used for direct explorer JSON-RPC calls (default to master host)
: "${RPC_HOST:=${MASTER_HOST}}"
# Use runtime overrides from compose; defaults align with masternode service
: "${MASTER_PORT:=7447}"
: "${RPC_PORT:=8000}"
: "${PUBLIC_RPCHOST:=}"
: "${RETRIES:=60}"
: "${SLEEP_SECONDS:=2}"
: "${EXPLORER_PORT:=2750}"
: "${EXPLORER_BIND:=0.0.0.0}"
: "${GENERATE_EXPLORER_CONF:=1}"   # Set to 0 to use pre-baked explorer.conf
: "${START_FLAGS:=-shrinkdebugfilesize}" # Additional multichaind flags (do not include -daemon)
: "${COMMIT_BYTES:=100000}"          # Initial indexing batch size
: "${EXPLORE_FLAGS:=}"               # Extra flags for Mce.abe (e.g. --reverse)
: "${FAST_START:=1}"                 # If 1 skip pre-index --no-serve pass
: "${START_LOCAL_NODE:=0}"           # If 1 start lightweight local node (not recommended w/ shared volume)

mc_log "[EXPLORER][DEBUG] FAST_START=${FAST_START} MASTER_PORT=${MASTER_PORT} RPC_PORT=${RPC_PORT} START_LOCAL_NODE=${START_LOCAL_NODE} RPC_HOST=${RPC_HOST}"

# Prefer Docker secret for RPC password when present (trim CR/LF from Windows-created files)
if [[ -f /run/secrets/rpc_password ]]; then
	RPC_PASSWORD=$(tr -d '\r\n' < /run/secrets/rpc_password)
	mc_log "[EXPLORER][DEBUG] Loaded RPC_PASSWORD from Docker secret (length=$(echo -n \"$RPC_PASSWORD\" | wc -c))"
fi

mc_log "[EXPLORER] Launching explorer for chain '${CHAIN_NAME}' (port ${EXPLORER_PORT})"

# Ensure we operate from a writable home directory so relative paths (if any) land here.
cd /home/multichain || mc_log "[EXPLORER][WARN] Failed to cd to /home/multichain"

# Normalize HOME (upstream image sets this, but be defensive)
HOME_DIR="${HOME:-/home/multichain}"
CHAIN_DIR="${HOME_DIR}/.multichain/${CHAIN_NAME}"

# --------------------------
# Wait for master reachability (mirrors logic in connect-node.sh)
# --------------------------
resolve_master() { getent hosts "$MASTER_HOST" | awk '{print $1}' | head -n1; }
attempt=0
ip=""
while [[ $attempt -lt $RETRIES ]]; do
	if ip=$(resolve_master) && [[ -n $ip ]]; then
		if (echo >/dev/tcp/$ip/$MASTER_PORT) >/dev/null 2>&1; then
			mc_log "[EXPLORER] Master reachable at $ip:$MASTER_PORT"
			break
		fi
	fi
	mc_log "[EXPLORER] Waiting for master ($((attempt+1))/$RETRIES)"
	attempt=$((attempt+1))
	sleep "$SLEEP_SECONDS"
done
[[ -z "$ip" ]] && { mc_log "[EXPLORER][ERROR] Master not reachable"; exit 1; }

# --------------------------
# Prepare configuration early (needed before reliable RPC checks)
# --------------------------
CONF_DIR="$CHAIN_DIR"
CONF_FILE="${CONF_DIR}/multichain.conf"
mkdir -p "$CONF_DIR"
touch "$CONF_FILE"
if ! grep -q '^rpcport=' "$CONF_FILE" 2>/dev/null; then
    echo "rpcport=${RPC_PORT}" >> "$CONF_FILE"
fi
# Inject optional RPC credentials/allow list if provided (matches masternode env)
if [[ -n "${RPC_USER:-}" ]] && ! grep -q '^rpcuser=' "$CONF_FILE" 2>/dev/null; then echo "rpcuser=${RPC_USER}" >> "$CONF_FILE"; fi
if [[ -n "${RPC_PASSWORD:-}" ]] && ! grep -q '^rpcpassword=' "$CONF_FILE" 2>/dev/null; then echo "rpcpassword=${RPC_PASSWORD}" >> "$CONF_FILE"; fi
if [[ -n "${RPC_ALLOWIP:-}" ]] && ! grep -q '^rpcallowip=' "$CONF_FILE" 2>/dev/null; then echo "rpcallowip=${RPC_ALLOWIP}" >> "$CONF_FILE"; fi
# If we are not starting a local node, force rpcconnect to remote master host (avoids default 127.0.0.1)
if [[ "${START_LOCAL_NODE}" != "1" ]]; then
	if grep -q '^rpcconnect=' "$CONF_FILE" 2>/dev/null; then
		sed -i "s/^rpcconnect=.*/rpcconnect=${RPC_HOST}/" "$CONF_FILE"
	else
		echo "rpcconnect=${RPC_HOST}" >> "$CONF_FILE"
	fi
fi
GLOBAL_CONF="${HOME_DIR}/.multichain/multichain.conf"
cp "$CONF_FILE" "$GLOBAL_CONF" 2>/dev/null || true

# --------------------------
# Optional local node startup (disabled by default)
# --------------------------
if [[ "$START_LOCAL_NODE" == "1" ]]; then
	if ! multichain-cli "$CHAIN_NAME" getinfo >/dev/null 2>&1; then
		read -r -a FLAG_ARR <<<"${START_FLAGS}"
		mc_log "[EXPLORER] Starting local multichaind daemon (flags: ${START_FLAGS})"
		multichaind "${CHAIN_NAME}@${ip}:${MASTER_PORT}" -daemon "${FLAG_ARR[@]}" || true
		RPC_MAX_ATTEMPTS=$((RETRIES/2))
		rpc_attempt=0
		while [[ $rpc_attempt -lt $RPC_MAX_ATTEMPTS ]]; do
			if multichain-cli "$CHAIN_NAME" getinfo >/dev/null 2>&1; then
				mc_log "[EXPLORER] RPC ready after $((rpc_attempt+1)) attempt(s)"
				break
			fi
			mc_log "[EXPLORER][DEBUG] Waiting for RPC ($((rpc_attempt+1))/$RPC_MAX_ATTEMPTS)"
			sleep "$SLEEP_SECONDS"
			rpc_attempt=$((rpc_attempt+1))
		done
		if ! multichain-cli "$CHAIN_NAME" getinfo >/dev/null 2>&1; then
			mc_log "[EXPLORER][WARN] RPC not confirmed ready after $RPC_MAX_ATTEMPTS attempts; continuing"
		fi
	else
		mc_log "[EXPLORER] multichaind already running; skipping start (START_LOCAL_NODE=1)"
	fi
else
	mc_log "[EXPLORER] START_LOCAL_NODE=0 (using remote RPC ${RPC_HOST}:${RPC_PORT})"
fi

# --------------------------
# Generate explorer configuration dynamically (optional)
# Produce an INI with [main], [chains], and per-chain sections expected by
# multichain-explorer-2's readconf.py
# --------------------------
EXPLORER_CONF="/home/multichain/explorer.ini"
if [[ "$GENERATE_EXPLORER_CONF" == "1" ]]; then
	# Ensure env fallbacks exist to avoid writing empty keys
	: "${RPC_USER:=}"; : "${RPC_PASSWORD:=}"; : "${RPC_HOST:=masternode}"; : "${RPC_PORT:=8000}"
	# PUBLIC_RPCHOST (optional) controls the browser-visible RPC URL (e.g. localhost:8000)
	# Use it when present to avoid exposing container-internal hostnames to clients.
	: "${PUBLIC_RPCHOST:=}"

	# Build server-side RPC URL (used by the service to contact the masternode)
	SERVER_RPC_RAW="${RPC_HOST}"
	if [[ "${SERVER_RPC_RAW,,}" == http://* || "${SERVER_RPC_RAW,,}" == https://* ]]; then
		SERVER_RPCHOST="${SERVER_RPC_RAW}"
	else
		if [[ "${SERVER_RPC_RAW}" == *":"* ]]; then
			SERVER_RPCHOST="http://${SERVER_RPC_RAW}"
		else
			SERVER_RPCHOST="http://${SERVER_RPC_RAW}:${RPC_PORT}"
		fi
	fi

	# Build public (browser) RPCHOST used in explorer.ini. Prefer PUBLIC_RPCHOST when set.
	if [[ -n "${PUBLIC_RPCHOST}" ]]; then
		PUBLIC_RPC_RAW="${PUBLIC_RPCHOST}"
		if [[ "${PUBLIC_RPC_RAW,,}" == http://* || "${PUBLIC_RPC_RAW,,}" == https://* ]]; then
			RPCHOST="${PUBLIC_RPC_RAW}"
		else
			if [[ "${PUBLIC_RPC_RAW}" == *":"* ]]; then
				RPCHOST="http://${PUBLIC_RPC_RAW}"
			else
				RPCHOST="http://${PUBLIC_RPC_RAW}:${RPC_PORT}"
			fi
		fi
	else
		RPC_HOST_RAW="${RPC_HOST}"
		if [[ "${RPC_HOST_RAW,,}" == http://* || "${RPC_HOST_RAW,,}" == https://* ]]; then
			RPCHOST="${RPC_HOST_RAW}"
		else
			if [[ "${RPC_HOST_RAW}" == *":"* ]]; then
				RPCHOST="http://${RPC_HOST_RAW}"
			else
				RPCHOST="http://${RPC_HOST_RAW}:${RPC_PORT}"
			fi
		fi
	fi

	# Build INI but omit empty rpcuser/rpcpassword lines to avoid invalid keys
	{
		echo "; Autogenerated explorer.ini (CHAIN_NAME=${CHAIN_NAME})"
		echo "[main]"
		echo "port = ${EXPLORER_PORT}"
		echo "host = ${EXPLORER_BIND}"
		echo "dbtype = sqlite3"
		echo "connect-args = /home/multichain/${CHAIN_NAME}.explorer.sqlite"
		echo "chainurl = http://localhost:${EXPLORER_PORT}/chain/${CHAIN_NAME}/"
		echo
		echo "[chains]"
		echo "${CHAIN_NAME} = on"
		echo
		echo "[${CHAIN_NAME}]"
	echo "name = ${CHAIN_NAME}"
		# Use the server-side RPC host for backend connectivity. Write a
		# scheme-prefixed host (no port) because the explorer's multichain
		# client appends the rpcport when building the final URL. This keeps
		# the server-side health checks (which use ${SERVER_RPCHOST}) separate
		# from the INI value used by the explorer library.
		echo "rpchost = http://${RPC_HOST}"
		# If a PUBLIC_RPCHOST is set, also add a commented hint for debugging.
		if [[ -n "${PUBLIC_RPCHOST:-}" ]]; then
			echo "; public_rpchost = ${PUBLIC_RPCHOST}"
		fi
		echo "rpcport = ${RPC_PORT}"
		if [[ -n "${RPC_USER}" ]]; then echo "rpcuser = ${RPC_USER}"; fi
		if [[ -n "${RPC_PASSWORD}" ]]; then echo "rpcpassword = ${RPC_PASSWORD}"; fi
		echo "; Use remote RPC (no datadir here for remote chains)"
	} > "$EXPLORER_CONF"

	mc_log "[EXPLORER] Generated explorer configuration at $EXPLORER_CONF"
else
	mc_log "[EXPLORER] Using baked explorer.conf (GENERATE_EXPLORER_CONF=0)"
fi

# --------------------------
# Wait for server-side RPC to be reachable and accept auth (non-fatal but retries)
# Use SERVER_RPCHOST (built above) for backend checks while RPCHOST controls the
# browser-visible URL returned in explorer.ini.
# --------------------------
SERVER_RPC_URL="${SERVER_RPCHOST%/}"
mc_log "[EXPLORER][DEBUG] Checking server RPC at ${SERVER_RPC_URL}"
rpc_try=0
max_rpc_tries=$RETRIES
while [[ $rpc_try -lt $max_rpc_tries ]]; do
	# Use curl with basic auth if credentials provided, else attempt unauthenticated
	if [[ -n "${RPC_USER:-}" && -n "${RPC_PASSWORD:-}" ]]; then
		resp=$(curl -sS -u "${RPC_USER}:${RPC_PASSWORD}" -X POST -H 'content-type: text/plain;' --data-binary '{"jsonrpc":"1.0","id":"hc","method":"getinfo","params":[]}' "${SERVER_RPC_URL}" 2>/dev/null || true)
	else
		resp=$(curl -sS -X POST -H 'content-type: text/plain;' --data-binary '{"jsonrpc":"1.0","id":"hc","method":"getinfo","params":[]}' "${SERVER_RPC_URL}" 2>/dev/null || true)
	fi
	# Simple check: look for a top-level "result" key in the JSON response
	if echo "$resp" | grep -q '"result"\s*:'; then
		mc_log "[EXPLORER] RPC ready at ${SERVER_RPC_URL}"
		break
	fi
	rpc_try=$((rpc_try+1))
	mc_log "[EXPLORER][DEBUG] Waiting for RPC readiness ($rpc_try/$max_rpc_tries)"
	sleep "$SLEEP_SECONDS"
done


# --------------------------
# Initial index pass (non-fatal) then serve
# Use python3 invocation and prefer installed explorer-2 under /opt
# --------------------------
PYTHON_CMD="python3"
if ! command -v ${PYTHON_CMD} >/dev/null 2>&1; then
	PYTHON_CMD="python"
fi

if [[ "$FAST_START" != "1" ]]; then
	mc_log "[EXPLORER][DEBUG] Pre-index pass (FAST_START=0)"
	${PYTHON_CMD} -m Mce.abe --config "$EXPLORER_CONF" --commit-bytes "$COMMIT_BYTES" --no-serve || true
else
	mc_log "[EXPLORER][DEBUG] Skipping pre-index (FAST_START=1)"
fi
mc_log "[EXPLORER] Starting explorer web server on ${EXPLORER_BIND}:${EXPLORER_PORT}"

# If /opt/multichain-explorer-2 exists, switch to that directory before launching
if [[ -d "/opt/multichain-explorer-2" ]]; then
	cd /opt/multichain-explorer-2 || true
fi

# Optional debug probe: print python info when DEBUG=1 (keeps runtime logs quieter)
if [[ "${DEBUG:-0}" == "1" ]]; then
	${PYTHON_CMD} - <<'EOF'
import sys, pkgutil
print('[EXPLORER][DEBUG] Python version:', sys.version)
print('[EXPLORER][DEBUG] sys.path:')
for p in sys.path:
	print('  -', p)
names = {name for _, name, _ in pkgutil.iter_modules()}
print('[EXPLORER][DEBUG] explorer module present?', 'explorer' in names)
EOF
fi
# Split explorer flags safely
read -r -a EXPLORE_ARR <<<"${EXPLORE_FLAGS}"

# If the modern multichain-explorer-2 package isn't installed in site-packages,
# prefer the source under /opt/multichain-explorer-2 (bundled in the image).
if ! ${PYTHON_CMD} -c "import importlib,sys; importlib.import_module('explorer')" >/dev/null 2>&1; then
	if [[ -d "/opt/multichain-explorer-2" ]]; then
		export PYTHONPATH="/opt/multichain-explorer-2:${PYTHONPATH:-}"
		cd /opt/multichain-explorer-2 || true
		mc_log "[EXPLORER][DEBUG] Using local /opt/multichain-explorer-2 source"
	else
		mc_log "[EXPLORER][WARN] explorer package not found; starting may fail"
	fi
fi

exec ${PYTHON_CMD} -m explorer "$EXPLORER_CONF" "${EXPLORE_ARR[@]}"