#!/usr/bin/env bash
set -euo pipefail

unset_if_empty() {
  local var_name="$1"
  if [ "${!var_name+x}" = "x" ] && [ -z "${!var_name}" ]; then
    unset "$var_name"
  fi
}

sanitize_agent_env() {
  local v=""

  for v in \
    HTTP_PROXY HTTPS_PROXY ALL_PROXY \
    http_proxy https_proxy all_proxy \
    NO_PROXY no_proxy \
    NODE_USE_SYSTEM_CA \
    SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE
  do
    unset_if_empty "$v"
  done

  if [[ "${NODE_EXTRA_CA_CERTS:-}" =~ ^[A-Za-z]:\\ ]]; then
    unset NODE_EXTRA_CA_CERTS
  fi

  local sys_ca="/etc/ssl/certs/ca-certificates.crt"
  local corp_ca="$HOME/.config/corp-ca.pem"
  local ca_bundle=""

  if [ -r "$corp_ca" ]; then
    ca_bundle="$corp_ca"
  elif [ -r "$sys_ca" ]; then
    ca_bundle="$sys_ca"
  fi

  if [ -n "$ca_bundle" ]; then
    export SSL_CERT_FILE="$ca_bundle"
    export REQUESTS_CA_BUNDLE="$ca_bundle"
    export CURL_CA_BUNDLE="$ca_bundle"
    export NODE_EXTRA_CA_CERTS="$ca_bundle"
    export NODE_USE_SYSTEM_CA=1
  fi
}

resolve_real_binary() {
  local name="$1"
  local wrapper_agent="$HOME/.local/agent-bin/$name"
  local wrapper_bin="$HOME/.local/bin/$name"
  local candidate=""

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if [ "$candidate" != "$wrapper_agent" ] && [ "$candidate" != "$wrapper_bin" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(which -a "$name" 2>/dev/null | awk '!seen[$0]++')

  return 1
}

claude_root_config_path() {
  printf '%s\n' "$HOME/.claude.json"
}

claude_persist_root_config_path() {
  printf '%s\n' "$HOME/.persist/claude/.claude.json"
}

claude_config_helper_path() {
  if [ -n "${SCRIPT_DIR:-}" ] && [ -f "$SCRIPT_DIR/claude-config.mjs" ]; then
    printf '%s\n' "$SCRIPT_DIR/claude-config.mjs"
    return 0
  fi

  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    if [ -f "$git_root/.devcontainer/scripts/claude-config.mjs" ]; then
      printf '%s\n' "$git_root/.devcontainer/scripts/claude-config.mjs"
      return 0
    fi
  fi

  return 1
}

sync_file_if_newer() {
  local source="$1"
  local target="$2"

  [ -f "$source" ] || return 0
  mkdir -p "$(dirname "$target")"

  if [ ! -f "$target" ] || [ "$source" -nt "$target" ]; then
    cp -p "$source" "$target"
  fi
}

restore_claude_root_config() {
  local source=""
  local target=""

  source="$(claude_persist_root_config_path)"
  target="$(claude_root_config_path)"
  sync_file_if_newer "$source" "$target"
}

persist_claude_root_config() {
  local source=""
  local target=""

  source="$(claude_root_config_path)"
  target="$(claude_persist_root_config_path)"
  sync_file_if_newer "$source" "$target"
}

ensure_claude_runtime_state() {
  local helper=""
  if ! helper="$(claude_config_helper_path)"; then
    return 0
  fi

  node "$helper" >/dev/null 2>&1 || true
}
