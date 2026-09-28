#!/usr/bin/env bash
set -euo pipefail

# https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf
# Text-only serving. PTQ1_0 requires PrismML's Hadamard-aware llama.cpp fork.
PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${BONSAI_MODEL_DIR:-${PROJECT_HOME}/models/bonsai-2-27b}"
MODEL="${MODEL_DIR}/Ternary-Bonsai-2-27B-PTQ1_0.gguf"
LLAMA_DIR="${BONSAI_LLAMA_DIR:-${PROJECT_HOME}/llama.cpp-bonsai}"
RUNTIME_DIR="${BONSAI_RUNTIME_DIR:-${LLAMA_DIR}/build/bin}"
LLAMA_SERVER="${RUNTIME_DIR}/llama-server"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
# Keep the default context in sync with the Bonsai model in opencode.json.
CTX_SIZE="${CTX_SIZE:-32768}"
BONSAI_REASONING_EFFORT="${BONSAI_REASONING_EFFORT:-medium}"
MODE=run

case "${1:-}" in
    -h|--help)
        cat <<'HELP'
Usage: ./serving/serve_bonsai_2_27b.sh [--dry-run|--check] [llama-server options...]

Standalone diagnostic server for Ternary Bonsai 2 27B PTQ1_0.
For Bonsai plus other agents, use ./serving/serve_router.sh.
Default: text-only, localhost:8080, 32K context, one slot, Q4 KV cache,
medium reasoning effort and the model author's thinking-mode sampling.
Stop any other server on the same port first, or set PORT=8081.

  --dry-run  Print the command without requiring downloads or starting a server
  --check    Check model presence and runtime loading without starting a server

Environment: BONSAI_MODEL_DIR, BONSAI_LLAMA_DIR, BONSAI_RUNTIME_DIR, HOST, PORT, CTX_SIZE,
             BONSAI_REASONING_EFFORT (medium or xhigh).
Extra arguments go to llama-server, e.g. --reasoning-budget 4096.
Install first: ./installations/install_bonsai_2_27b.sh
HELP
        exit 0 ;;
    --dry-run) MODE=dry-run; shift ;;
    --check) MODE=check; shift ;;
esac

if [[ ! "${CTX_SIZE}" =~ ^[1-9][0-9]{0,5}$ ]] || (( CTX_SIZE > 262144 )); then
    echo "ERROR: CTX_SIZE must be an integer between 1 and 262144." >&2
    exit 2
fi
case "${BONSAI_REASONING_EFFORT}" in
    medium|xhigh) ;;
    *) echo "ERROR: BONSAI_REASONING_EFFORT must be medium or xhigh." >&2; exit 2 ;;
esac

ARGS=(
    -m "${MODEL}" --alias bonsai-2-27b-ternary
    -c "${CTX_SIZE}" -np 1 -b 512 -ub 128
    -ctk q4_0 -ctv q4_0 -fa on
    --fit on --fit-target 768
    --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.05
    --repeat-penalty 1.0 --presence-penalty 0.0 --frequency-penalty 0.0
    --jinja --chat-template-kwargs "{\"reasoning_effort\":\"${BONSAI_REASONING_EFFORT}\"}"
    --host "${HOST}" --port "${PORT}"
)
export LD_LIBRARY_PATH="${RUNTIME_DIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

if [[ "${MODE}" == dry-run ]]; then
    printf '%q ' "${LLAMA_SERVER}" "${ARGS[@]}" "$@"
    printf '\n'
    exit 0
fi
if [[ ! -x "${LLAMA_SERVER}" || ! -s "${MODEL}" ]]; then
    echo "ERROR: Missing PrismML runtime or Bonsai model." >&2
    echo "Run ./installations/install_bonsai_2_27b.sh first." >&2
    exit 1
fi
if [[ "${MODE}" == check ]]; then
    "${LLAMA_SERVER}" --version
    echo "Model present: ${MODEL} (inference not tested)"
    exit 0
fi

echo "Ternary Bonsai 2 27B PTQ1_0 | context: ${CTX_SIZE} | reasoning: ${BONSAI_REASONING_EFFORT}"
echo "API: http://${HOST}:${PORT}/v1"
exec "${LLAMA_SERVER}" "${ARGS[@]}" "$@"
