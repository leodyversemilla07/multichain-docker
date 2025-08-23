#!/usr/bin/env bash
set -euo pipefail

# MultiChain Docker setup helper (restored)
PROJECT_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$PROJECT_ROOT_DIR/.env"
COMPOSE_FILE="$PROJECT_ROOT_DIR/docker-compose.yaml"

color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }
info() { echo "$(color 36 [INFO]) $*"; }
err()  { echo "$(color 31 [ERR])  $*" >&2; }
require() { command -v "$1" >/dev/null 2>&1 || { err "Missing $1"; exit 1; }; }

generate_password() {
	if command -v openssl >/dev/null 2>&1; then openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32; else tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32; fi
}

write_env() {
	cat >"$ENV_FILE.tmp" <<EOF
# Generated $(date -u +%FT%TZ)
CHAIN_NAME=${CHAIN_NAME}
RPC_USER=${RPC_USER}
RPC_PASSWORD=${RPC_PASSWORD}
MASTER_PORT=${MASTER_PORT}
RPC_PORT=${RPC_PORT}
RPC_HOST=${RPC_HOST}
RPC_ALLOWIP=${RPC_ALLOWIP}
EOF
	mv "$ENV_FILE.tmp" "$ENV_FILE"; chmod 600 "$ENV_FILE" || true
	info "Wrote .env"
}

main(){
	require docker
	if docker compose version >/dev/null 2>&1; then COMPOSE=(docker compose); elif command -v docker-compose >/dev/null 2>&1; then COMPOSE=(docker-compose); else err "Compose not found"; exit 1; fi

	: "${CHAIN_NAME:=procuchain}"
	: "${RPC_USER:=multichainrpc}"
	: "${RPC_PASSWORD:=}"
	: "${MASTER_PORT:=7447}"
	: "${RPC_PORT:=8000}"
	: "${RPC_HOST:=masternode}"
	: "${RPC_ALLOWIP:=127.0.0.1,172.18.0.0/16}"

	if [[ -z "$RPC_PASSWORD" ]]; then RPC_PASSWORD=$(generate_password); fi
	write_env

	info "Building & starting core services"; "${COMPOSE[@]}" up -d masternode explorer
	info "Done. Explorer on port 2750; RPC on ${RPC_PORT}."
}
main "$@"
