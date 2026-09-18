#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Enable the built-in Exa web search for local model providers, including Qwen.
export OPENCODE_ENABLE_EXA=1

exec "${PROJECT_HOME}/.tools/opencode-home/.opencode/bin/opencode" "$@"
