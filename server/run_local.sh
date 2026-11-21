#!/usr/bin/env bash
# Run the matchmaking server on this machine for testing.
# Usage: server/run_local.sh [path-to-godot] [port]
set -euo pipefail
GODOT="${1:-godot}"
PORT="${2:-24702}"
cd "$(dirname "$0")/.."
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  "$GODOT" --headless --path . --import || true
fi
exec "$GODOT" --headless --path . -- --server --port="$PORT"
