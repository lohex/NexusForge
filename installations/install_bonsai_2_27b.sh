#!/usr/bin/env bash
set -euo pipefail

# Official model card: https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf
# Download the model, clone the PrismML llama.cpp fork, then build CUDA.
# Starts no server. PrismML release pinned on 2026-09-26.
PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${BONSAI_MODEL_DIR:-${PROJECT_HOME}/models/bonsai-2-27b}"
MODEL_REPO="prism-ml/Ternary-Bonsai-2-27B-gguf"
MODEL_REVISION="b072e1d3b35a0a630cece372c2127528e0994386"
MODEL_NAME="Ternary-Bonsai-2-27B-PTQ1_0.gguf"
MODEL_SHA256="53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3"
LLAMA_DIR="${BONSAI_LLAMA_DIR:-${PROJECT_HOME}/llama.cpp-bonsai}"
RUNTIME_DIR="${LLAMA_DIR}/build/bin"
LLAMA_REVISION="prism-b10743-adfffbe"
BUILD_JOBS="${BONSAI_BUILD_JOBS:-4}"
CUDA_ARCHITECTURES="${BONSAI_CUDA_ARCHITECTURES:-native}"

case "${1:-}" in
    -h|--help)
        cat <<'HELP'
Usage: ./installations/install_bonsai_2_27b.sh

1. Download the official Ternary Bonsai 2 27B PTQ1_0 model (~5.95 GB).
   The model revision is pinned and its SHA256 is verified.
2. Clone https://github.com/PrismML-Eng/llama.cpp.git into llama.cpp-bonsai/.
   Full Git clone, checked out at release prism-b10743-adfffbe.
3. Apply the bundled router scheduling fix and build llama-server and llama-cli
   with CUDA into llama.cpp-bonsai/build/bin/.

Requires Linux, hf, git, CMake >= 3.24, make, a C++ compiler and CUDA toolkit
(nvcc). Existing model files are verified and reused; existing repositories
are reused without pulling updates. Repeated builds are incremental.

Environment:
  BONSAI_MODEL_DIR           Model destination (default: models/bonsai-2-27b)
  BONSAI_LLAMA_DIR           Fork clone (default: llama.cpp-bonsai)
  BONSAI_BUILD_JOBS          Parallel compiler jobs (default: 4)
  BONSAI_CUDA_ARCHITECTURES  CUDA architectures (default: native; RTX 3060 Ti: 86)
  CUDACXX                   Optional path to nvcc
  HF_BIN                    Optional path to the Hugging Face CLI

Start afterwards: ./serving/serve_router.sh
HELP
        exit 0 ;;
    "") ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 2 ;;
