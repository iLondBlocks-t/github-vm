#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077

KICKSTART=/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'MacRDP requires the GitHub-hosted macOS runner.' >&2
  exit 1
fi
if [[ -z "${NGROK_AUTH_TOKEN:-}" ]]; then
  echo 'NGROK_AUTH_TOKEN is missing; no tunnel was started.' >&2
  exit 1
fi
if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo 'GitHub Actions step summary is unavailable; refusing to publish connection details.' >&2
  exit 1
fi
if [[ ! -x "$KICKSTART" ]]; then
  echo 'Apple Remote Management kickstart tool is not present on this runner.' >&2
  exit 1
fi

printf '::add-mask::%s\n' "$NGROK_AUTH_TOKEN"
MACOS_USER="$(id -un)"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/macrdp.XXXXXX")"
NGROK_CONFIG="$WORKDIR/ngrok.yml"
NGROK_LOG="$WORKDIR/ngrok.log"
NGROK_PID=''

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [[ -n "$NGROK_PID" ]] && kill -0 "$NGROK_PID" 2>/dev/null; then
    kill "$NGROK_PID" 2>/dev/null || true
    wait "$NGROK_PID" 2>/dev/null || true
  fi
  sudo "$KICKSTART" -deactivate >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
  unset NGROK_AUTH_TOKEN VNC_PASSWORD
  exit "$rc"
}
trap cleanup EXIT INT TERM

if ! command -v brew >/dev/null 2>&1; then
  echo 'Homebrew is not installed on the macOS runner.' >&2
  exit 1
fi
if ! command -v ngrok >/dev/null 2>&1; then
  brew install ngrok/ngrok/ngrok >/dev/null
fi
ngrok version >/dev/null

