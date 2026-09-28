#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_SERVER="${LLAMA_SERVER:-${PROJECT_HOME}/llama.cpp/build/bin/llama-server}"
MODEL_DIR="${QIANFAN_MODEL_DIR:-${PROJECT_HOME}/models/qianfan-ocr}"
MODEL_FILE="${QIANFAN_MODEL_FILE:-}"
QUANT="${QIANFAN_QUANT:-Q8_0}"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-32768}"
N_GPU_LAYERS="${N_GPU_LAYERS:-999}"
N_PREDICT="${N_PREDICT:-8192}"

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

if [[ -z "${MODEL_FILE}" ]]; then
    MODEL_FILE="$(find "${MODEL_DIR}" -maxdepth 1 -type f -iname "*${QUANT}*.gguf" -print -quit)"
fi
if [[ -z "${MODEL_FILE}" || ! -f "${MODEL_FILE}" ]]; then
    echo "ERROR: Qianfan-OCR GGUF not found in ${MODEL_DIR}" >&2
    echo "Run ./installations/install_qianfan_ocr.sh first." >&2
    exit 1
fi

if [[ "${CHECK_ONLY}" == true ]]; then
    echo "Qianfan-OCR llama.cpp prerequisites are ready."
    echo "Model:  ${MODEL_FILE}"
    echo "Server: ${LLAMA_SERVER}"
    echo "API:    http://${HOST}:${PORT}/v1"
    exit 0
fi

echo "============================================================"
echo "NexusForge Qianfan-OCR (llama.cpp)"
echo "============================================================"
echo "Model:  ${MODEL_FILE}"
echo "Context: ${CTX_SIZE} tokens"
echo "API:    http://${HOST}:${PORT}/v1"
echo

exec "${LLAMA_SERVER}" \
    -m "${MODEL_FILE}" \
    --alias qianfan-ocr \
    -c "${CTX_SIZE}" \
    -ngl "${N_GPU_LAYERS}" \
    -np 1 \
    -fa on \
    --temp 0.2 \
    --top-p 0.9 \
    --top-k 20 \
    --min-p 0.0 \
    -n "${N_PREDICT}" \
    --jinja \
    --host "${HOST}" \
    --port "${PORT}"
