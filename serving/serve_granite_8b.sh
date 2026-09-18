#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_SERVER="${LLAMA_SERVER:-${PROJECT_HOME}/llama.cpp/build/bin/llama-server}"
MODEL_DIR="${GRANITE_8B_MODEL_DIR:-${PROJECT_HOME}/models/granite}"
MODEL="${MODEL_DIR}/granite-4.2-8b-Q4_K_M.gguf"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
# Keep the OpenCode model context limit in sync when changing this value.
CTX_SIZE="${CTX_SIZE:-16384}"

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: llama-server not found: ${LLAMA_SERVER}" >&2
    echo "Build llama.cpp using ./installations/install.sh first." >&2
    exit 1
fi

if [[ ! -s "${MODEL}" ]]; then
    echo "ERROR: Granite 4.2 8B model not found: ${MODEL}" >&2
    echo "Run ./installations/install_granite_8b.sh first." >&2
    exit 1
fi

echo "Starting Granite 4.2 8B Q4_K_M"
echo "Context: ${CTX_SIZE} tokens; one slot; Q8 KV cache"
echo "API: http://${HOST}:${PORT}/v1"
echo "Sampling: temperature=1.0, top_p=0.95, neutral penalties"

# IBM recommends temperature=1.0 and top_p=0.95 for all tasks:
# https://huggingface.co/ibm-granite/granite-4.2-8b#generation-parameters
# Disable extra top-k/min-p filtering and keep penalties neutral for code.
# Fit GPU offload to available VRAM; fixed context is shared with opencode.json.
# Set GRANITE_REASONING=off for direct answers or pass additional server flags.
exec "${LLAMA_SERVER}" \
    -m "${MODEL}" \
    --alias granite-4.2-8b-orchestrator \
    -c "${CTX_SIZE}" \
    -np 1 \
    -ctk q8_0 \
    -ctv q8_0 \
    -fa on \
    --fit on \
    --fit-target 512 \
    --jinja \
    --reasoning "${GRANITE_REASONING:-auto}" \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 0 \
    --min-p 0.0 \
    --repeat-penalty 1.0 \
    --presence-penalty 0.0 \
    --frequency-penalty 0.0 \
    -n 8192 \
    --host "${HOST}" \
    --port "${PORT}" \
    "$@"
