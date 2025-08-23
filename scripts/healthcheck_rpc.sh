#!/bin/bash
# Healthcheck: robust RPC probe that trims CR/LF from secret and performs JSON-RPC getinfo
set -euo pipefail
RPC_PORT=${RPC_PORT:-8000}
RPC_USER=${RPC_USER:-multichainrpc}
# Read secret or fallback to env, stripping CR/LF
if [ -f /run/secrets/rpc_password ]; then
  RPC_PW=$(tr -d '\r\n' < /run/secrets/rpc_password)
else
  RPC_PW=$(echo -n "${RPC_PASSWORD:-}" | tr -d '\r\n')
fi
# Write payload to a temp file to avoid shell quoting issues
payload=$(mktemp)
cat > "$payload" <<'EOF'
{"jsonrpc":"1.0","id":"hc","method":"getinfo","params":[]}
EOF
# Call RPC; exit non-zero if no "result" found
if curl -s -S -u "${RPC_USER}:${RPC_PW}" -X POST -H 'content-type: text/plain;' --data-binary @"$payload" "http://127.0.0.1:${RPC_PORT}/" | grep -q '"result"'; then
  rm -f "$payload"
  exit 0
else
  rm -f "$payload"
  exit 1
fi
