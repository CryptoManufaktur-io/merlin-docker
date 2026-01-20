#!/usr/bin/env bash
set -Eeuo pipefail

compose_service=""
container=""
local_rpc=""
public_rpc=""
block_lag=""
env_file=""
no_install=0

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  --compose-service <service>  Run curl/jq inside docker compose service"
  echo "  --container <container>      Run curl/jq inside docker container"
  echo "  --local-rpc <url>            Local RPC URL (default: http://localhost:\${RPC_PORT:-8123})"
  echo "  --public-rpc <url>           Public RPC URL (default: https://rpc.merlinchain.io)"
  echo "  --block-lag <blocks>         Allowed block lag before syncing (default: 5)"
  echo "  --env-file <path>            Env file to load (default: .env if present)"
  echo "  --no-install                 Do not install curl/jq in container"
  echo "  -h, --help                   Show this help"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose-service)
      compose_service="${2:-}"
      shift 2
      ;;
    --container)
      container="${2:-}"
      shift 2
      ;;
    --local-rpc)
      local_rpc="${2:-}"
      shift 2
      ;;
    --public-rpc)
      public_rpc="${2:-}"
      shift 2
      ;;
    --block-lag)
      block_lag="${2:-}"
      shift 2
      ;;
    --env-file)
      env_file="${2:-}"
      shift 2
      ;;
    --no-install)
      no_install=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

load_env_file() {
  local file="$1"
  if [ -f "$file" ]; then
    local line key value
    while IFS= read -r line || [ -n "$line" ]; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        export "$key=$value"
      fi
    done < "$file"
  fi
}

if [ -n "$env_file" ]; then
  load_env_file "$env_file"
elif [ -f ".env" ]; then
  load_env_file ".env"
fi

if [ -z "$block_lag" ]; then
  block_lag="${BLOCK_LAG:-5}"
fi

if [ -z "$local_rpc" ]; then
  if [ -n "${LOCAL_RPC:-}" ]; then
    local_rpc="$LOCAL_RPC"
  else
    local_rpc="http://localhost:${RPC_PORT:-8123}"
  fi
fi

if [ -z "$public_rpc" ]; then
  if [ -n "${PUBLIC_RPC:-}" ]; then
    public_rpc="$PUBLIC_RPC"
  else
    public_rpc="https://rpc.merlinchain.io"
  fi
fi

__exec() {
  if [ -n "$compose_service" ]; then
    docker compose exec -T "$compose_service" "$@"
  elif [ -n "$container" ]; then
    docker exec -i "$container" "$@"
  else
    "$@"
  fi
}

ensure_container_deps() {
  if __exec sh -c "command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1"; then
    return 0
  fi
  if [ "$no_install" -eq 1 ]; then
    echo "curl/jq missing in container. Install them or omit --no-install."
    exit 2
  fi
  if __exec sh -c "command -v apt-get >/dev/null 2>&1"; then
    __exec sh -c "apt-get update && apt-get install -y curl jq"
  elif __exec sh -c "command -v apk >/dev/null 2>&1"; then
    __exec sh -c "apk add --no-cache curl jq"
  else
    echo "Unsupported package manager in container (need apt-get or apk)."
    exit 2
  fi
}

ensure_host_deps() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required on the host."
    exit 2
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required on the host."
    exit 2
  fi
}

if [ -n "$compose_service" ] || [ -n "$container" ]; then
  ensure_container_deps
else
  ensure_host_deps
fi

rpc_call() {
  local url="$1"
  local method="$2"
  local params="$3"
  local filter="$4"
  local payload

  payload=$(printf '{"jsonrpc":"2.0","id":1,"method":"%s","params":%s}' "$method" "$params")
  if [ -n "$compose_service" ] || [ -n "$container" ]; then
    printf '%s' "$payload" \
      | __exec sh -c "curl -sS -X POST -H 'content-type: application/json' --data-binary @- '$url'" \
      | __exec jq -r "$filter"
  else
    curl -sS -X POST -H 'content-type: application/json' --data-binary "$payload" "$url" \
      | jq -r "$filter"
  fi
}

hex_to_dec() {
  local hex="$1"
  hex="${hex#0x}"
  if [ -z "$hex" ]; then
    echo ""
    return
  fi
  echo "$((16#$hex))"
}

dec_to_hex() {
  printf "0x%x" "$1"
}

block_number_filter='(.result // .blockNumber // .data // empty)'
block_hash_filter='(.result.hash // .result.blockHash // .blockHash // .hash // .data.hash // .data.blockHash // empty)'
sync_filter='(.result // .syncing // .data)'

local_height_hex=$(rpc_call "$local_rpc" "eth_blockNumber" "[]" "$block_number_filter" || true)
public_height_hex=$(rpc_call "$public_rpc" "eth_blockNumber" "[]" "$block_number_filter" || true)
local_sync_raw=$(rpc_call "$local_rpc" "eth_syncing" "[]" "$sync_filter" || true)

if [ -z "$local_height_hex" ] || [ "$local_height_hex" = "null" ]; then
  echo "Failed to read local block height from $local_rpc"
  exit 2
fi
if [ -z "$public_height_hex" ] || [ "$public_height_hex" = "null" ]; then
  echo "Failed to read public block height from $public_rpc"
  exit 2
fi

local_height=$(hex_to_dec "$local_height_hex")
public_height=$(hex_to_dec "$public_height_hex")

if [ -z "$local_height" ] || [ -z "$public_height" ]; then
  echo "Failed to parse block heights."
  exit 2
fi

syncing_status="false"
if [ -n "$local_sync_raw" ] && [ "$local_sync_raw" != "false" ] && [ "$local_sync_raw" != "null" ]; then
  syncing_status="true"
fi

lag=$((public_height - local_height))
abs_lag=$lag
if [ "$abs_lag" -lt 0 ]; then
  abs_lag=$(( -1 * abs_lag ))
fi

compare_height=$local_height
if [ "$public_height" -lt "$compare_height" ]; then
  compare_height=$public_height
fi

compare_hex=$(dec_to_hex "$compare_height")
local_hash=$(rpc_call "$local_rpc" "eth_getBlockByNumber" "[\"$compare_hex\", false]" "$block_hash_filter" || true)
public_hash=$(rpc_call "$public_rpc" "eth_getBlockByNumber" "[\"$compare_hex\", false]" "$block_hash_filter" || true)

diverged=0
if [ -n "$local_hash" ] && [ -n "$public_hash" ] && [ "$local_hash" != "null" ] && [ "$public_hash" != "null" ]; then
  if [ "$local_hash" != "$public_hash" ]; then
    diverged=1
  fi
fi

echo "Local height: $local_height"
echo "Public height: $public_height"
echo "Lag: $lag"
if [ "$syncing_status" = "true" ] || [ "$abs_lag" -gt "$block_lag" ]; then
  echo "Status: syncing"
else
  echo "Status: caught up"
fi
if [ "$diverged" -eq 1 ]; then
  echo "Chain mismatch at height $compare_height"
fi

if [ "$diverged" -eq 1 ]; then
  exit 2
fi
if [ "$syncing_status" = "true" ] || [ "$abs_lag" -gt "$block_lag" ]; then
  exit 1
fi
exit 0
