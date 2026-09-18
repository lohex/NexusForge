#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG="${PROJECT_HOME}/config/qwen-long-context.env"
LLAMA_SERVER="${PROJECT_HOME}/llama.cpp/build/bin/llama-server"
MODEL="${PROJECT_HOME}/models/qwen-long-context/Qwen3.5-4B-Q4_K_M.gguf"

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
    shift
fi

if (( $# > 0 )); then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi

if [[ ! -f "${CONFIG}" ]]; then
    echo "ERROR: Configuration not found:"
    echo "  ${CONFIG}"
    exit 1
fi

source "${CONFIG}"

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: llama-server not found:"
    echo "  ${LLAMA_SERVER}"
    exit 1
fi

if [[ ! -f "${MODEL}" ]]; then
    echo "ERROR: model not found:"
    echo "  ${MODEL}"
    exit 1
fi

if [[ "${CHECK_ONLY}" == true ]]; then
    echo "Qwen long-context serving prerequisites are ready."
    echo "Model:  ${MODEL}"
    echo "Config: ${CONFIG}"
    echo "Server: ${LLAMA_SERVER}"
    exit 0
fi

echo "============================================================"
echo "NexusForge Long Context Agent"
echo "============================================================"
echo
echo "Model:   Qwen3.5-4B Q4_K_M"
echo "Context: ${CONTEXT_SIZE} tokens"
echo "YaRN:    factor ${YARN_FACTOR}"
echo "KV:      ${CACHE_TYPE_K}/${CACHE_TYPE_V} in system RAM"
echo "API:     http://${HOST}:${PORT}/v1"
echo

exec "${LLAMA_SERVER}" \
    -m "${MODEL}" \
    --alias qwen3.5-4b-long-context \
    -c "${CONTEXT_SIZE}" \
    -np "${PARALLEL}" \
    -b 256 \
    -ub 64 \
    -fa on \
    --rope-scaling yarn \
    --rope-scale "${YARN_FACTOR}" \
    --yarn-orig-ctx "${YARN_ORIGINAL_CONTEXT}" \
    -ctk "${CACHE_TYPE_K}" \
    -ctv "${CACHE_TYPE_V}" \
    --no-kv-offload \
    --fit on \
    --fit-target 768 \
    --jinja \
    --host "${HOST}" \
    --port "${PORT}"
