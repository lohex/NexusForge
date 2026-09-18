#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="${PROJECT_HOME}/models/qwen-long-context"

MODEL_REPO="unsloth/Qwen3.5-4B-GGUF"
MODEL_NAME="Qwen3.5-4B-Q4_K_M.gguf"
MODEL_FILE="${MODEL_DIR}/${MODEL_NAME}"

# Current Q4_K_M is ~2.74 GB.
MIN_MODEL_SIZE=2600000000

export HF_HUB_DISABLE_XET=1
export HF_HOME="${PROJECT_HOME}/.cache/huggingface"
export HF_HUB_CACHE="${HF_HOME}/hub"

mkdir -p "${MODEL_DIR}"
mkdir -p "${HF_HUB_CACHE}"


# ------------------------------------------------------------
# Find Hugging Face CLI
# ------------------------------------------------------------

PROJECT_HF="${PROJECT_HOME}/.tools/hf-home/.local/bin/hf"

if [[ -x "${PROJECT_HF}" ]]; then
    HF_BIN="${PROJECT_HF}"
elif command -v hf >/dev/null 2>&1; then
    HF_BIN="$(command -v hf)"
else
    echo "ERROR: Hugging Face CLI not found."
    echo "Run the NexusForge installer first."
    exit 1
fi


# ------------------------------------------------------------
# Check whether model is already complete
# ------------------------------------------------------------

if [[ -f "${MODEL_FILE}" ]]; then
    FILE_SIZE="$(stat -c%s "${MODEL_FILE}")"

    if (( FILE_SIZE >= MIN_MODEL_SIZE )); then
        echo "Qwen3.5-4B long-context model already installed."
        echo
        echo "  ${MODEL_FILE}"
        echo "  $(( FILE_SIZE / 1000000 )) MB"
        exit 0
    fi

    echo "Incomplete model detected:"
    echo "  ${MODEL_FILE}"
    echo
    echo "Removing incomplete output file."
    rm -f "${MODEL_FILE}"
fi


# ------------------------------------------------------------
# Download
# ------------------------------------------------------------

echo "============================================================"
echo "Downloading Qwen3.5-4B Q4_K_M"
echo "============================================================"
echo
echo "Repository:"
echo "  ${MODEL_REPO}"
echo
echo "Destination:"
echo "  ${MODEL_FILE}"
echo

"${HF_BIN}" download \
    "${MODEL_REPO}" \
    "${MODEL_NAME}" \
    --local-dir "${MODEL_DIR}" 


# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

if [[ ! -f "${MODEL_FILE}" ]]; then
    echo "ERROR: model file not found after download."
    exit 1
fi

FILE_SIZE="$(stat -c%s "${MODEL_FILE}")"

if (( FILE_SIZE < MIN_MODEL_SIZE )); then
    echo "ERROR: downloaded model appears incomplete."
    echo "Size: ${FILE_SIZE}"
    exit 1
fi

echo
echo "============================================================"
echo "Long-context model installed"
echo "============================================================"
echo
echo "${MODEL_FILE}"
echo
echo "Size: $(( FILE_SIZE / 1000000 )) MB"
