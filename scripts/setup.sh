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
MASTER_HOST=${MASTER_HOST}
RPC_HOST=${RPC_HOST}
RPC_ALLOWIP=${RPC_ALLOWIP}
EXPLORER_PORT=${EXPLORER_PORT}
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
Usage: setup.sh [--yes|-y] [--no-start] [--reset] [--services core|all] [--help]

Options:
	-y, --yes          Non-interactive: accept defaults and overwrite existing .env if present
	--no-start         Do not start docker compose services after writing .env
	--reset            Remove compose containers, named volumes and images for this project before starting (destructive)
	--services <type>  Which services to start: 'core' (masternode + explorer) or 'all' (masternode, explorer, peers). Default: all
	--env <local|prod> Choose environment defaults: 'local' (browser-accessible RPC) or 'prod' (secure defaults). Default: local
	-h, --help         Show this help
USAGE
}

main(){
	# parse args
	BATCH=0
	NO_START=0
	RESET=0
	SERVICES=all
	ENV_TYPE=local
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-y|--yes) BATCH=1; shift ;;
			--env) ENV_TYPE="$2"; shift 2 ;;
			--no-start) NO_START=1; shift ;;
			--reset) RESET=1; shift ;;
			--services) SERVICES="$2"; shift 2 ;;
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
	: "${MASTER_HOST:=masternode}"
	: "${RPC_BIND:=0.0.0.0}"
	: "${EXPLORER_PORT:=2750}"

	# set RPC defaults based on environment type if not already set
	# RPC_HOST is the hostname explorer/containers use to reach the masternode.
	# RPC_BIND is the interface the masternode will bind RPC to (0.0.0.0 for host access).
	if [[ -z "${RPC_HOST:-}" ]]; then
		if [[ "${ENV_TYPE,,}" == "prod" ]]; then
			RPC_HOST=masternode
			RPC_ALLOWIP=127.0.0.1/32
			RPC_BIND=127.0.0.1
		else
			# For local development we want explorer (in a container) to connect to the
			# masternode container by its service name, but still expose RPC on 0.0.0.0
			# so the host browser can access it via localhost:RPC_PORT.
			RPC_HOST=masternode
			RPC_ALLOWIP=0.0.0.0/0
			RPC_BIND=0.0.0.0
		fi
	fi

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
	prompt RPC_HOST "RPC host (used by explorer/browser)" "$RPC_HOST"
	prompt RPC_ALLOWIP "RPC allow IPs (comma separated)" "$RPC_ALLOWIP"
	prompt MASTER_HOST "Masternode service hostname (used by containers)" "$MASTER_HOST"
	prompt EXPLORER_PORT "Explorer UI port" "$EXPLORER_PORT"

		# write .env
		write_env

		if [[ "$NO_START" -eq 1 ]]; then
			info "--no-start supplied; skipping starting services. .env created at $ENV_FILE"
			exit 0
		fi

		# Destructive reset flow (remove containers/volumes/images used by this compose project)
		if [[ "$RESET" -eq 1 ]]; then
			if [[ "$BATCH" -eq 0 ]]; then
				read -r -p "--reset will remove containers, named volumes and images for this project. Continue? [y/N]: " yn
		RPC_BIND=${RPC_BIND}
				yn=${yn:-N}
				if [[ ! "$yn" =~ ^[Yy]$ ]]; then
					info "Reset aborted by user. Continuing without reset."
				else
					info "Performing reset: stopping and removing compose resources (containers, named volumes, images)"
					"${COMPOSE[@]}" down --rmi all --volumes --remove-orphans
					# prune build cache to ensure rebuild
					docker builder prune -f || true
				fi
			else
				info "--reset supplied and --yes: performing non-interactive reset"
				"${COMPOSE[@]}" down --rmi all --volumes --remove-orphans
				docker builder prune -f || true
			fi
		fi

		# Decide which services to start
		case "${SERVICES,,}" in
			core)
				START_CMD=("${COMPOSE[@]}" up -d masternode explorer)
				info "Starting core services (masternode + explorer)"
				;;
			all)
				START_CMD=("${COMPOSE[@]}" up -d)
				info "Starting all services defined in $COMPOSE_FILE (masternode, explorer, peer1, peer2)"
				;;
			*)
				err "Unknown services type: ${SERVICES}. Use 'core' or 'all'."; exit 2
				;;
		esac

		# Start services (rebuild if images missing)
		"${START_CMD[@]}"

		info "Startup requested. Waiting a few seconds for services to initialize..."
		sleep 3

		# Post-start verification: show basic status and recent logs for core services
		"${COMPOSE[@]}" ps
		echo
		echo "--- masternode recent logs ---"
		"${COMPOSE[@]}" logs --no-color --tail=50 masternode || true
		echo
		echo "--- explorer recent logs ---"
		"${COMPOSE[@]}" logs --no-color --tail=50 explorer || true

		info "Startup complete. Explorer should be available on port ${EXPLORER_PORT:-2750} (if exposed)."
		info "Do not share the RPC password; it is stored in $ENV_FILE with mode 600."
}

main "$@"
