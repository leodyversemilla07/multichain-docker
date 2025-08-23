#!/usr/bin/env bash
set -euo pipefail
# Generate a new address and grant baseline permissions (receive,send)
: "${CHAIN_NAME:=procuchain}"
: "${GRANT_PERMS:=receive,send}"
addr=$(multichain-cli "$CHAIN_NAME" getnewaddress)
multichain-cli "$CHAIN_NAME" grant "$addr" "$GRANT_PERMS" >/dev/null
echo "$addr"
