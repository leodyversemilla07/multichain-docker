#!/usr/bin/env bash
# Common MultiChain helper functions (sourced by role-specific entrypoints)
set -euo pipefail

# Simple timestamped logger to stderr
mc_log(){ printf '%s %s\n' "[$(date +'%Y-%m-%dT%H:%M:%S%z')]" "$*" >&2; }

# Ensure the chain data directory exists. If AUTO_CREATE=1 attempt to create it
# using multichain-util; return non-zero if missing and not created.
mc_ensure_chain_dir(){
  local chain_name=${1:?missing chain_name}
  local data_root=${2:-/home/multichain/.multichain}
  local dir="${data_root}/${chain_name}"

  if [[ -d "$dir" ]]; then
    return 0
  fi

  if [[ "${AUTO_CREATE:-1}" = "1" ]]; then
    mc_log "Chain directory missing. Creating chain '${chain_name}'"
    if ! multichain-util create "${chain_name}"; then
      mc_log "ERROR: failed to create chain '${chain_name}' via multichain-util"
      return 2
    fi
    # ensure dir now exists
    if [[ ! -d "$dir" ]]; then
      mc_log "ERROR: expected chain dir '$dir' after creation but it does not exist"
      return 3
    fi
    return 0
  fi

  mc_log "Chain directory '${dir}' missing and AUTO_CREATE=0 (skipping creation)"
  return 1
}

# Fix ownership if running as root
mc_fix_perms(){
  local target=${1:-/home/multichain}
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    chown -R multichain:multichain "$target" || true
  fi
}

# Load secret values from *_FILE pattern (value overrides env). Trim CR/LF and surrounding
# whitespace to be robust to Windows-created secret files. By default loads a small set of
# RPC-related vars but can be extended by passing a list of keys as arguments.
mc_load_file_env(){
  local keys=("RPC_USER" "RPC_PASSWORD" "RPC_ALLOWIP" "RPC_PORT")
  if [[ $# -gt 0 ]]; then
    keys=("$@")
  fi

  for key in "${keys[@]}"; do
    local file_var="${key}_FILE"
    local file_path="${!file_var:-}"
    if [[ -n "$file_path" && -f "$file_path" ]]; then
      # Trim CR and LF and surrounding whitespace
      local val
      val=$(tr -d '\r' <"$file_path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
      if [[ -n "$val" ]]; then
        export "$key"="$val"
        if [[ "${QUIET_SECRET_LOGGING:-0}" != "1" ]]; then
          mc_log "Loaded secret for ${key} from ${file_path}"
        else
          mc_log "Loaded secret for ${key} (path suppressed)"
        fi
      fi
    fi
  done
}
