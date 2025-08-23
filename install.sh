#!/usr/bin/env bash
set -euo pipefail

# MultiChain Docker installer (bash)
# - Writes .env (prefills from existing .env when present)
# - Generates RPC password if missing
# - Optionally starts core services (masternode + explorer) via Docker Compose

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$REPO_ROOT/.env"

usage(){
  cat <<EOF
Usage: $0 [options]

Options:
  -c, --chain NAME       Chain name (defaults to existing .env or 'procuchain')
  -u, --rpc-user USER    RPC user (defaults to existing .env or 'multichainrpc')
  -p, --rpc-pass PASS    RPC password (if omitted one will be generated)
  -s, --start            Start core services (masternode + explorer) after writing .env
  -f, --force            Overwrite existing .env without prompting
  -h, --help             Show this help

Examples:
  # interactive (prompts for missing values)
  ./install.sh --start

  # non-interactive
  ./install.sh -c procuchain -u multichainrpc -p S3cret -s

EOF
}

read_env(){
  declare -gA EXISTING_ENV
  if [[ -f "$ENV_FILE" ]]; then
    while IFS='=' read -r key value; do
      key="${key// /}"
      # strip surrounding double-quotes if present
      value="${value%\"}"
      value="${value#\"}"
      [[ -z "$key" || "$key" =~ ^# ]] && continue
      EXISTING_ENV["$key"]="$value"
    done < <(grep -E '^[[:alnum:]_]+=|^#' "$ENV_FILE" || true)
  fi
}

generate_password(){
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32
  else
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
  fi
}

find_compose(){
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    return 1
  fi
}

# Defaults
CHAIN_NAME=""
RPC_USER=""
RPC_PASSWORD=""
RPC_HOST="masternode"
RPC_ALLOWIP="127.0.0.1 172.18.0.0/16"
RPC_PORT=8000
MASTER_PORT=7447
START_SERVICES=0
FORCE=0

# Parse args
while [[ ${#} -gt 0 ]]; do
  case "$1" in
    -c|--chain) CHAIN_NAME="$2"; shift 2;;
    -u|--rpc-user) RPC_USER="$2"; shift 2;;
    -p|--rpc-pass) RPC_PASSWORD="$2"; shift 2;;
    -s|--start) START_SERVICES=1; shift;;
    -f|--force) FORCE=1; shift;;
    -h|--help) usage; exit 0;;
    --) shift; break;;
    -*) echo "Unknown option: $1"; usage; exit 1;;
    *) break;;
  esac
done

read_env

: "${CHAIN_NAME:=${EXISTING_ENV[CHAIN_NAME]:-procuchain}}"
: "${RPC_USER:=${EXISTING_ENV[RPC_USER]:-multichainrpc}}"
: "${RPC_PASSWORD:=${EXISTING_ENV[RPC_PASSWORD]:-}}"

if [[ -z "$RPC_PASSWORD" ]]; then
  if [[ $FORCE -eq 1 || ! -t 0 ]]; then
    RPC_PASSWORD=$(generate_password)
    echo "[INFO] Generated RPC password"
  else
    read -r -p "Enter RPC password (leave blank to auto-generate): " input_pw
    if [[ -n "$input_pw" ]]; then
      RPC_PASSWORD="$input_pw"
    else
      RPC_PASSWORD=$(generate_password)
      echo "[INFO] Generated RPC password"
    fi
  fi
fi

echo "[INFO] Preparing .env at $ENV_FILE"

if [[ -f "$ENV_FILE" && $FORCE -ne 1 ]]; then
  read -r -p "A .env already exists at $ENV_FILE. Overwrite? (y/N): " ans
  if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
    echo "[INFO] Aborting: .env not overwritten. Rerun with --force to bypass."; exit 0
  fi
fi

cat > "$ENV_FILE.tmp" <<EOF
# Generated $(date -u +%FT%TZ)
CHAIN_NAME=$CHAIN_NAME
RPC_USER=$RPC_USER
RPC_PASSWORD=$RPC_PASSWORD
MASTER_PORT=$MASTER_PORT
RPC_PORT=$RPC_PORT
RPC_HOST=$RPC_HOST
RPC_ALLOWIP=$RPC_ALLOWIP
EOF

mv "$ENV_FILE.tmp" "$ENV_FILE"
chmod 600 "$ENV_FILE" || true
echo "[INFO] .env written"

if [[ $START_SERVICES -eq 1 ]]; then
  compose_cmd="$(find_compose || true)"
  if [[ -z "$compose_cmd" ]]; then
    echo "[ERROR] Docker Compose not found (need 'docker compose' or 'docker-compose')."; exit 2
  fi
  echo "[INFO] Starting core services: masternode + explorer"
  if [[ "$compose_cmd" == "docker compose" ]]; then
    docker compose up -d masternode explorer
  else
    docker-compose up -d masternode explorer
  fi
  echo "[INFO] Compose up requested. Use 'docker compose ps' and 'docker compose logs -f masternode' to follow startup."
else
  echo "[INFO] Installer finished. Rerun with --start to bring up core services."
fi

exit 0
