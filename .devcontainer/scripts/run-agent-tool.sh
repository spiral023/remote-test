#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/agent-env.sh"

TOOL_NAME="${1:-}"
if [ -z "$TOOL_NAME" ]; then
  echo "Usage: $0 <tool-name> [args...]" >&2
  exit 1
fi
shift

sanitize_agent_env

if ! REAL_BIN="$(resolve_real_binary "$TOOL_NAME")"; then
  echo "[agent-runner] Binary nicht gefunden: $TOOL_NAME" >&2
  exit 1
fi

if [ "$TOOL_NAME" = "claude" ]; then
  restore_claude_root_config
  ensure_claude_runtime_state
  persist_claude_root_config
  if "$REAL_BIN" "$@"; then
    status=0
  else
    status=$?
  fi
  persist_claude_root_config
  exit "$status"
fi

exec "$REAL_BIN" "$@"
