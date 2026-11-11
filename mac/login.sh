#!/usr/bin/env bash
set -Eeuo pipefail

cat >&2 <<'MESSAGE'
No VNC credentials are available: the MacRDP workflow is blocked before it
creates a public tunnel. This script never prints or invents a password.
See README.md for the macOS and VNC limitations.
MESSAGE
exit 78
