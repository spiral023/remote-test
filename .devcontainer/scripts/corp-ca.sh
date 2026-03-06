#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".devcontainer/devcontainer.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "[ca] No $ENV_FILE found, skipping."
  exit 0
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [ "${USE_CORP_CA:-0}" != "1" ]; then
  echo "[ca] USE_CORP_CA!=1 -> skipping CA install."
  exit 0
fi

GLOB="${CORP_CA_GLOB:-.devcontainer/certs/*.crt}"

shopt -s nullglob
FILES=( $GLOB )
shopt -u nullglob

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[ca] No certs matched: $GLOB"
  echo "[ca] Put your corporate root CA as PEM/CRT into .devcontainer/certs/ (gitignored)."
  exit 1
fi

if command -v sudo >/dev/null 2>&1; then
  for f in "${FILES[@]}"; do
    base="$(basename "$f")"
    sudo cp -f "$f" "/usr/local/share/ca-certificates/$base"
  done
  sudo update-ca-certificates
fi

mkdir -p /home/node/.config
BUNDLE="/home/node/.config/corp-ca.pem"
cat "${FILES[@]}" > "$BUNDLE"
chmod 0644 "$BUNDLE"

if command -v sudo >/dev/null 2>&1; then
  sudo tee /etc/profile.d/98-corp-ca.sh >/dev/null <<EOF_CA
export NODE_USE_SYSTEM_CA=1
export NODE_EXTRA_CA_CERTS="$BUNDLE"
EOF_CA
fi

echo "[ca] Installed ${#FILES[@]} corporate CA cert(s)."
