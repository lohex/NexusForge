#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NexusForge local LLM setup
#
# Everything specific to NexusForge is stored below PROJECT_HOME.
#
# Structure:
#
# NexusForge/
# ├── models/
# │   ├── qwen/
# │   │   └── Qwen3.5-9B-Q4_K_M.gguf
# │   └── granite/
# │       └── granite-4.2-3b-Q4_K_M.gguf
# │
# ├── llama.cpp/
# │   └── build/bin/
# │       ├── llama-server
# │       └── llama-cli
# │
# ├── .tools/
# │   └── hf-home/
# │
# └── .cache/
#     └── huggingface/
# ============================================================


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODELS_DIR="${PROJECT_HOME}/models"
QWEN_DIR="${MODELS_DIR}/qwen"
GRANITE_DIR="${MODELS_DIR}/granite"

LLAMA_DIR="${PROJECT_HOME}/llama.cpp"

TOOLS_DIR="${PROJECT_HOME}/.tools"

OPENCODE_HOME="${PROJECT_HOME}/.tools/opencode-home"
OPENCODE_BIN="${OPENCODE_HOME}/.opencode/bin/opencode"

TMP_DIR="${PROJECT_HOME}/.cache/tmp"

# The standalone HF installer normally writes into $HOME.
# Give it a project-local HOME instead.
HF_INSTALL_HOME="${TOOLS_DIR}/hf-home"
HF_BIN="${HF_INSTALL_HOME}/.local/bin/hf"

# Keep all Hugging Face cache/state below the project directory.
export HF_HOME="${PROJECT_HOME}/.cache/huggingface"
export HF_HUB_CACHE="${HF_HOME}/hub"
export HF_XET_CACHE="${HF_HOME}/xet"

# Avoid Xet/CAS reconstruction problems.
export HF_HUB_DISABLE_XET=1

# Optional: avoid update-check noise during scripted runs.
export HF_HUB_DISABLE_UPDATE_CHECK=1


# ------------------------------------------------------------
# Model definitions
# ------------------------------------------------------------

QWEN_REPO="unsloth/Qwen3.5-9B-GGUF"
QWEN_NAME="Qwen3.5-9B-Q4_K_M.gguf"
QWEN_FILE="${QWEN_DIR}/${QWEN_NAME}"

GRANITE_REPO="ibm-granite/granite-4.2-3b-GGUF"
GRANITE_NAME="granite-4.2-3b-Q4_K_M.gguf"
GRANITE_FILE="${GRANITE_DIR}/${GRANITE_NAME}"

# Conservative thresholds used only to detect obviously incomplete files.
# Expected sizes are roughly:
# Qwen:    5.68 GB
# Granite: 2.24 GB

QWEN_MIN_BYTES=5500000000
GRANITE_MIN_BYTES=2100000000


# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

file_is_complete() {
    local file="$1"
    local min_size="$2"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    local size
    size="$(stat -c%s "${file}")"

    if (( size >= min_size )); then
        return 0
    fi

    return 1
}


download_model() {
    local repo="$1"
    local filename="$2"
    local destination="$3"
    local min_size="$4"

    local target="${destination}/${filename}"

    if file_is_complete "${target}" "${min_size}"; then
        local size
        size="$(stat -c%s "${target}")"

        echo
        echo "Model already present:"
        echo "  ${target}"
        echo "  size: $(( size / 1000000 )) MB"
        echo "Skipping download."
        return
    fi

    if [[ -f "${target}" ]]; then
        local size
        size="$(stat -c%s "${target}")"

        echo
        echo "Incomplete model file detected:"
        echo "  ${target}"
        echo "  size: $(( size / 1000000 )) MB"
        echo
        echo "Removing incomplete reconstructed file."
        echo "Download cache is retained so hf can reuse existing data."

        rm -f "${target}"
    fi

    echo
    echo "Downloading:"
    echo "  ${repo}/${filename}"
    echo

    "${HF_BIN}" download \
        "${repo}" \
        "${filename}" \
        --local-dir "${destination}" \
        --cache-dir "${HF_HUB_CACHE}"

    if ! file_is_complete "${target}" "${min_size}"; then
        echo
        echo "ERROR: Download completed but model file appears incomplete:"
        echo "  ${target}"
        exit 1
    fi

    echo
    echo "Download complete:"
    echo "  ${target}"
}


# ------------------------------------------------------------
# 1. Create directory structure
# ------------------------------------------------------------

echo "============================================================"
echo "NexusForge setup"
echo "============================================================"
echo
echo "Project:"
echo "  ${PROJECT_HOME}"
echo

mkdir -p "${QWEN_DIR}"
mkdir -p "${GRANITE_DIR}"
mkdir -p "${TOOLS_DIR}"
mkdir -p "${HF_HOME}"
mkdir -p "${OPENCODE_HOME}"
mkdir -p "${TMP_DIR}"

# ------------------------------------------------------------
# 2. Install project-local Hugging Face CLI
# ------------------------------------------------------------

if [[ -x "${HF_BIN}" ]]; then
    echo "Hugging Face CLI already installed:"
    echo "  ${HF_BIN}"
    "${HF_BIN}" version || true

else
    echo
    echo "=== Installing project-local Hugging Face CLI ==="

    mkdir -p "${HF_INSTALL_HOME}"

    curl -LsSf https://hf.co/cli/install.sh \
        | env \
            HOME="${HF_INSTALL_HOME}" \
            XDG_CACHE_HOME="${HF_INSTALL_HOME}/.cache" \
            XDG_CONFIG_HOME="${HF_INSTALL_HOME}/.config" \
            XDG_DATA_HOME="${HF_INSTALL_HOME}/.local/share" \
            bash -s -- --exclude-skill

    if [[ ! -x "${HF_BIN}" ]]; then
        echo
        echo "ERROR: hf CLI installation failed."
        echo "Expected executable:"
        echo "  ${HF_BIN}"
        exit 1
    fi
