#!/usr/bin/env bash
set -euo pipefail

# Community distillation by Empero, using the Qwen3.5-9B architecture.
# https://huggingface.co/empero-ai/Qwen3.8-9B-Distill-GGUF
PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${QWEN38_MODEL_DIR:-${PROJECT_HOME}/models/qwen38-9b-distill}"
MODEL_REPO="empero-ai/Qwen3.8-9B-Distill-GGUF"
MODEL_REVISION="760121cd70bb4c36b2b5ec58eb765e0df5987efe"
MODEL_NAME="Qwen3.8-9B-Q4_K_M.gguf"
MODEL_SHA256="df13d66021cef676f82be74053220fd75af6bf2a6a7fb77f5222ab9e50744a7a"
MODEL_FILE="${MODEL_DIR}/${MODEL_NAME}"

case "${1:-}" in
    -h|--help)
        cat <<'HELP'
Usage: ./installations/install_qwen38_9b_distill.sh

Download Empero Qwen3.8-9B-Distill Q4_K_M (5.78 GB), verify SHA256,
and save its model card and checksums. Existing verified weights are reused.
Requires hf and sha256sum. Uses the existing standard llama.cpp installation;
run installations/install.sh first if llama-server is missing.

Environment:
  QWEN38_MODEL_DIR  Destination (default: models/qwen38-9b-distill)
  HF_BIN           Optional path to hf
  HF_TOKEN         Optional Hugging Face token; cached hf login also works
  HF_HOME          Cache directory (default: .cache/huggingface)

Start afterwards: ./serving/serve_qwen38_9b_distill.sh
HELP
        exit 0 ;;
esac
if (( $# )); then
    echo "ERROR: Unexpected arguments. Use --help." >&2
    exit 2
fi
command -v sha256sum >/dev/null || { echo "ERROR: sha256sum missing." >&2; exit 1; }
if [[ -z "${HF_BIN:-}" ]]; then
    if [[ -x "${PROJECT_HOME}/.tools/hf-home/.local/bin/hf" ]]; then
        HF_BIN="${PROJECT_HOME}/.tools/hf-home/.local/bin/hf"
    else
        HF_BIN="hf"
    fi
fi
command -v "${HF_BIN}" >/dev/null || { echo "ERROR: Install hf or run installations/install.sh first." >&2; exit 1; }
export HF_HOME="${HF_HOME:-${PROJECT_HOME}/.cache/huggingface}"
export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"
mkdir -p "${MODEL_DIR}"

verify_model() {
    [[ -f "${MODEL_FILE}" ]] &&
        printf '%s  %s\n' "${MODEL_SHA256}" "${MODEL_FILE}" | sha256sum --check --status
}
if verify_model; then
    echo "Existing model verified: ${MODEL_FILE}"
else
    DOWNLOAD_ARGS=()
    if [[ -f "${MODEL_FILE}" ]]; then
        echo "Existing model failed verification; downloading a fresh copy."
        DOWNLOAD_ARGS+=(--force-download)
    fi
    "${HF_BIN}" download "${MODEL_REPO}" "${MODEL_NAME}" \
        --revision "${MODEL_REVISION}" --local-dir "${MODEL_DIR}" "${DOWNLOAD_ARGS[@]}"
    if ! verify_model; then
        echo "ERROR: SHA256 mismatch. Run the installer again to retry." >&2
        exit 1
    fi
fi
"${HF_BIN}" download "${MODEL_REPO}" README.md SHA256SUMS \
    --revision "${MODEL_REVISION}" --local-dir "${MODEL_DIR}"
echo "Installed and verified: ${MODEL_FILE}"
echo "Start with: ./serving/serve_qwen38_9b_distill.sh"
