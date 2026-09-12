#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LLAMA_SERVER="${PROJECT_HOME}/llama.cpp/build/bin/llama-server"
MODEL="${PROJECT_HOME}/models/granite/granite-4.2-3b-Q4_K_M.gguf"

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

echo "Starting Granite 4.2 3B with two parallel worker slots..."

exec "${LLAMA_SERVER}" \
    -m "${MODEL}" \
    -ngl 999 \
    -c 65536 \
    -np 2 \
    -ctk q8_0 \
    -ctv q8_0 \
    -fa on \
    --host 127.0.0.1 \
    --port 8080
