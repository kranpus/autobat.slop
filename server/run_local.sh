#!/usr/bin/env bash
# Run the matchmaking server on this machine for testing.
# Usage: server/run_local.sh [path-to-godot] [port]
set -euo pipefail
GODOT="${1:-godot}"
PORT="${2:-24702}"
cd "$(dirname "$0")/.."
# Import every time so scripts added by updates are registered (quick after
# the first run); otherwise the server fails with "Identifier ... not declared".
"$GODOT" --headless --path . --import > server/import.log 2>&1 || true
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  echo "Importing the project failed; see server/import.log" >&2
  exit 1
fi
exec "$GODOT" --headless --path . -- --server --port="$PORT"
