#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LLAMA_SERVER="${PROJECT_HOME}/llama.cpp/build/bin/llama-server"
MODEL="${PROJECT_HOME}/models/ornith/Ornith-1.5-9B-Q4_K_M.gguf"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-131072}"
ORNITH_REASONING_BUDGET="${ORNITH_REASONING_BUDGET:-4096}"

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: llama-server not found:"
    echo "  ${LLAMA_SERVER}"
    exit 1
fi

if [[ ! -f "${MODEL}" ]]; then
    echo "ERROR: Ornith model not found:"
    echo "  ${MODEL}"
    echo
    echo "Run ./installations/install_ornith.sh first."
    exit 1
fi

if [[ ! "${ORNITH_REASONING_BUDGET}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: ORNITH_REASONING_BUDGET must be a non-negative integer."
    exit 1
fi

echo "============================================================"
echo "Ornith-1.5-9B"
echo "============================================================"
echo "Context: ${CTX_SIZE}"
echo "Reasoning budget: ${ORNITH_REASONING_BUDGET} tokens (effort: medium)"
echo "API:     http://${HOST}:${PORT}/v1"
echo

# Precise coding profile recommended by the model authors:
# https://huggingface.co/ornith-ai/Ornith-1.5-9B#quickstart
# Keep penalties neutral so repeated code identifiers are not discouraged.
exec "${LLAMA_SERVER}" \
    -m "${MODEL}" \
    --alias ornith-1.5-9b-orchestrator \
    -c "${CTX_SIZE}" \
    -np 1 \
    -ctk q4_0 \
    -ctv q4_0 \
    -fa on \
    --temp 0.6 \
    --top-p 0.95 \
    --top-k 20 \
    --min-p 0.0 \
    --repeat-penalty 1.0 \
    --presence-penalty 0.0 \
    --frequency-penalty 0.0 \
    --reasoning-budget "${ORNITH_REASONING_BUDGET}" \
    --chat-template-kwargs '{"reasoning_effort": "medium"}' \
    --jinja \
    --fit on \
    --fit-target 512 \
    --host "${HOST}" \
    --port "${PORT}"
