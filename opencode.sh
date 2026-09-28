#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Enable the built-in Exa web search for local model providers, including Qwen.
export OPENCODE_ENABLE_EXA=1

# Project-local language servers, available even in another target repository.
export PATH="${PROJECT_HOME}/.tools/lsp/node_modules/.bin:${PATH}"
export OPENCODE_EXPERIMENTAL_LSP_TOOL=true

# Load the NexusForge providers and agents even when OpenCode works in another
# repository. The custom config directory also exposes the shared skills,
# plugins, and their project-local dependencies.
export OPENCODE_CONFIG="${PROJECT_HOME}/opencode.json"
export OPENCODE_CONFIG_DIR="${PROJECT_HOME}/.opencode"

# Shared skills use this path for NexusForge-owned launchers and configuration
# instead of resolving them relative to the active target repository.
export NEXUSFORGE_HOME="${PROJECT_HOME}"

# Interactive and server modes need the configured local model API. Diagnose and
# management commands remain usable even when no model server is installed.
case "${1:-}" in
    ""|run|serve|web|github|pr|--agent|--model|-m|-c|--continue|-s|--session|--prompt|--port|--hostname|--mini|--auto|/*|./*|../*) NEED_ROUTER=true ;;
    --help|-h|--version|-v|debug|agent|models|session|db|plugin|plug|providers|auth|completion|upgrade|uninstall|import|export|stats|mcp|attach|acp) NEED_ROUTER=false ;;
    *) NEED_ROUTER=true ;;
esac
if [[ "${NEED_ROUTER}" == true && "${NEXUSFORGE_ROUTER_AUTOSTART:-1}" != 0 ]]; then
    ROUTER_DIR="${PROJECT_HOME}/.cache/router"
    mkdir -p "${ROUTER_DIR}"
    # Serialize check/start across two OpenCode launches. Release before exec.
    exec 9>"${ROUTER_DIR}/startup.lock"
    flock -x 9
    BACKEND="${NEXUSFORGE_LLAMA_BACKEND:-bonsai}"
    PROBE=(python3 "${PROJECT_HOME}/serving/check_router.py" "${BACKEND}")
    if "${PROBE[@]}"; then
        :
    else
        STATUS=$?
        if (( STATUS != 10 )); then
            echo "ERROR: Port 8080 is occupied by an incompatible server or cannot be checked." >&2
            echo "Expected the NexusForge ${BACKEND} router. Stop the other server or set NEXUSFORGE_ROUTER_AUTOSTART=0." >&2
            exit 1
        fi
        # This only starts when the port has no listener. The router checks its
        # runtime and presets; a failed start is reported with the log path.
        LOG="${ROUTER_DIR}/${BACKEND}-router.log"
        echo "Starting NexusForge router (${BACKEND}); log: ${LOG}" >&2
        nohup env HOST=127.0.0.1 PORT=8080 NEXUSFORGE_LLAMA_BACKEND="${BACKEND}" \
            "${PROJECT_HOME}/serving/serve_router.sh" >>"${LOG}" 2>&1 </dev/null &
        ROUTER_PID=$!
        printf '%s\n' "${ROUTER_PID}" >"${ROUTER_DIR}/${BACKEND}-router.pid"
        READY=false
        for (( attempt=0; attempt<60; attempt++ )); do
            if "${PROBE[@]}"; then READY=true; break; fi
            if ! kill -0 "${ROUTER_PID}" 2>/dev/null; then break; fi
            sleep 0.25
        done
        if [[ "${READY}" != true ]]; then
            echo "ERROR: Router did not become ready. Inspect ${LOG}." >&2
            exit 1
        fi
    fi
    flock -u 9
    exec 9>&-
fi

exec "${PROJECT_HOME}/.tools/opencode-home/.opencode/bin/opencode" "$@"
