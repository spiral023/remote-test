#!/usr/bin/env bash
set -euo pipefail

check_dir() {
  local dir="$1"
  if [ -w "$dir" ]; then
    printf '[doctor] OK   writable: %s\n' "$dir"
  else
    printf '[doctor] FAIL writable: %s\n' "$dir"
    return 1
  fi
}

check_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    printf '[doctor] OK   command : %s -> %s\n' "$name" "$(command -v "$name")"
  else
    printf '[doctor] FAIL command : %s\n' "$name"
    return 1
  fi
}

check_version() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    local output=""
    if output="$($name --version 2>/dev/null | head -n 1)"; then
      printf '[doctor] OK   version : %s -> %s\n' "$name" "$output"
    else
      printf '[doctor] WARN version : %s --version failed\n' "$name"
    fi
  fi
}

check_localhost_resolution() {
  local first_result=""
  if command -v getent >/dev/null 2>&1; then
    first_result="$(getent hosts localhost 2>/dev/null | awk 'NR==1 { print $1 }')"
  fi

  if [ -n "$first_result" ]; then
    printf '[doctor] INFO  localhost-first=%s\n' "$first_result"
    if [ "$first_result" = "::1" ]; then
      printf '[doctor] WARN localhost resolves IPv6-first; claude-login applies an IPv4 workaround automatically\n'
    fi
  else
    printf '[doctor] WARN localhost resolution could not be determined via getent\n'
  fi
}

check_claude_root_config() {
  local root_config="$HOME/.claude.json"
  local persist_config="$HOME/.persist/claude/.claude.json"

  if [ -f "$root_config" ]; then
    printf '[doctor] OK   file    : %s\n' "$root_config"
  else
    printf '[doctor] WARN file    : %s missing (created after first Claude run/login)\n' "$root_config"
  fi

  if [ -f "$persist_config" ]; then
    printf '[doctor] OK   persist : %s\n' "$persist_config"
  else
    printf '[doctor] WARN persist : %s missing; Claude account context will not survive rebuilds yet\n' "$persist_config"
  fi
}

main() {
  local failed=0
  local registry="$HOME/.gemini/projects.json"

  for dir in \
    "$HOME/.codex" \
    "$HOME/.gemini" \
    "$HOME/.config/gemini" \
    "$HOME/.claude" \
    "$HOME/.persist/claude"
  do
    check_dir "$dir" || failed=1
  done

  for cmd in codex gemini claude claude-login claude-bridge; do
    check_cmd "$cmd" || failed=1
  done

  for cmd in codex gemini claude; do
    check_version "$cmd"
  done

  if [ -f "$registry" ] && [ "$(tr -d '[:space:]' < "$registry" 2>/dev/null || true)" = "{}" ]; then
    printf '[doctor] WARN legacy Gemini registry detected: %s\n' "$registry"
  fi

  printf '[doctor] INFO  HTTP_PROXY=%s\n' "${HTTP_PROXY:-<unset>}"
  printf '[doctor] INFO  HTTPS_PROXY=%s\n' "${HTTPS_PROXY:-<unset>}"
  printf '[doctor] INFO  NODE_EXTRA_CA_CERTS=%s\n' "${NODE_EXTRA_CA_CERTS:-<unset>}"
  check_localhost_resolution
  check_claude_root_config

  exit "$failed"
}

main "$@"
