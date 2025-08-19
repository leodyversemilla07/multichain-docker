#!/usr/bin/env bash
# Common MultiChain helper functions (sourced by role-specific entrypoints)
set -euo pipefail

mc_log(){ printf '%s %s\n' "[$(date +'%H:%M:%S')]" "$*" >&2; }

mc_ensure_chain_dir(){
  local chain_name=$1
  local data_root=${2:-/home/multichain/.multichain}
  local dir="${data_root}/${chain_name}"
  if [[ ! -d $dir ]]; then
    if [[ "${AUTO_CREATE:-1}" = "1" ]]; then
      mc_log "Chain directory missing. Creating chain '${chain_name}'"
      multichain-util create "${chain_name}"
    else
      mc_log "Chain directory '${dir}' missing and AUTO_CREATE=0 (skipping creation)"; return 0
    fi
  fi
}

mc_fix_perms(){
  local target=${1:-/home/multichain}
  if [[ $(id -u) -eq 0 ]]; then
    chown -R multichain:multichain "$target" || true
  fi
}

# Load secret values from *_FILE pattern (value overrides env)
mc_load_file_env(){
  local keys=(RPC_USER RPC_PASSWORD RPC_ALLOWIP RPC_PORT)
  for key in "${keys[@]}"; do
    local file_var="${key}_FILE"
    if [[ -n "${!file_var:-}" && -f "${!file_var}" ]]; then
      local val
      val=$(<"${!file_var}")
      if [[ -n $val ]]; then
        export "$key"="$val"
        if [[ "${QUIET_SECRET_LOGGING:-0}" != "1" ]]; then
          mc_log "Loaded secret for ${key} from ${!file_var}"
        else
          mc_log "Loaded secret for ${key} (path suppressed)"
        fi
      fi
    fi
  done
}
