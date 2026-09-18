#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LLAMA_SERVER="${PROJECT_HOME}/llama.cpp/build/bin/llama-server"

MODEL="${PROJECT_HOME}/models/gemma4-26b-a4b/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8083}"
CTX_SIZE="${CTX_SIZE:-32768}"

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: llama-server not found:"
    echo "  ${LLAMA_SERVER}"
    exit 1
fi

if [[ ! -f "${MODEL}" ]]; then
    echo "ERROR: Gemma model not found:"
    echo "  ${MODEL}"
    echo
    echo "Run ./installations/install_gemma4-26B-a4b.sh first."
    exit 1
fi

echo "============================================================"
echo "Gemma 4 26B A4B"
echo "============================================================"
echo
echo "Architecture: MoE"
echo "Total params: ~25.2B"
echo "Active params: ~3.8B/token"
echo
echo "Experts: CPU RAM"
echo "Other tensors: GPU where possible"
echo "Context: ${CTX_SIZE}"
echo "API:     http://${HOST}:${PORT}/v1"
echo

exec "${LLAMA_SERVER}" \
    -m "${MODEL}" \
    -c "${CTX_SIZE}" \
    -np 1 \
    --cpu-moe \
    -ctk q4_0 \
    -ctv q4_0 \
    -fa on \
    --jinja \
    --fit on \
    --fit-target 768 \
    --host "${HOST}" \
    --port "${PORT}"
