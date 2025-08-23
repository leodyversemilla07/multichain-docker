#!/bin/sh
# Healthcheck script for masternode RPC. Runs inside container at /scripts/healthcheck_rpc.sh
# Uses RPC_USER/RPC_PASSWORD env vars if provided.
RPC_URL="http://127.0.0.1:8000/"

# Try an authenticated RPC call if credentials exist, otherwise anonymous.
if [ -n "$RPC_USER" ]; then
  resp=$(curl -sS --max-time 5 -u "$RPC_USER:$RPC_PASSWORD" -X POST -H 'content-type: text/plain;' --data-binary '{"jsonrpc":"1.0","id":"hc","method":"getinfo","params":[]}' "$RPC_URL" || true)
else
  resp=$(curl -sS --max-time 5 -X POST -H 'content-type: text/plain;' --data-binary '{"jsonrpc":"1.0","id":"hc","method":"getinfo","params":[]}' "$RPC_URL" || true)
fi

# Succeed if response contains "result", otherwise print response and fail
echo "$resp" | grep -q '"result"' >/dev/null 2>&1 || (echo "$resp" >&2; exit 1)
exit 0