fi

echo
echo "Using hf:"
echo "  ${HF_BIN}"

# ------------------------------------------------------------
# Install project-local OpenCode CLI
# ------------------------------------------------------------

echo
echo "=== Checking OpenCode CLI ==="

if [[ -x "${OPENCODE_BIN}" ]]; then
    echo "OpenCode already installed:"
    echo "  ${OPENCODE_BIN}"
    "${OPENCODE_BIN}" --version || true

else
    echo "=== Installing project-local OpenCode CLI ==="

    curl -fsSL https://opencode.ai/install \
        | env \
            HOME="${OPENCODE_HOME}" \
            TMPDIR="${TMP_DIR}" \
            PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            bash -s -- --no-modify-path

    if [[ ! -x "${OPENCODE_BIN}" ]]; then
        echo
        echo "ERROR: OpenCode installation failed."
        echo "Expected executable:"
        echo "  ${OPENCODE_BIN}"
        exit 1
    fi
fi

echo
echo "Using OpenCode:"
echo "  ${OPENCODE_BIN}"

# ------------------------------------------------------------
# 3. Download Qwen
# ------------------------------------------------------------

echo
echo "=== Checking Qwen3.5-9B Q4_K_M ==="

download_model \
    "${QWEN_REPO}" \
    "${QWEN_NAME}" \
    "${QWEN_DIR}" \
    "${QWEN_MIN_BYTES}"


# ------------------------------------------------------------
# 4. Download Granite
# ------------------------------------------------------------

echo
echo "=== Checking Granite 4.2 3B Q4_K_M ==="

download_model \
    "${GRANITE_REPO}" \
    "${GRANITE_NAME}" \
    "${GRANITE_DIR}" \
    "${GRANITE_MIN_BYTES}"


# ------------------------------------------------------------
# 5. Install llama.cpp system build dependencies
# ------------------------------------------------------------

echo
echo "=== Checking llama.cpp build dependencies ==="

missing_packages=()

command -v git >/dev/null 2>&1 || missing_packages+=(git)
command -v cmake >/dev/null 2>&1 || missing_packages+=(cmake)
command -v make >/dev/null 2>&1 || missing_packages+=(build-essential)
command -v curl >/dev/null 2>&1 || missing_packages+=(curl)

if (( ${#missing_packages[@]} > 0 )); then
    echo "Installing missing packages:"
    printf '  %s\n' "${missing_packages[@]}"

    sudo apt update
    sudo apt install -y "${missing_packages[@]}"
else
    echo "Build dependencies already installed."
fi


# ------------------------------------------------------------
# 6. Check NVIDIA / CUDA
# ------------------------------------------------------------

echo
echo "=== Checking NVIDIA GPU ==="

if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi
else
    echo
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
    echo "Install CUDA first and rerun this script."
    exit 1
fi


# ------------------------------------------------------------
# 7. Clone or update llama.cpp
# ------------------------------------------------------------

if [[ -d "${LLAMA_DIR}/.git" ]]; then
    echo
    echo "=== Updating existing llama.cpp repository ==="

    git -C "${LLAMA_DIR}" pull --ff-only

elif [[ -e "${LLAMA_DIR}" ]]; then
    echo
    echo "ERROR:"
    echo "  ${LLAMA_DIR}"
    echo "already exists but is not a llama.cpp git repository."
    exit 1

else
    echo
    echo "=== Cloning llama.cpp ==="

    git clone \
        https://github.com/ggml-org/llama.cpp.git \
        "${LLAMA_DIR}"
fi


# ------------------------------------------------------------
# 8. Build llama.cpp with CUDA
# ------------------------------------------------------------

echo
echo "=== Configuring llama.cpp with CUDA ==="

cmake \
    -S "${LLAMA_DIR}" \
    -B "${LLAMA_DIR}/build" \
    -DGGML_CUDA=ON \
    -DCMAKE_BUILD_TYPE=Release

echo
echo "=== Building llama.cpp ==="

# CMake performs an incremental build if already built.
cmake \
    --build "${LLAMA_DIR}/build" \
    --config Release \
    -j "$(nproc)"


# ------------------------------------------------------------
# 9. Verify
# ------------------------------------------------------------

LLAMA_SERVER="${LLAMA_DIR}/build/bin/llama-server"
LLAMA_CLI="${LLAMA_DIR}/build/bin/llama-cli"

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo
    echo "ERROR: llama-server was not built successfully."
    exit 1
fi


# ------------------------------------------------------------
# 10. Summary
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Installation complete"
echo "============================================================"

echo
echo "Project:"
echo "  ${PROJECT_HOME}"

echo
echo "Qwen:"
echo "  ${QWEN_FILE}"

echo
echo "Granite:"
echo "  ${GRANITE_FILE}"

echo
echo "Hugging Face CLI:"
echo "  ${HF_BIN}"

echo
echo "llama-server:"
echo "  ${LLAMA_SERVER}"

echo
echo "llama-cli:"
echo "  ${LLAMA_CLI}"

echo
echo "Start Granite with two parallel slots:"
echo
echo "${LLAMA_SERVER} \\"
echo "  -m ${GRANITE_FILE} \\"
echo "  -ngl 999 \\"
echo "  -c 32768 \\"
echo "  -np 2 \\"
echo "  --host 127.0.0.1 \\"
echo "  --port 8080"

echo
