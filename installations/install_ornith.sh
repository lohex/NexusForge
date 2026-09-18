#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="${PROJECT_HOME}/models/ornith"
MODEL_REPO="ornith-ai/Ornith-1.5-9B-GGUF"
MODEL_NAME="Ornith-1.5-9B-Q4_K_M.gguf"
MODEL_FILE="${MODEL_DIR}/${MODEL_NAME}"

# Actual file size is ~5.78 GB.
MIN_MODEL_SIZE=5600000000

export HF_HUB_DISABLE_XET=1
export HF_HOME="${PROJECT_HOME}/.cache/huggingface"

mkdir -p "${MODEL_DIR}"

PROJECT_HF="${PROJECT_HOME}/.tools/hf-home/.local/bin/hf"

if [[ -x "${PROJECT_HF}" ]]; then
    HF_BIN="${PROJECT_HF}"
elif command -v hf >/dev/null 2>&1; then
    HF_BIN="$(command -v hf)"
else
    echo "ERROR: Hugging Face CLI not found."
    exit 1
fi

if [[ -f "${MODEL_FILE}" ]]; then
    FILE_SIZE="$(stat -c%s "${MODEL_FILE}")"

    if (( FILE_SIZE >= MIN_MODEL_SIZE )); then
        echo "Ornith already installed:"
        echo "  ${MODEL_FILE}"
        exit 0
    fi

    echo "Incomplete Ornith file found. Removing it."
    rm -f "${MODEL_FILE}"
fi

echo "Downloading Ornith-1.5-9B Q4_K_M..."

"${HF_BIN}" download \
    "${MODEL_REPO}" \
    "${MODEL_NAME}" \
    --local-dir "${MODEL_DIR}"

FILE_SIZE="$(stat -c%s "${MODEL_FILE}")"

if (( FILE_SIZE < MIN_MODEL_SIZE )); then
    echo "ERROR: downloaded model appears incomplete."
    exit 1
fi

echo
echo "Ornith installed:"
echo "  ${MODEL_FILE}"
