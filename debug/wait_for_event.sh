#!/usr/bin/env bash
# Wait for a DebugBridge event.
#
# Usage:
#   ./debug/wait_for_event.sh screen_ready [timeout_sec] [--panel PeoplePanel]
#
# Thin wrapper around wait_for_event.py — requires Python 3.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/wait_for_event.py" "$@"
