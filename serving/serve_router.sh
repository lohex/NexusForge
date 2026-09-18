#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_SERVER="${PROJECT_HOME}/llama.cpp/build/bin/llama-server"
PRESETS="${PROJECT_HOME}/config/router-models.ini"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: llama-server not found: ${LLAMA_SERVER}" >&2
    exit 1
fi

if [[ ! -f "${PRESETS}" ]]; then
    echo "ERROR: Router presets not found: ${PRESETS}" >&2
    exit 1
fi

# Resolve model paths independently of the directory from which we were called.
cd "${PROJECT_HOME}"

echo "Starting NexusForge model router: http://${HOST}:${PORT}/v1"
echo "At most one model loaded; models load on demand."
echo "Use /models in OpenCode to switch. Stop standalone model servers first."

# Do not pass model-specific flags here: router CLI flags override INI presets.
# No -m: this starts router mode, not a single-model server.
exec "${LLAMA_SERVER}" \
    --models-preset "${PRESETS}" \
    --models-max 1 \
    --models-autoload \
    --host "${HOST}" \
    --port "${PORT}"
