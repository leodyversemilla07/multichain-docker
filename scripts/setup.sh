#!/usr/bin/env bash
set -euo pipefail

# Interactive MultiChain Docker setup helper
PROJECT_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$PROJECT_ROOT_DIR/.env"
COMPOSE_FILE="$PROJECT_ROOT_DIR/docker-compose.yaml"

color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }
info() { echo "$(color 36 [INFO]) $*"; }
err()  { echo "$(color 31 [ERR])  $*" >&2; }
require() { command -v "$1" >/dev/null 2>&1 || { err "Missing $1"; exit 1; }; }

generate_password() {
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32
	else
		tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
	fi
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
	mv "$ENV_FILE.tmp" "$ENV_FILE"
	chmod 600 "$ENV_FILE" || true
	info "Wrote $ENV_FILE (permissions 600)"
}

prompt() {
	local var_name="$1"; local prompt_text="$2"; local default="$3"
	local val
	if [[ -n "${!var_name:-}" ]]; then
		# honor already exported variable
		val="${!var_name}"
	else
		if [ -t 0 ]; then
			if [[ -n "$default" ]]; then
				read -r -p "$prompt_text [$default]: " val
				val="${val:-$default}"
			else
				read -r -p "$prompt_text: " val
			fi
		else
			# non-interactive fallback to default
			val="$default"
		fi
	fi
	export "$var_name"="$val"
}

prompt_password() {
	local var_name="$1"; local default_generate="$2"
	if [[ -n "${!var_name:-}" ]]; then
		return 0
	fi
	if [ -t 0 ]; then
		printf "%s" "Enter RPC password (leave empty to auto-generate): "
		# read -s to avoid echo
		IFS= read -r -s pw
		echo
		if [[ -z "$pw" ]]; then
			pw="$default_generate"
			info "Using generated password (hidden)"
		else
			printf "%s" "Confirm RPC password: "
			IFS= read -r -s pw2
			echo
			if [[ "$pw" != "$pw2" ]]; then
				err "Passwords do not match"; exit 1
			fi
		fi
	else
		pw="$default_generate"
	fi
	export "$var_name"="$pw"
}

usage(){
	cat <<'USAGE' >&2
Usage: setup.sh [--yes|-y] [--no-start] [--help]

Options:
	-y, --yes       Non-interactive: accept defaults and overwrite existing .env if present
			--no-start  Do not start docker compose services after writing .env
	-h, --help      Show this help
USAGE
}

main(){
	# parse args
	BATCH=0
	NO_START=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-y|--yes) BATCH=1; shift ;;
			--no-start) NO_START=1; shift ;;
			-h|--help) usage; exit 0 ;;
			*) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
		esac
	done
	require docker
	if docker compose version >/dev/null 2>&1; then
		COMPOSE=(docker compose)
	elif command -v docker-compose >/dev/null 2>&1; then
		COMPOSE=(docker-compose)
	else
		err "Compose not found (docker compose or docker-compose)"
		exit 1
	fi

	# sensible defaults
	: "${CHAIN_NAME:=procuchain}"
	: "${RPC_USER:=multichainrpc}"
	: "${RPC_PASSWORD:=}"
	: "${MASTER_PORT:=7447}"
	: "${RPC_PORT:=8000}"
	: "${RPC_HOST:=masternode}"
	: "${RPC_ALLOWIP:=0.0.0.0/0}"

	info "Interactive setup will collect configuration for .env"

		if [[ -f "$ENV_FILE" ]]; then
			if [[ "$BATCH" -eq 1 ]]; then
				info ".env exists but --yes supplied: overwriting $ENV_FILE"
			else
				if [ -t 0 ]; then
					read -r -p ".env already exists. Overwrite? [y/N]: " yn
					yn=${yn:-N}
					if [[ ! "$yn" =~ ^[Yy]$ ]]; then
						info "Leaving existing .env in place. To re-run interactively, remove $ENV_FILE and run setup again."
						exit 0
					fi
				else
					err ".env exists and session is non-interactive. Aborting."; exit 1
				fi
			fi
		fi

	# Prompt for values (honor exported env vars if present)
	prompt CHAIN_NAME "Chain name" "$CHAIN_NAME"
	prompt RPC_USER "RPC username" "$RPC_USER"

	# generate a password if needed
	default_pw=$(generate_password)
	prompt_password RPC_PASSWORD "$default_pw"

	prompt MASTER_PORT "Masternode port (P2P)" "$MASTER_PORT"
	prompt RPC_PORT "RPC port" "$RPC_PORT"
	prompt RPC_HOST "RPC host (used by explorer)" "$RPC_HOST"
	prompt RPC_ALLOWIP "RPC allow IPs (comma separated)" "$RPC_ALLOWIP"

		# write .env
		write_env

		if [[ "$NO_START" -eq 1 ]]; then
			info "--no-start supplied; skipping starting services. .env created at $ENV_FILE"
			exit 0
		fi

		info "Starting core services (masternode + explorer). Logs will follow in the compose output." 
		"${COMPOSE[@]}" up -d masternode explorer

		info "Startup complete. Explorer should be available on port ${EXPLORER_PORT:-2750} (if exposed)."
		info "Do not share the RPC password; it is stored in $ENV_FILE with mode 600."
}

main "$@"
