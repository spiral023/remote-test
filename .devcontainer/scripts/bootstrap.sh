#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[bootstrap] %s\n' "$*"
}

warn() {
  printf '[bootstrap][warn] %s\n' "$*" >&2
}

has_writable_dir() {
  local dir="$1"
  mkdir -p "$dir" 2>/dev/null || true
  [ -w "$dir" ]
}

maybe_migrate_legacy_gemini_registry() {
  local registry="$HOME/.gemini/projects.json"
  local backup="$HOME/.gemini/projects.json.legacy-empty.bak"
  local normalized=""

  if [ ! -f "$registry" ]; then
    return 0
  fi

  normalized="$(tr -d '[:space:]' < "$registry" 2>/dev/null || true)"
  if [ "$normalized" != "{}" ]; then
    return 0
  fi

  if [ -f "$backup" ]; then
    rm -f "$registry"
    log "Leere Legacy-Gemini-Registry entfernt: $registry"
    return 0
  fi

  mv "$registry" "$backup"
  log "Leere Legacy-Gemini-Registry verschoben: $registry -> $backup"
}

sync_file_if_newer() {
  local source="$1"
  local target="$2"
  local label="$3"

  [ -f "$source" ] || return 0
  mkdir -p "$(dirname "$target")"

  if [ ! -f "$target" ] || [ "$source" -nt "$target" ]; then
    cp -p "$source" "$target"
    log "$label synchronisiert: $source -> $target"
  fi
}

sync_claude_root_config() {
  local root_config="$HOME/.claude.json"
  local persist_config="$HOME/.persist/claude/.claude.json"

  sync_file_if_newer "$persist_config" "$root_config" "Claude Root-Config wiederhergestellt"
  sync_file_if_newer "$root_config" "$persist_config" "Claude Root-Config persistiert"
}

ensure_claude_runtime_state() {
  local helper="$PWD/.devcontainer/scripts/claude-config.mjs"

  if [ ! -f "$helper" ]; then
    if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
      helper="$git_root/.devcontainer/scripts/claude-config.mjs"
    fi
  fi

  if [ -f "$helper" ]; then
    node "$helper" >/dev/null 2>&1 || true
  fi
}

write_shell_wrapper() {
  local name="$1"
  local script_rel="$2"
  local wrapper="$HOME/.local/agent-bin/$name"
  local shim="$HOME/.local/bin/$name"

  cat > "$wrapper" <<EOF_WRAPPER
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_REL="$script_rel"

if [ -f "\$PWD/\$SCRIPT_REL" ]; then
  exec bash "\$PWD/\$SCRIPT_REL" "$name" "\$@"
fi

if git_root="\$(git rev-parse --show-toplevel 2>/dev/null)"; then
  if [ -f "\$git_root/\$SCRIPT_REL" ]; then
    exec bash "\$git_root/\$SCRIPT_REL" "$name" "\$@"
  fi
fi

echo "Konnte \$SCRIPT_REL nicht finden. Bitte aus dem Repo-Verzeichnis ausführen." >&2
exit 1
EOF_WRAPPER

  chmod +x "$wrapper"
  ln -snf "../agent-bin/$name" "$shim"
  log "Wrapper erstellt: $wrapper"
  log "Shim erstellt   : $shim -> ../agent-bin/$name"
}

write_repo_script_wrapper() {
  local name="$1"
  local script_rel="$2"
  local runner="$3"
  local wrapper="$HOME/.local/agent-bin/$name"
  local shim="$HOME/.local/bin/$name"

  cat > "$wrapper" <<EOF_WRAPPER
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_REL="$script_rel"

if [ -f "\$PWD/\$SCRIPT_REL" ]; then
  exec $runner "\$PWD/\$SCRIPT_REL" "\$@"
fi

if git_root="\$(git rev-parse --show-toplevel 2>/dev/null)"; then
  if [ -f "\$git_root/\$SCRIPT_REL" ]; then
    exec $runner "\$git_root/\$SCRIPT_REL" "\$@"
  fi
fi

echo "Konnte \$SCRIPT_REL nicht finden. Bitte aus dem Repo-Verzeichnis ausführen." >&2
exit 1
EOF_WRAPPER

  chmod +x "$wrapper"
  ln -snf "../agent-bin/$name" "$shim"
  log "Helper erstellt: $wrapper"
  log "Shim erstellt   : $shim -> ../agent-bin/$name"
}

main() {
  log "Bootstrap starting as user: $(id -un) (uid=$(id -u), gid=$(id -g))"
  log "HOME=$HOME"

  mkdir -p "$HOME/.local/bin" "$HOME/.local/agent-bin"

  local dir=""
  for dir in \
    "$HOME/.codex" \
    "$HOME/.gemini" \
    "$HOME/.config/gemini" \
    "$HOME/.claude" \
    "$HOME/.persist/claude"
  do
    if has_writable_dir "$dir"; then
      log "Verzeichnis bereit: $dir"
    else
      warn "$dir ist nicht schreibbar. Persistenz oder Logins können fehlschlagen."
    fi
  done

  maybe_migrate_legacy_gemini_registry
  sync_claude_root_config
  ensure_claude_runtime_state
  sync_claude_root_config

  write_shell_wrapper "codex" ".devcontainer/scripts/run-agent-tool.sh"
  write_shell_wrapper "gemini" ".devcontainer/scripts/run-agent-tool.sh"
  write_shell_wrapper "claude" ".devcontainer/scripts/run-agent-tool.sh"
  write_repo_script_wrapper "claude-login" ".devcontainer/scripts/run-claude-login.sh" "bash"
  write_repo_script_wrapper "claude-bridge" ".devcontainer/scripts/claude-ipv4-bridge.mjs" "node"
  write_repo_script_wrapper "agent-doctor" ".devcontainer/scripts/doctor.sh" "bash"

  log "Bootstrap finished OK."
  log "Verwende für Claude-Login bevorzugt: claude-login"
  log "Verwende für Diagnose: agent-doctor"
}

main "$@"
