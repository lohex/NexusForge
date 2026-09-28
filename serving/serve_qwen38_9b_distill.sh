#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_SERVER="${LLAMA_SERVER:-${PROJECT_HOME}/llama.cpp/build/bin/llama-server}"
MODEL_DIR="${QWEN38_MODEL_DIR:-${PROJECT_HOME}/models/qwen38-9b-distill}"
MODEL="${MODEL_DIR}/Qwen3.8-9B-Q4_K_M.gguf"
CTX_SIZE="${CTX_SIZE:-32768}"
CACHE_TYPE_K="${CACHE_TYPE_K:-q4_0}"
CACHE_TYPE_V="${CACHE_TYPE_V:-q4_0}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
MODE=run
SERVER_ARGS=()
while (( $# )); do
    case "$1" in
        --dry-run) MODE=dry-run ;;
        --check) MODE=check ;;
        --16k) CTX_SIZE=16384 ;;
        --32k) CTX_SIZE=32768 ;;
        -h|--help)
            cat <<'HELP'
Usage: ./serving/serve_qwen38_9b_distill.sh [options] [llama-server args...]

Serve Empero Qwen3.8-9B-Distill Q4_K_M using standard llama.cpp.
Defaults: 32K context, one slot, q4_0 K/V cache, flash attention,
automatic GPU fitting with 512 MiB headroom; http://127.0.0.1:8080/v1.
API model alias: qwen3.8-9b-distill

Options:
  --16k / --32k  Context size (both retain configured cache types)
  --dry-run     Print command without requiring weights or starting a server
  --check       Check local model and runtime availability without starting
  --            Pass all remaining arguments directly to llama-server

Environment:
  QWEN38_MODEL_DIR  Model directory (default: models/qwen38-9b-distill)
  LLAMA_SERVER     Server binary (default: llama.cpp/build/bin/llama-server)
  CTX_SIZE         Context tokens (default: 32768)
  CACHE_TYPE_K/V   Cache types (both default to q4_0)
  HOST / PORT      Bind address (default: 127.0.0.1 / 8080)

Sampling follows the author's model card: temp 0.6, top-p 0.95, top-k 20.
Reasoning uses the embedded chat template. Allow sufficient output tokens
in the client for thinking. Stop any other server on the same port first,
or set PORT to a different value.
HELP
            exit 0 ;;
        --) shift; SERVER_ARGS+=("$@"); break ;;
        *) SERVER_ARGS+=("$1") ;;
    esac
    shift
done

CMD=("${LLAMA_SERVER}" -m "${MODEL}" --alias qwen3.8-9b-distill
    -c "${CTX_SIZE}" -np 1 -b 512 -ub 128
    -ctk "${CACHE_TYPE_K}" -ctv "${CACHE_TYPE_V}"
    --fit on --fit-target 512 -fa on --jinja
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0
    --repeat-penalty 1.0 --presence-penalty 0.0 --frequency-penalty 0.0
    --reasoning auto --host "${HOST}" --port "${PORT}"
    "${SERVER_ARGS[@]}")
if [[ "${MODE}" == dry-run ]]; then
    printf '%q ' "${CMD[@]}"
    printf '\n'
    exit 0
fi
if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: llama-server missing: ${LLAMA_SERVER}. Run installations/install.sh." >&2
    exit 1
fi
if [[ ! -s "${MODEL}" ]]; then
    echo "ERROR: Model missing: ${MODEL}. Run installations/install_qwen38_9b_distill.sh." >&2
    exit 1
fi
if [[ "${MODE}" == check ]]; then
    echo "Model and runtime found. Architecture compatibility is checked when loading."
    exit 0
fi
echo "Starting Qwen3.8-9B-Distill: ${CTX_SIZE} context, ${CACHE_TYPE_K}/${CACHE_TYPE_V} KV cache"
echo "API: http://${HOST}:${PORT}/v1; model: qwen3.8-9b-distill"
exec "${CMD[@]}"
