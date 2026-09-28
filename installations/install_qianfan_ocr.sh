#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${PROJECT_HOME}/models/qianfan-ocr"
MODEL_REPO="${QIANFAN_MODEL_REPO:-ggml-org/Qianfan-OCR-GGUF}"
QUANT="${QIANFAN_QUANT:-Q8_0}"

export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"
export HF_HOME="${HF_HOME:-${PROJECT_HOME}/.cache/huggingface}"
export HF_HUB_CACHE="${HF_HUB_CACHE:-${HF_HOME}/hub}"

PROJECT_HF="${PROJECT_HOME}/.tools/hf-home/.local/bin/hf"
if [[ -x "${PROJECT_HF}" ]]; then
    HF_BIN="${PROJECT_HF}"
elif command -v hf >/dev/null 2>&1; then
    HF_BIN="$(command -v hf)"
else
    echo "ERROR: Hugging Face CLI (hf) not found." >&2
    echo "Run installations/install.sh first." >&2
    exit 1
fi

mkdir -p "${MODEL_DIR}" "${HF_HUB_CACHE}"

echo "Downloading Qianfan-OCR GGUF (${QUANT})"
echo "Repository: ${MODEL_REPO}"
"${HF_BIN}" download "${MODEL_REPO}" \
    --include "*${QUANT}*.gguf" \
    --local-dir "${MODEL_DIR}"

MODEL_FILE="$(find "${MODEL_DIR}" -maxdepth 1 -type f -iname "*${QUANT}*.gguf" -print -quit)"
if [[ -z "${MODEL_FILE}" ]]; then
    echo "ERROR: no ${QUANT} GGUF file found in ${MODEL_DIR}" >&2
    exit 1
fi

echo
echo "Qianfan-OCR GGUF installed"
echo "  Model: ${MODEL_FILE}"
echo "  Size:  $(( $(stat -c%s "${MODEL_FILE}") / 1000000 )) MB"
