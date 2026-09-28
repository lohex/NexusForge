#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${NEXUSFORGE_LLAMA_BACKEND:-bonsai}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
MODE=run
case "${1:-}" in
    --dry-run) MODE=dry-run; shift ;;
    --check) MODE=check; shift ;;
    -h|--help)
        cat <<'HELP'
Usage: ./serving/serve_router.sh [--dry-run|--check]

One API for Bonsai and the six existing NexusForge models. Models load on
request; at most one model is loaded. Granite 3B retains its three slots.

Environment:
  NEXUSFORGE_LLAMA_BACKEND  bonsai (default) or standard (without Bonsai)
  BONSAI_LLAMA_DIR         Fork directory (default: ./llama.cpp-bonsai)
  HOST / PORT              Bind address (default: 127.0.0.1 / 8080)

--dry-run  Print working directory, runtime, presets and command; start nothing.
--check    Check runtime version and required router options; start nothing.
Model paths and per-model settings are configured in config/router-models*.ini.
Install the fork with ./installations/install_bonsai_2_27b.sh.
Stop the existing server before changing backends. No automatic fallback.
HELP
        exit 0 ;;
esac
if (( $# )); then
    echo "ERROR: Unexpected argument: $1. Use --help." >&2
    exit 2
fi
case "${BACKEND}" in
    bonsai)
        LLAMA_DIR="${BONSAI_LLAMA_DIR:-${PROJECT_HOME}/llama.cpp-bonsai}"
        PRESETS="${PROJECT_HOME}/config/router-models-bonsai.ini"
        INSTALLER="installations/install_bonsai_2_27b.sh" ;;
    standard)
        LLAMA_DIR="${PROJECT_HOME}/llama.cpp"
        PRESETS="${PROJECT_HOME}/config/router-models.ini"
        INSTALLER="installations/install.sh" ;;
    *) echo "ERROR: NEXUSFORGE_LLAMA_BACKEND must be standard or bonsai." >&2; exit 2 ;;
esac
# Resolve relative overrides before switching the working directory.
[[ "${LLAMA_DIR}" = /* ]] || LLAMA_DIR="${PWD}/${LLAMA_DIR}"
RUNTIME_DIR="${LLAMA_DIR}/build/bin"
LLAMA_SERVER="${RUNTIME_DIR}/llama-server"
# Children execute this same binary. Prefer its matching shared libraries.
export LD_LIBRARY_PATH="${RUNTIME_DIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
cd "${PROJECT_HOME}"
CMD=("${LLAMA_SERVER}" --models-preset "${PRESETS}" --models-max 1
     --models-autoload --host "${HOST}" --port "${PORT}")
if [[ "${MODE}" == dry-run ]]; then
    printf 'Backend: %s\nWorking directory: %s\n' "${BACKEND}" "${PROJECT_HOME}"
    printf 'LD_LIBRARY_PATH=%q ' "${LD_LIBRARY_PATH}"
    printf '%q ' "${CMD[@]}"
    printf '\n'
    exit 0
fi
if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: Runtime missing: ${LLAMA_SERVER}. Run ./${INSTALLER}." >&2
    exit 1
fi
if [[ ! -f "${PRESETS}" ]]; then
    echo "ERROR: Router presets missing: ${PRESETS}. Restore the project configuration." >&2
    exit 1
fi
if [[ "${MODE}" == check ]]; then
    "${LLAMA_SERVER}" --version
    HELP_OUTPUT="$("${LLAMA_SERVER}" --help)"
    for option in --models-preset --models-max --models-autoload; do
        if [[ "${HELP_OUTPUT}" != *"${option}"* ]]; then
            echo "ERROR: Runtime does not support ${option}." >&2
            exit 1
        fi
    done
    echo "Router runtime ready (${BACKEND}); model loading not tested."
    exit 0
fi
echo "Starting NexusForge router (${BACKEND}): http://${HOST}:${PORT}/v1"
echo "At most one model loaded; use /models in OpenCode to select a model."
# Model-specific flags belong in INI profiles; CLI flags would override them.
exec "${CMD[@]}"
