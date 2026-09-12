#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG="${PROJECT_HOME}/config/qwen-long-context.env"

LLAMA_SERVER="${PROJECT_HOME}/llama.cpp/build/bin/llama-server"

MODEL="${PROJECT_HOME}/models/qwen-long-context/Qwen3.5-4B-Q4_K_M.gguf"


# ------------------------------------------------------------
# Load configuration
# ------------------------------------------------------------

if [[ ! -f "${CONFIG}" ]]; then
    echo "ERROR: Configuration not found:"
    echo "  ${CONFIG}"
    exit 1
fi

source "${CONFIG}"


# ------------------------------------------------------------
# Validate
# ------------------------------------------------------------

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: llama-server not found:"
    echo "  ${LLAMA_SERVER}"
    exit 1
fi

if [[ ! -f "${MODEL}" ]]; then
    echo "ERROR: model not found:"
    echo "  ${MODEL}"
    echo
    echo "Run:"
    echo "  ./install-qwen-long-context.sh"
    exit 1
fi


# ------------------------------------------------------------
# Information
# ------------------------------------------------------------

echo "============================================================"
echo "NexusForge Long Context Agent"
echo "============================================================"
echo
echo "Model:"
echo "  Qwen3.5-4B Q4_K_M"
echo
echo "Context:"
echo "  ${CONTEXT_SIZE} tokens"
echo
echo "YaRN:"
echo "  original context: ${YARN_ORIGINAL_CONTEXT}"
echo "  scaling factor:   ${YARN_FACTOR}"
echo
echo "KV cache:"
echo "  K: ${CACHE_TYPE_K}"
echo "  V: ${CACHE_TYPE_V}"
echo "  location: system RAM"
echo
echo "API:"
echo "  http://${HOST}:${PORT}/v1"
echo


# ------------------------------------------------------------
# Start server
# ------------------------------------------------------------

exec "${LLAMA_SERVER}" \
    -m "${MODEL}" \
    -ngl 999 \
    -c "${CONTEXT_SIZE}" \
    -np "${PARALLEL}" \
    --rope-scaling yarn \
    --rope-scale "${YARN_FACTOR}" \
    --yarn-orig-ctx "${YARN_ORIGINAL_CONTEXT}" \
    -ctk "${CACHE_TYPE_K}" \
    -ctv "${CACHE_TYPE_V}" \
    --no-kv-offload \
    --host "${HOST}" \
    --port "${PORT}"
