#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${PROJECT_HOME}/.tools/opencode-home/.opencode/bin/opencode" "$@"
