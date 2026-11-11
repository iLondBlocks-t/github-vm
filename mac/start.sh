#!/usr/bin/env bash
set -Eeuo pipefail

cat >&2 <<'MESSAGE'
MacRDP BLOCKED: no public VNC tunnel was started.

The current GitHub-hosted macos-latest runner cannot be assumed to enable
interactive Screen Sharing with Apple's kickstart CLI. Apple documents that
kickstart cannot enable Screen Sharing on macOS 12.1 and later, and that
Screen Sharing enabled by kickstart is view-only on macOS 10.14 and later.
The existing design also exposes legacy VNC over a public raw TCP endpoint;
Apple warns that third-party VNC traffic may not encrypt keystrokes.

This script intentionally exits before creating a macOS account, setting a
password, using NGROK_AUTH_TOKEN, or opening a public endpoint. Do not replace
this guard with a password printed to GitHub logs or an unauthenticated VNC
service. See README.md for the audited behavior and supported next steps.
MESSAGE
exit 78
