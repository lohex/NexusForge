#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LLAMA_SERVER="${PROJECT_HOME}/llama.cpp/build/bin/llama-server"
MODEL="${PROJECT_HOME}/models/granite/granite-4.2-3b-Q4_K_M.gguf"

# Keep CTX_PER_SLOT in sync with granite-4.2-3b-multi in opencode.json.
PARALLEL="${PARALLEL:-2}"
CTX_PER_SLOT="${CTX_PER_SLOT:-32768}"
CACHE_TYPE_K="${CACHE_TYPE_K:-q8_0}"
CACHE_TYPE_V="${CACHE_TYPE_V:-q8_0}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"

if [[ ! "${PARALLEL}" =~ ^[1-9][0-9]*$ || ! "${CTX_PER_SLOT}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: PARALLEL and CTX_PER_SLOT must be positive integers." >&2
    exit 1
fi

CTX_SIZE=$((PARALLEL * CTX_PER_SLOT))

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: llama-server not found:"
    echo "  ${LLAMA_SERVER}"
    exit 1
fi

if [[ ! -f "${MODEL}" ]]; then
    echo "ERROR: Granite model not found:"
    echo "  ${MODEL}"
    exit 1
fi

echo "Starting Granite 4.2 3B with ${PARALLEL} parallel worker slots..."
echo "Context: ${CTX_PER_SLOT} tokens per slot (${CTX_SIZE} total)"
echo "KV cache: K=${CACHE_TYPE_K}, V=${CACHE_TYPE_V}"

# IBM recommends temperature=1.0 and top_p=0.95 across all tasks:
# https://huggingface.co/ibm-granite/granite-4.2-3b#generation-parameters
# Use neutral penalties for code and disable extra top-k/min-p filtering.
# For 3 x 32K slots on 8 GB, try PARALLEL=3 with both cache types set to q4_0.
exec "${LLAMA_SERVER}" \
    -m "${MODEL}" \
    --alias granite-4.2-3b-multi \
    -ngl 999 \
    -c "${CTX_SIZE}" \
    -np "${PARALLEL}" \
    --no-kv-unified \
    -ctk "${CACHE_TYPE_K}" \
    -ctv "${CACHE_TYPE_V}" \
    -fa on \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 0 \
    --min-p 0.0 \
    --repeat-penalty 1.0 \
    --presence-penalty 0.0 \
    --frequency-penalty 0.0 \
    --host "${HOST}" \
    --port "${PORT}" \
    "$@"
