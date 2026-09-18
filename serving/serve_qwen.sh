#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LLAMA_SERVER="${PROJECT_HOME}/llama.cpp/build/bin/llama-server"
MODEL="${PROJECT_HOME}/models/qwen/Qwen3.5-9B-Q4_K_M.gguf"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-16384}"
CACHE_TYPE_K="${CACHE_TYPE_K:-q8_0}"
CACHE_TYPE_V="${CACHE_TYPE_V:-q8_0}"
SERVER_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --32k|--ctx32k|--context-32k)
            CTX_SIZE=32768
            CACHE_TYPE_K=q4_0
            CACHE_TYPE_V=q4_0
            shift
            ;;
        -h|--help)
            cat <<'USAGE'
Usage: serving/serve_qwen.sh [--32k] [llama-server args...]

Options:
  --32k, --ctx32k, --context-32k
      Start Qwen3.5-9B with 32K context and q4_0 KV cache.

Environment:
  CTX_SIZE      Override context size manually. Default: 16384
  CACHE_TYPE_K  Override K cache type manually. Default: q8_0
  CACHE_TYPE_V  Override V cache type manually. Default: q8_0
  HOST          Bind host. Default: 127.0.0.1
  PORT          Bind port. Default: 8080
USAGE
            exit 0
            ;;
        *)
            SERVER_ARGS+=("$1")
            shift
            ;;
    esac
done

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
echo "Context: ${CTX_SIZE} tokens; one slot; ${CACHE_TYPE_K}/${CACHE_TYPE_V} KV cache"
echo "API: http://${HOST}:${PORT}/v1"
# Keep context in sync with qwen3.5-9b-orchestrator in opencode.json.
# Q8 KV cache limits VRAM use at 16K context on the 8 GB GPU.
# Use --32k to switch to 32K context with q4_0 KV cache for test runs.
# Set QWEN_REASONING=off for faster visible answers without thinking.
# Sampling uses Qwen's precise coding profile for thinking mode:
# https://huggingface.co/Qwen/Qwen3.5-9B#best-practices
# Keep penalties neutral so repeated code identifiers are not discouraged.

exec "${LLAMA_SERVER}" \
    -m "${MODEL}" \
    --alias qwen3.5-9b-orchestrator \
    -ngl 999 \
    -c "${CTX_SIZE}" \
    -np 1 \
    -ctk "${CACHE_TYPE_K}" \
    -ctv "${CACHE_TYPE_V}" \
    -fa on \
    --temp 0.6 \
    --top-p 0.95 \
    --top-k 20 \
    --min-p 0.0 \
    --repeat-penalty 1.0 \
    --presence-penalty 0.0 \
    --frequency-penalty 0.0 \
    --reasoning "${QWEN_REASONING:-auto}" \
    --host "${HOST}" \
    --port "${PORT}" \
    "${SERVER_ARGS[@]}"