esac
if (( $# > 0 )); then
    echo "ERROR: This script takes no arguments (except --help)." >&2
    exit 2
fi

if [[ "$(uname -s)" != Linux ]]; then
    echo "ERROR: This installer targets Linux with CUDA." >&2
    exit 1
fi
for cmd in git cmake make c++ sha256sum; do
    command -v "${cmd}" >/dev/null || { echo "ERROR: Missing ${cmd}." >&2; exit 1; }
done

if [[ ! "${BUILD_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: BONSAI_BUILD_JOBS must be a positive integer." >&2
    exit 2
fi
if [[ -z "${CUDACXX:-}" ]]; then
    if command -v nvcc >/dev/null 2>&1; then
        CUDACXX="$(command -v nvcc)"
    elif [[ -x /usr/local/cuda/bin/nvcc ]]; then
        CUDACXX=/usr/local/cuda/bin/nvcc
    else
        echo "ERROR: CUDA toolkit missing. Install nvcc or set CUDACXX." >&2
        exit 1
    fi
fi
command -v "${CUDACXX}" >/dev/null || { echo "ERROR: CUDACXX is not executable." >&2; exit 1; }
export CUDACXX

if [[ -z "${HF_BIN:-}" ]]; then
    PROJECT_HF="${PROJECT_HOME}/.tools/hf-home/.local/bin/hf"
    if [[ -x "${PROJECT_HF}" ]]; then
        HF_BIN="${PROJECT_HF}"
    elif command -v hf >/dev/null 2>&1; then
        HF_BIN="$(command -v hf)"
    else
        echo "ERROR: Install the Hugging Face CLI (hf) first." >&2
        exit 1
    fi
fi
command -v "${HF_BIN}" >/dev/null || { echo "ERROR: HF_BIN is not executable." >&2; exit 1; }

export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"
export HF_HOME="${HF_HOME:-${PROJECT_HOME}/.cache/huggingface}"

verify_file() {
    [[ -f "$1" ]] && printf '%s  %s\n' "$2" "$1" | sha256sum --check --status
}

# 1. Download and verify the model before installing the source repository.
mkdir -p "${MODEL_DIR}"
MODEL_FILE="${MODEL_DIR}/${MODEL_NAME}"
if verify_file "${MODEL_FILE}" "${MODEL_SHA256}"; then
    echo "Model already present and SHA256-verified: ${MODEL_FILE}"
else
    DOWNLOAD_ARGS=()
    if [[ -f "${MODEL_FILE}" ]]; then
        echo "Existing model failed verification; downloading a fresh copy."
        DOWNLOAD_ARGS+=(--force-download)
    fi
    echo "Downloading Ternary Bonsai 2 27B PTQ1_0 (~5.95 GB)..."
    "${HF_BIN}" download "${MODEL_REPO}" "${MODEL_NAME}" \
        --revision "${MODEL_REVISION}" --local-dir "${MODEL_DIR}" "${DOWNLOAD_ARGS[@]}"
    if ! verify_file "${MODEL_FILE}" "${MODEL_SHA256}"; then
        echo "ERROR: Model checksum mismatch; rerun to retry." >&2
        exit 1
    fi
fi

"${HF_BIN}" download "${MODEL_REPO}" README.md LICENSE NOTICE.txt \
    --revision "${MODEL_REVISION}" --local-dir "${MODEL_DIR}"

clone_or_reuse() {
    local url="$1" ref="$2" dest="$3"
    if [[ -e "${dest}/.git" ]]; then
        if [[ "$(git -C "${dest}" remote get-url origin)" != "${url}" ]]; then
            echo "ERROR: Unexpected Git origin in ${dest}; choose another BONSAI_LLAMA_DIR." >&2
            exit 1
        fi
        echo "Reusing repository: ${dest}"
    elif [[ -e "${dest}" ]]; then
        echo "ERROR: ${dest} exists but is not a Git checkout." >&2
        exit 1
    else
        mkdir -p "$(dirname "${dest}")"
        git clone --branch "${ref}" "${url}" "${dest}"
    fi
}

# 2. Clone the inference engine beside the standard llama.cpp installation.
clone_or_reuse https://github.com/PrismML-Eng/llama.cpp.git "${LLAMA_REVISION}" "${LLAMA_DIR}"
if [[ "$(git -C "${LLAMA_DIR}" rev-parse HEAD)" != \
      "$(git -C "${LLAMA_DIR}" rev-parse "${LLAMA_REVISION}^{commit}")" ]]; then
    echo "ERROR: ${LLAMA_DIR} must be checked out at ${LLAMA_REVISION}." >&2
    echo "Review that checkout or choose a fresh BONSAI_LLAMA_DIR, then rerun." >&2
    exit 1
fi

# Apply the local router scheduling fix once, preserving unrelated checkout edits.
ROUTER_PATCH="${PROJECT_HOME}/installations/patches/bonsai-router-pending-eviction.patch"
if git -C "${LLAMA_DIR}" apply --reverse --check "${ROUTER_PATCH}" 2>/dev/null; then
    echo "Router scheduling patch already applied."
elif git -C "${LLAMA_DIR}" apply --check "${ROUTER_PATCH}"; then
    git -C "${LLAMA_DIR}" apply "${ROUTER_PATCH}"
else
    echo "ERROR: Router patch conflicts with this checkout; review ${LLAMA_DIR}." >&2
    exit 1
fi

# 3. Build in the fork's own tree.
echo "Building PrismML llama.cpp with CUDA (${CUDA_ARCHITECTURES}, ${BUILD_JOBS} jobs)..."
cmake -S "${LLAMA_DIR}" -B "${LLAMA_DIR}/build" \
    -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES}"
cmake --build "${LLAMA_DIR}/build" --config Release \
    --target llama-server llama-cli --parallel "${BUILD_JOBS}"
LD_LIBRARY_PATH="${RUNTIME_DIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
    "${RUNTIME_DIR}/llama-server" --version

echo "PrismML repository: ${LLAMA_DIR}"
echo "Built runtime: ${RUNTIME_DIR}/llama-server"
echo "Installed and verified: ${MODEL_FILE}"
echo "Start with: ./serving/serve_router.sh"
