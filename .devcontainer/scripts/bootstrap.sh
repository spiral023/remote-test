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

resolve_real_binary() {
  local name="$1"
  local candidate=""

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if [ "$candidate" != "$HOME/.local/bin/$name" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(which -a "$name" 2>/dev/null | awk '!seen[$0]++')

  return 1
}

write_env_wrapper() {
  local name="$1"
  local real_bin="$2"
  local wrapper="$HOME/.local/bin/$name"

  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail

unset_if_empty() {
  local var_name="\$1"
  if [ "\${!var_name+x}" = "x" ] && [ -z "\${!var_name}" ]; then
    unset "\$var_name"
  fi
}

for v in \\
  HTTP_PROXY HTTPS_PROXY ALL_PROXY \\
  http_proxy https_proxy all_proxy \\
  NO_PROXY no_proxy \\
  NODE_USE_SYSTEM_CA \\
  SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE
do
  unset_if_empty "\$v"
done

SYS_CA="/etc/ssl/certs/ca-certificates.crt"
CORP_CA="\$HOME/.config/corp-ca.pem"
CA_BUNDLE=""

if [ -r "\$CORP_CA" ]; then
  CA_BUNDLE="\$CORP_CA"
elif [ -r "\$SYS_CA" ]; then
  CA_BUNDLE="\$SYS_CA"
fi

if [[ "\${NODE_EXTRA_CA_CERTS:-}" =~ ^[A-Za-z]:\\\\ ]]; then
  unset NODE_EXTRA_CA_CERTS
fi

if [ -n "\$CA_BUNDLE" ]; then
  export SSL_CERT_FILE="\$CA_BUNDLE"
  export REQUESTS_CA_BUNDLE="\$CA_BUNDLE"
  export CURL_CA_BUNDLE="\$CA_BUNDLE"
  export NODE_EXTRA_CA_CERTS="\$CA_BUNDLE"
  export NODE_USE_SYSTEM_CA=1
fi

exec "$real_bin" "\$@"
EOF

  chmod +x "$wrapper"
  log "Wrapper erstellt: $wrapper -> $real_bin"
}

write_repo_node_wrapper() {
  local name="$1"
  local script_rel="$2"
  local wrapper="$HOME/.local/bin/$name"

  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_REL="$script_rel"

if [ -f "\$PWD/\$SCRIPT_REL" ]; then
  exec node "\$PWD/\$SCRIPT_REL" "\$@"
fi

if git_root="\$(git rev-parse --show-toplevel 2>/dev/null)"; then
  if [ -f "\$git_root/\$SCRIPT_REL" ]; then
    exec node "\$git_root/\$SCRIPT_REL" "\$@"
  fi
fi

echo "Konnte \$SCRIPT_REL nicht finden. Bitte aus dem Repo-Verzeichnis ausführen." >&2
exit 1
EOF

  chmod +x "$wrapper"
  log "Helper erstellt: $wrapper"
}

write_claude_login_wrapper() {
  local real_claude="$1"
  local wrapper="$HOME/.local/bin/claude-login"

  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail

unset_if_empty() {
  local var_name="\$1"
  if [ "\${!var_name+x}" = "x" ] && [ -z "\${!var_name}" ]; then
    unset "\$var_name"
  fi
}

for v in \\
  HTTP_PROXY HTTPS_PROXY ALL_PROXY \\
  http_proxy https_proxy all_proxy \\
  NO_PROXY no_proxy \\
  NODE_USE_SYSTEM_CA \\
  SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE
do
  unset_if_empty "\$v"
done

SYS_CA="/etc/ssl/certs/ca-certificates.crt"
CORP_CA="\$HOME/.config/corp-ca.pem"
CA_BUNDLE=""

if [ -r "\$CORP_CA" ]; then
  CA_BUNDLE="\$CORP_CA"
elif [ -r "\$SYS_CA" ]; then
  CA_BUNDLE="\$SYS_CA"
fi

if [[ "\${NODE_EXTRA_CA_CERTS:-}" =~ ^[A-Za-z]:\\\\ ]]; then
  unset NODE_EXTRA_CA_CERTS
fi

if [ -n "\$CA_BUNDLE" ]; then
  export SSL_CERT_FILE="\$CA_BUNDLE"
  export REQUESTS_CA_BUNDLE="\$CA_BUNDLE"
  export CURL_CA_BUNDLE="\$CA_BUNDLE"
  export NODE_EXTRA_CA_CERTS="\$CA_BUNDLE"
  export NODE_USE_SYSTEM_CA=1
fi

SCRIPT_REL=".devcontainer/scripts/claude-login.mjs"

if [ -f "\$PWD/\$SCRIPT_REL" ]; then
  exec node "\$PWD/\$SCRIPT_REL" "$real_claude" "\$@"
fi

if git_root="\$(git rev-parse --show-toplevel 2>/dev/null)"; then
  if [ -f "\$git_root/\$SCRIPT_REL" ]; then
    exec node "\$git_root/\$SCRIPT_REL" "$real_claude" "\$@"
  fi
fi

echo "Konnte \$SCRIPT_REL nicht finden. Bitte aus dem Repo-Verzeichnis ausführen." >&2
exit 1
EOF

  chmod +x "$wrapper"
  log "Helper erstellt: $wrapper"
}

main() {
  log "Bootstrap starting as user: $(id -un) (uid=$(id -u), gid=$(id -g))"
  log "HOME=$HOME"

  mkdir -p "$HOME/.local/bin"

  if has_writable_dir "$HOME/.codex"; then
    if [ ! -f "$HOME/.codex/config.toml" ]; then
      cat > "$HOME/.codex/config.toml" <<'EOF'
# User-level Codex config
# Projektbezogene Overrides kannst du zusätzlich in .codex/config.toml ablegen.
EOF
      chmod 600 "$HOME/.codex/config.toml"
      log "Erstellt: $HOME/.codex/config.toml"
    fi
  else
    warn "~/.codex ist nicht schreibbar. Codex kann Konfiguration/Login evtl. nicht persistieren."
  fi

  if has_writable_dir "$HOME/.gemini"; then
    if [ ! -f "$HOME/.gemini/projects.json" ]; then
      printf '{}\n' > "$HOME/.gemini/projects.json"
      chmod 600 "$HOME/.gemini/projects.json"
      log "Erstellt: $HOME/.gemini/projects.json"
    fi
  else
    warn "~/.gemini ist nicht schreibbar. Gemini kann Konfiguration/Login evtl. nicht persistieren."
  fi

  if ! has_writable_dir "$HOME/.config/gemini"; then
    warn "~/.config/gemini ist nicht schreibbar. Gemini-IDE-Begleitdateien können Probleme machen."
  fi

  if ! has_writable_dir "$HOME/.claude"; then
    warn "~/.claude ist nicht schreibbar. Claude kann Konfiguration/Login evtl. nicht persistieren."
  fi

  if ! has_writable_dir "$HOME/.persist/claude"; then
    warn "~/.persist/claude ist nicht schreibbar. Claude-Sessiondaten können Probleme machen."
  fi

  local tool=""
  local real_bin=""

  for tool in codex gemini claude; do
    if real_bin="$(resolve_real_binary "$tool")"; then
      write_env_wrapper "$tool" "$real_bin"
      if [ "$tool" = "claude" ]; then
        write_claude_login_wrapper "$real_bin"
      fi
    else
      warn "Binary nicht gefunden, Wrapper übersprungen: $tool"
    fi
  done

  write_repo_node_wrapper "claude-bridge" ".devcontainer/scripts/claude-ipv4-bridge.mjs"

  log "Bootstrap finished OK."
  log "Verwende für Claude-Login bevorzugt: claude-login"
}

main "$@"