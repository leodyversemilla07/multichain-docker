#!/usr/bin/env bash
set -euo pipefail
# Simple stream utility: create+subscribe if missing, then publish hex data
# Usage: ./stream_helper.sh <stream> <key> <data_string>
: "${CHAIN_NAME:=procuchain}"
stream=${1:?stream name required}
key=${2:?key required}
value=${3:?data string required}
# Ensure stream exists
if ! multichain-cli "$CHAIN_NAME" liststreams | grep -q "\"name\" : \"$stream\""; then
  multichain-cli "$CHAIN_NAME" create stream "$stream" true >/dev/null
fi
multichain-cli "$CHAIN_NAME" subscribe "$stream" >/dev/null || true
# Convert value to hex without xxd dependency (portable)
# Using od (coreutils) then stripping whitespace/newlines
hex=$(printf '%s' "$value" | od -An -tx1 | tr -d ' \n')
multichain-cli "$CHAIN_NAME" publish "$stream" "$key" "$hex"
