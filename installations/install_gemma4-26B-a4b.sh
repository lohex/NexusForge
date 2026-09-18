#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="${PROJECT_HOME}/models/gemma4-26b-a4b"

MODEL_REPO="unsloth/gemma-4-26B-A4B-it-GGUF"
MODEL_NAME="gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
MODEL_FILE="${MODEL_DIR}/${MODEL_NAME}"

# Actual file size is ~16.9 GB.
MIN_MODEL_SIZE=16500000000

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
        echo "Gemma 4 26B A4B already installed:"
        echo "  ${MODEL_FILE}"
        exit 0
    fi

    echo "Incomplete Gemma file found. Removing it."
    rm -f "${MODEL_FILE}"
fi

echo "Downloading Gemma 4 26B A4B UD-Q4_K_M..."
echo "Expected download size: ~16.9 GB"

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
echo "Gemma installed:"
echo "  ${MODEL_FILE}"
