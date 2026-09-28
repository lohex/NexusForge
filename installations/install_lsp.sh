#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LSP_DIR="${PROJECT_HOME}/.tools/lsp"

case "${1:-}" in
    -h|--help)
        cat <<'HELP'
Usage: ./installations/install_lsp.sh

Install the Bash, Python (Pyright), and JavaScript/TypeScript language servers
locally in .tools/lsp/. Requires Node.js >= 22.22.2 and npm.
Uses fixed package versions; npm keeps a package-lock.json in .tools/lsp/.
The NexusForge opencode.sh launcher exposes the commands and enables the LSP tool;
opencode.json defines their file extensions and startup commands.

Restart OpenCode after installation:
  ./opencode.sh --agent bonsai-orchestrator

Optional: install ShellCheck through your system package manager for richer
Bash diagnostics. For Python projects, activate their virtual environment before
starting OpenCode, or configure Pyright's environment in the target project.
HELP
        exit 0 ;;
    "") ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 2 ;;
esac
if (( $# != 0 )); then
    echo "ERROR: This script takes no arguments (except --help)." >&2
    exit 2
fi

for cmd in node npm; do
    command -v "${cmd}" >/dev/null || { echo "ERROR: Install ${cmd} first." >&2; exit 1; }
done
node - <<'NODE'
const [major, minor, patch] = process.versions.node.split('.').map(Number)
if (major < 22 || (major === 22 && (minor < 22 || (minor === 22 && patch < 2)))) {
  console.error(`ERROR: Node.js >= 22.22.2 required; found ${process.versions.node}.`)
  process.exit(1)
}
NODE

mkdir -p "${LSP_DIR}"
echo "Installing NexusForge language servers into ${LSP_DIR}..."
# typescript-language-server needs the JavaScript tsserver shipped by TS 5.x.
# Do not replace this pin with TypeScript 7, which no longer ships that binary.
npm install --prefix "${LSP_DIR}" --cache "${PROJECT_HOME}/.cache/npm" \
    --save-exact --no-audit --no-fund \
    bash-language-server@5.8.1 \
    pyright@1.1.414 \
    typescript@5.9.3 \
    typescript-language-server@6.0.1

for cmd in bash-language-server pyright-langserver typescript-language-server; do
    if [[ ! -x "${LSP_DIR}/node_modules/.bin/${cmd}" ]]; then
        echo "ERROR: Missing installed command: ${cmd}" >&2
        exit 1
    fi
done
"${LSP_DIR}/node_modules/.bin/bash-language-server" --version
"${LSP_DIR}/node_modules/.bin/pyright" --version
"${LSP_DIR}/node_modules/.bin/typescript-language-server" --version
if [[ ! -f "${LSP_DIR}/node_modules/typescript/lib/tsserver.js" ]]; then
    echo "ERROR: TypeScript tsserver.js is missing." >&2
    exit 1
fi

echo "Language servers installed. Restart OpenCode via ./opencode.sh."
