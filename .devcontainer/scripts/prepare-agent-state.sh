#!/usr/bin/env bash
set -euo pipefail

state_root="${HOME}/.devcontainer-agent-state/remote-test"

mkdir -p \
  "${state_root}/codex" \
  "${state_root}/gemini" \
  "${state_root}/gemini-config" \
  "${state_root}/claude" \
  "${state_root}/claude-persist"

printf '[prepare-agent-state] ensured host state directories under %s\n' "$state_root"
