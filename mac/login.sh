#!/usr/bin/env bash
set -Eeuo pipefail
set +x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v node >/dev/null 2>&1; then
  echo 'Node.js is required locally to decrypt the workflow payload.' >&2
  exit 1
fi

read -r -s -p 'Ngrok auth token (input is hidden; do not paste it into GitHub or chat): ' NGROK_AUTH_TOKEN
printf '\n'
read -r -p 'Paste the encrypted password payload from the workflow summary: ' VNC_PASSWORD_ENVELOPE
export NGROK_AUTH_TOKEN VNC_PASSWORD_ENVELOPE
node "$SCRIPT_DIR/decrypt-vnc-password.js"
result=$?
unset NGROK_AUTH_TOKEN VNC_PASSWORD_ENVELOPE
exit "$result"
