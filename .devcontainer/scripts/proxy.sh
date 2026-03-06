#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".devcontainer/devcontainer.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "[proxy] No $ENV_FILE found, skipping."
  exit 0
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

PROFILE_FILE="/etc/profile.d/99-corp-proxy.sh"

if [ "${USE_LOCAL_PROXY:-0}" != "1" ]; then
  echo "[proxy] USE_LOCAL_PROXY!=1 -> disabling proxy (if previously set)."
  if command -v sudo >/dev/null 2>&1; then
    sudo rm -f "$PROFILE_FILE" || true
  fi
  exit 0
fi

PROXY="${LOCAL_PROXY_URL:-}"
if [ -z "$PROXY" ]; then
  echo "[proxy] LOCAL_PROXY_URL is empty. Set it in $ENV_FILE."
  exit 1
fi

# Tools wie curl/git/npm/pip lesen HTTP(S)_PROXY env vars. :contentReference[oaicite:5]{index=5}
# Codex CLI hat (noch) kein eigenes Proxy-Setting; Workaround sind env vars. :contentReference[oaicite:6]{index=6}
# Daher setzen wir (groß+klein) + ALL_PROXY.
if command -v sudo >/dev/null 2>&1; then
  sudo tee "$PROFILE_FILE" >/dev/null <<EOF
export HTTP_PROXY="$PROXY"
export HTTPS_PROXY="$PROXY"
export ALL_PROXY="$PROXY"
export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,::1}"

export http_proxy="\$HTTP_PROXY"
export https_proxy="\$HTTPS_PROXY"
export all_proxy="\$ALL_PROXY"
export no_proxy="\$NO_PROXY"
EOF
fi

echo "[proxy] Enabled via $PROXY"