#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LLAMA_SERVER="${PROJECT_HOME}/llama.cpp/build/bin/llama-server"
MODEL="${PROJECT_HOME}/models/qwen/Qwen3.5-9B-Q4_K_M.gguf"

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: llama-server not found:"
    echo "  ${LLAMA_SERVER}"
    exit 1
fi

if [[ ! -f "${MODEL}" ]]; then
    echo "ERROR: Qwen model not found:"
    echo "  ${MODEL}"
    exit 1
fi

echo "Starting Qwen3.5-9B orchestrator..."
# Keep context in sync with provider.llama-main.models.qwen-local in opencode.json.
# Q8 KV cache limits VRAM use at 16K context on the 8 GB GPU.
# Set QWEN_REASONING=off for faster visible answers without thinking.

exec "${LLAMA_SERVER}" \
    -m "${MODEL}" \
    --alias qwen-local \
    -ngl 999 \
    -c 16384 \
    -np 1 \
    -ctk q8_0 \
    -ctv q8_0 \
    -fa on \
    --reasoning "${QWEN_REASONING:-auto}" \
    --host 127.0.0.1 \
    --port 8080 \
    "$@"
