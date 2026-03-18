#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/agent-env.sh"

sanitize_agent_env
exec node "$SCRIPT_DIR/claude-login.mjs" "$@"
