#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${GRANITE_8B_MODEL_DIR:-${PROJECT_HOME}/models/granite}"
MODEL_REPO="ibm-granite/granite-4.2-8b-GGUF"
MODEL_NAME="granite-4.2-8b-Q4_K_M.gguf"
MODEL_FILE="${MODEL_DIR}/${MODEL_NAME}"

# Pin the official IBM artifact so its SHA256 remains reproducible.
MODEL_REVISION="3b36e977bf3dbbf2143c5ead4029290e94637084"
MODEL_SHA256="16a9369d0805f80b7377d25d87f937a90c05dc04ad79173a52001e42c9aab311"

verify_model() {
    [[ -f "${MODEL_FILE}" ]] &&
        printf '%s  %s\n' "${MODEL_SHA256}" "${MODEL_FILE}" | sha256sum --check --status
}

if verify_model; then
    echo "Granite 4.2 8B is already installed and verified:"
    echo "  ${MODEL_FILE}"
    exit 0
fi

PROJECT_HF="${PROJECT_HOME}/.tools/hf-home/.local/bin/hf"
if [[ -x "${PROJECT_HF}" ]]; then
    HF_BIN="${PROJECT_HF}"
elif command -v hf >/dev/null 2>&1; then
    HF_BIN="$(command -v hf)"
else
    echo "ERROR: Hugging Face CLI not found. Install hf or run ./installations/install.sh first." >&2
    exit 1
fi

export HF_HUB_DISABLE_XET=1
export HF_HOME="${PROJECT_HOME}/.cache/huggingface"
mkdir -p "${MODEL_DIR}"

# Resume interrupted downloads; replace an existing file only if verification failed.
DOWNLOAD_ARGS=()
if [[ -f "${MODEL_FILE}" ]]; then
    echo "Existing model failed verification; downloading a fresh copy."
    DOWNLOAD_ARGS+=(--force-download)
fi

echo "Downloading official Granite 4.2 8B Q4_K_M (5.35 GB)..."
"${HF_BIN}" download "${MODEL_REPO}" "${MODEL_NAME}" \
    --revision "${MODEL_REVISION}" \
    --local-dir "${MODEL_DIR}" \
    "${DOWNLOAD_ARGS[@]}"

echo "Verifying SHA256..."
if ! verify_model; then
    echo "ERROR: Model checksum mismatch. Run this script again to retry." >&2
    exit 1
fi

echo "Installed and verified: ${MODEL_FILE}"
echo "Start with: ./serving/serve_granite_8b.sh"
