#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="${PROJECT_HOME}/models/qwen-vl-4b"
MODEL_REPO="${QWEN_VL_MODEL_REPO:-Qwen/Qwen3-VL-4B-Instruct-GGUF}"
MODEL_NAME="${QWEN_VL_MODEL_FILE:-Qwen3VL-4B-Instruct-Q4_K_M.gguf}"
MMPROJ_NAME="${QWEN_VL_MMPROJ_FILE:-mmproj-Qwen3VL-4B-Instruct-F16.gguf}"
MODEL_FILE="${MODEL_DIR}/${MODEL_NAME}"
MMPROJ_FILE="${MODEL_DIR}/${MMPROJ_NAME}"

# Guard against interrupted downloads. The exact size may change between
# revisions, so these are deliberately conservative lower bounds.
MIN_MODEL_SIZE="${QWEN_VL_MIN_MODEL_SIZE:-2000000000}"
MIN_MMPROJ_SIZE="${QWEN_VL_MIN_MMPROJ_SIZE:-100000000}"

export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"
export HF_HOME="${HF_HOME:-${PROJECT_HOME}/.cache/huggingface}"
export HF_HUB_CACHE="${HF_HUB_CACHE:-${HF_HOME}/hub}"

mkdir -p "${MODEL_DIR}" "${HF_HUB_CACHE}"

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

is_complete() {
    local file="$1" minimum="$2"
    [[ -f "${file}" ]] && (( $(stat -c%s "${file}") >= minimum ))
}

download_file() {
    local file="$1" minimum="$2"
    if is_complete "${file}" "${minimum}"; then
        echo "Already present: ${file}"
        return
    fi
    if [[ -e "${file}" ]]; then
        echo "Removing incomplete file: ${file}"
        rm -f "${file}"
    fi
    "${HF_BIN}" download "${MODEL_REPO}" "$(basename "${file}")" \
        --local-dir "${MODEL_DIR}"
    if ! is_complete "${file}" "${minimum}"; then
        echo "ERROR: downloaded file appears incomplete: ${file}" >&2
        exit 1
    fi
}

echo "Downloading Qwen3-VL-4B-Instruct GGUF components"
echo "Repository: ${MODEL_REPO}"
download_file "${MODEL_FILE}" "${MIN_MODEL_SIZE}"
download_file "${MMPROJ_FILE}" "${MIN_MMPROJ_SIZE}"

echo
echo "Qwen3-VL-4B-Instruct installed"
echo "  Model:   ${MODEL_FILE} ($(stat -c%s "${MODEL_FILE}")) bytes"
echo "  mmproj:  ${MMPROJ_FILE} ($(stat -c%s "${MMPROJ_FILE}")) bytes"
