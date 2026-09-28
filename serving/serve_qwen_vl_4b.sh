#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_SERVER="${LLAMA_SERVER:-${PROJECT_HOME}/llama.cpp/build/bin/llama-server}"
MODEL="${QWEN_VL_MODEL:-${PROJECT_HOME}/models/qwen-vl-4b/Qwen3VL-4B-Instruct-Q4_K_M.gguf}"
MMPROJ="${QWEN_VL_MMPROJ:-${PROJECT_HOME}/models/qwen-vl-4b/mmproj-Qwen3VL-4B-Instruct-F16.gguf}"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-32768}"
N_GPU_LAYERS="${N_GPU_LAYERS:-999}"
N_PREDICT="${N_PREDICT:-4096}"

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
    shift
fi
if (( $# > 0 )); then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: llama-server not found: ${LLAMA_SERVER}" >&2
    exit 1
fi
if [[ ! -f "${MODEL}" ]]; then
    echo "ERROR: Qwen-VL model not found: ${MODEL}" >&2
    echo "Run ./installations/install_qwen_vl_4b.sh first." >&2
    exit 1
fi
if [[ ! -f "${MMPROJ}" ]]; then
    echo "ERROR: Qwen-VL vision projector not found: ${MMPROJ}" >&2
    echo "Run ./installations/install_qwen_vl_4b.sh first." >&2
    exit 1
fi

if [[ "${CHECK_ONLY}" == true ]]; then
    echo "Qwen3-VL-4B serving prerequisites are ready."
    echo "Model:  ${MODEL}"
    echo "mmproj: ${MMPROJ}"
    echo "Server: ${LLAMA_SERVER}"
    exit 0
fi

echo "============================================================"
echo "NexusForge Qwen3-VL-4B-Instruct"
echo "============================================================"
echo "Model:   ${MODEL}"
echo "mmproj:  ${MMPROJ}"
echo "Context: ${CTX_SIZE} tokens"
echo "API:     http://${HOST}:${PORT}/v1"
echo

exec "${LLAMA_SERVER}" \
    -m "${MODEL}" \
    --mmproj "${MMPROJ}" \
    --alias qwen3-vl-4b-instruct \
    -c "${CTX_SIZE}" \
    -ngl "${N_GPU_LAYERS}" \
    -np 1 \
    -fa on \
    --temp 0.7 \
    --top-p 0.8 \
    --top-k 20 \
    --min-p 0.0 \
    --presence-penalty 1.5 \
    -n "${N_PREDICT}" \
    --jinja \
    --host "${HOST}" \
    --port "${PORT}"
