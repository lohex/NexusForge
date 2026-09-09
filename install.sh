#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Local LLM setup
#
# Structure:
#
# ~/models/
# ├── qwen/
# │   └── Qwen3.5-9B-Q4_K_M.gguf
# └── granite/
#     └── granite-4.2-3b-Q4_K_M.gguf
#
# ~/llama.cpp/
# └── build/bin/
#     ├── llama-server
#     └── llama-cli
# ============================================================

PROJECT_HOME="$(pwd)"
MODELS_DIR="${PROJECT_HOME}/models"
QWEN_DIR="${MODELS_DIR}/qwen"
GRANITE_DIR="${MODELS_DIR}/granite"
LLAMA_DIR="${HOME}/llama.cpp"

echo "=== Creating directory structure ==="

mkdir -p "${QWEN_DIR}"
mkdir -p "${GRANITE_DIR}"


# ------------------------------------------------------------
# 1. Install Hugging Face CLI
# ------------------------------------------------------------

if command -v hf >/dev/null 2>&1; then
    echo "hf CLI already installed:"
    hf version || true
else
    echo "=== Installing Hugging Face CLI ==="

    curl -LsSf https://hf.co/cli/install.sh | bash

    # hf is normally installed into ~/.local/bin
    export PATH="${HOME}/.local/bin:${PATH}"

    if ! command -v hf >/dev/null 2>&1; then
        echo "ERROR: hf CLI was installed but is not on PATH."
        echo "Add this to ~/.bashrc:"
        echo 'export PATH="$HOME/.local/bin:$PATH"'
        exit 1
    fi
fi


# ------------------------------------------------------------
# 2. Download Qwen3.5-9B Q4_K_M
# ------------------------------------------------------------

QWEN_FILE="${QWEN_DIR}/Qwen3.5-9B-Q4_K_M.gguf"

if [[ -f "${QWEN_FILE}" ]]; then
    echo "Qwen model already exists:"
    echo "  ${QWEN_FILE}"
else
    echo "=== Downloading Qwen3.5-9B Q4_K_M ==="

    hf download \
        unsloth/Qwen3.5-9B-GGUF \
        Qwen3.5-9B-Q4_K_M.gguf \
        --local-dir "${QWEN_DIR}"
fi


# ------------------------------------------------------------
# 3. Download Granite 4.2 3B Q4_K_M
# ------------------------------------------------------------

GRANITE_FILE="${GRANITE_DIR}/granite-4.2-3b-Q4_K_M.gguf"

if [[ -f "${GRANITE_FILE}" ]]; then
    echo "Granite model already exists:"
    echo "  ${GRANITE_FILE}"
else
    echo "=== Downloading Granite 4.2 3B Q4_K_M ==="

    hf download \
        ibm-granite/granite-4.2-3b-GGUF \
        granite-4.2-3b-Q4_K_M.gguf \
        --local-dir "${GRANITE_DIR}"
fi


# ------------------------------------------------------------
# 4. Install llama.cpp build dependencies
# ------------------------------------------------------------

echo "=== Installing llama.cpp dependencies ==="

sudo apt update
sudo apt install -y \
    git \
    cmake \
    build-essential \
    curl


# ------------------------------------------------------------
# 5. Check NVIDIA / CUDA
# ------------------------------------------------------------

echo "=== Checking NVIDIA GPU ==="

if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi
else
    echo "WARNING: nvidia-smi was not found."
    echo "NVIDIA drivers may not be installed."
fi

echo

if command -v nvcc >/dev/null 2>&1; then
    echo "CUDA compiler found:"
    nvcc --version
else
    echo
    echo "ERROR: nvcc was not found."
    echo
    echo "llama.cpp CUDA support requires the CUDA Toolkit."
    echo "Install CUDA first, then run this script again."
    echo
    exit 1
fi


# ------------------------------------------------------------
# 6. Clone/update llama.cpp
# ------------------------------------------------------------

if [[ -d "${LLAMA_DIR}/.git" ]]; then
    echo "=== Updating existing llama.cpp repository ==="

    git -C "${LLAMA_DIR}" pull --ff-only
else
    echo "=== Cloning llama.cpp ==="

    git clone \
        https://github.com/ggml-org/llama.cpp.git \
        "${LLAMA_DIR}"
fi


# ------------------------------------------------------------
# 7. Build llama.cpp with CUDA
# ------------------------------------------------------------

echo "=== Configuring llama.cpp with CUDA ==="

cmake \
    -S "${LLAMA_DIR}" \
    -B "${LLAMA_DIR}/build" \
    -DGGML_CUDA=ON \
    -DCMAKE_BUILD_TYPE=Release


echo "=== Building llama.cpp ==="

cmake \
    --build "${LLAMA_DIR}/build" \
    --config Release \
    -j "$(nproc)"


# ------------------------------------------------------------
# 8. Verify
# ------------------------------------------------------------

LLAMA_SERVER="${LLAMA_DIR}/build/bin/llama-server"

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "ERROR: llama-server was not built successfully."
    exit 1
fi


echo
echo "============================================================"
echo "Installation complete"
echo "============================================================"
echo
echo "Qwen:"
echo "  ${QWEN_FILE}"
echo
echo "Granite:"
echo "  ${GRANITE_FILE}"
echo
echo "llama-server:"
echo "  ${LLAMA_SERVER}"
echo
echo "Test Granite with:"
echo
echo "${LLAMA_SERVER} \\"
echo "  -m ${GRANITE_FILE} \\"
echo "  -ngl 999 \\"
echo "  -c 32768 \\"
echo "  -np 2 \\"
echo "  --host 127.0.0.1 \\"
echo "  --port 8080"
echo