# VNC legacy authentication accepts at most eight characters. Generate exactly
# eight uniformly random URL-safe characters; never truncate a longer value.
VNC_PASSWORD="$(node <<'NODE'
const crypto = require('crypto');
const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
let value = '';
for (let i = 0; i < 8; i++) value += alphabet[crypto.randomInt(alphabet.length)];
process.stdout.write(value);
NODE
)"
if [[ ${#VNC_PASSWORD} -ne 8 ]]; then
  echo 'Could not generate the required VNC password.' >&2
  exit 1
fi
printf '::add-mask::%s\n' "$VNC_PASSWORD"
export VNC_PASSWORD

# Use the runner's existing macOS account and limit Remote Management to it.
# Keep kickstart output private because third-party tools can echo arguments.
if ! sudo "$KICKSTART" -activate -configure -allowAccessFor -specifiedUsers \
  -users "$MACOS_USER" -privs -all >"$WORKDIR/kickstart-config.log" 2>&1; then
  echo 'Apple Remote Management configuration failed; no Ngrok tunnel was started.' >&2
  exit 1
fi
if ! sudo "$KICKSTART" -configure -clientopts -setvnclegacy -vnclegacy yes \
  -setvncpw "$VNC_PASSWORD" >"$WORKDIR/kickstart-vnc.log" 2>&1; then
  echo 'macOS rejected VNC legacy authentication; no Ngrok tunnel was started.' >&2
  exit 1
fi
if ! sudo "$KICKSTART" -restart -agent -console >"$WORKDIR/kickstart-restart.log" 2>&1; then
  echo 'Apple Remote Management agent could not be restarted.' >&2
  exit 1
fi

check_rfb() {
  python3 - "$1" "$2" <<'PY'
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
def exact(sock, n):
    chunks = bytearray()
    while len(chunks) < n:
        part = sock.recv(n - len(chunks))
        if not part:
            raise RuntimeError('VNC closed during RFB handshake')
        chunks.extend(part)
    return bytes(chunks)
with socket.create_connection((host, port), timeout=8) as s:
    s.settimeout(8)
    banner = exact(s, 12)
    if not banner.startswith(b'RFB '):
        raise RuntimeError('service did not return an RFB banner')
    s.sendall(b'RFB 003.008\n')
    count = exact(s, 1)[0]
    if count == 0:
        raise RuntimeError('VNC server offered no security types')
    types = exact(s, count)
    if 2 not in types:
        raise RuntimeError('VNC legacy password authentication is not offered')
    s.sendall(b'\x02')
    exact(s, 16)  # VNC authentication challenge; do not log it.
PY
}

ready=0
for _ in $(seq 1 40); do
  if check_rfb 127.0.0.1 5900 >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if [[ "$ready" -ne 1 ]]; then
  echo 'Port 5900 did not provide a VNC legacy-authentication handshake; no Ngrok tunnel was started.' >&2
  exit 1
fi

# Store the token only in a mode-600 temporary config; never put it in source or logs.
NGROK_CONFIG="$NGROK_CONFIG" node <<'NODE'
const fs = require('fs');
const token = process.env.NGROK_AUTH_TOKEN;
if (!token) process.exit(2);
const yaml = `version: "3"\nagent:\n  authtoken: ${JSON.stringify(token)}\n`;
fs.writeFileSync(process.env.NGROK_CONFIG, yaml, { mode: 0o600 });
NODE

ngrok tcp 5900 --config="$NGROK_CONFIG" --log=stdout >"$NGROK_LOG" 2>&1 &
NGROK_PID=$!
VNC_HOST=''
VNC_PORT=''
for _ in $(seq 1 45); do
  if ! kill -0 "$NGROK_PID" 2>/dev/null; then
    if grep -q 'ERR_NGROK_8013' "$NGROK_LOG"; then
      echo 'Ngrok TCP requires a valid card on the free account; Ngrok says the card is not charged. No endpoint was established.' >&2
    else
      echo 'Ngrok exited before establishing a TCP endpoint. Its private log was withheld to avoid credential leakage.' >&2
    fi
    exit 1
  fi
  if curl --silent --show-error --fail http://127.0.0.1:4040/api/tunnels \
      -o "$WORKDIR/tunnels.json" 2>/dev/null; then
    endpoint="$(node - "$WORKDIR/tunnels.json" <<'NODE'
const fs = require('fs');
try {
  const data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const tunnel = (data.tunnels || []).find(t => t.proto === 'tcp');
  if (!tunnel || !tunnel.public_url || !String(tunnel.config?.addr || '').endsWith(':5900')) process.exit(1);
  const url = new URL(tunnel.public_url);
  process.stdout.write(`${url.hostname}\t${url.port}`);
} catch { process.exit(1); }
NODE
)" || true
    if [[ -n "$endpoint" ]]; then
      IFS=$'\t' read -r VNC_HOST VNC_PORT <<< "$endpoint"
      break
    fi
  fi
  sleep 2
done
if [[ -z "$VNC_HOST" || -z "$VNC_PORT" ]]; then
  echo 'Ngrok local API did not confirm a TCP endpoint to port 5900; no connection details were published.' >&2
  exit 1
fi

# Verify the public endpoint reaches the VNC RFB service, not merely that ngrok started.
if ! check_rfb "$VNC_HOST" "$VNC_PORT" >/dev/null 2>&1; then
  echo 'Public Ngrok endpoint did not complete the VNC RFB legacy-authentication handshake.' >&2
  exit 1
fi

# Encrypt the generated VNC password with a key derived from the existing Ngrok token.
# Only this authenticated ciphertext is written to the public workflow summary.
VNC_PASSWORD_ENVELOPE="$(node <<'NODE'
const crypto = require('crypto');
const token = process.env.NGROK_AUTH_TOKEN;
const password = process.env.VNC_PASSWORD;
if (!token || !password) process.exit(2);
const salt = crypto.randomBytes(16);
const nonce = crypto.randomBytes(12);
const info = Buffer.from('github-vm/MacRDP/VNC-password/v1');
const aad = Buffer.from('github-vm:MacRDP:v1');
const key = Buffer.from(crypto.hkdfSync('sha256', Buffer.from(token), salt, info, 32));
const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
cipher.setAAD(aad);
const ciphertext = Buffer.concat([cipher.update(password, 'utf8'), cipher.final()]);
const tag = cipher.getAuthTag();
const payload = Buffer.concat([salt, nonce, tag, ciphertext]).toString('base64url');
process.stdout.write(`v1:${payload}`);
NODE
)"

printf 'Ngrok Host: %s\nNgrok TCP Port: %s\nmacOS account authorized for Remote Management: %s\n' \
  "$VNC_HOST" "$VNC_PORT" "$MACOS_USER"
printf 'Validation: local and public TCP/RFB handshakes passed; Android login and interactive control are not yet verified.\n'
{
  printf '# MacRDP connection details\n\n'
  printf '**Status:** `VNC_ENDPOINT_VERIFIED` (Android authentication and interactive control are not yet verified)\n\n'
  printf '**Operating System:** macOS %s\n\n' "$(sw_vers -productVersion)"
  printf '**Connection Protocol:** VNC over Ngrok TCP\n\n'
  printf '**VNC Host:** `%s`\n\n' "$VNC_HOST"
  printf '**VNC Port:** `%s`\n\n' "$VNC_PORT"
  printf '**macOS account allowed by Remote Management:** `%s`\n\n' "$MACOS_USER"
  printf '**VNC authentication:** VNC legacy password only; the VNC viewer may not ask for a username.\n\n'
  printf '**Encrypted password payload:** `%s`\n\n' "$VNC_PASSWORD_ENVELOPE"
  printf 'On a trusted device, run `bash mac/login.sh` from a checkout of this repository. Enter the Ngrok token privately when prompted and paste this encrypted payload; the helper prints the VNC password only in that local terminal.\n\n'
  printf '**Password constraint:** exactly 8 random URL-safe characters, generated for this run; legacy VNC cannot use a longer password.\n\n'
  printf '**Transport warning:** legacy VNC over raw TCP may not encrypt screen contents or keystrokes. Do not use this session for sensitive data.\n'
} >> "$GITHUB_STEP_SUMMARY"

# Keep the endpoint alive, and fail if either process or the local VNC listener disappears.
while true; do
  if ! kill -0 "$NGROK_PID" 2>/dev/null; then
    echo 'Ngrok tunnel process stopped unexpectedly.' >&2
    exit 1
  fi
  if ! python3 - <<'PY'
import socket, sys
try:
    with socket.create_connection(('127.0.0.1', 5900), timeout=3): pass
except OSError:
    sys.exit(1)
PY
  then
    echo 'VNC port 5900 stopped listening unexpectedly.' >&2
    exit 1
  fi
  sleep 20
done
