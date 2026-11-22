#!/usr/bin/env bash
# Build the browser (HTML5) version into export/web/ and zip it for itch.io.
# Usage: tools/build_web.sh [path-to-godot-4.3]
# Needs the Godot 4.3 export templates (Editor > Manage Export Templates > Download).
set -euo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import > export_web.log 2>&1 || true
mkdir -p export/web
touch export/.gdignore   # keep Godot from importing the exported files
rm -f export/web/*
"$GODOT" --headless --path . --export-release "Web" export/web/index.html >> export_web.log 2>&1 || true
if [ ! -f export/web/index.html ] || [ ! -f export/web/index.wasm ]; then
  echo "Export failed - see export_web.log (are the 4.3 export templates installed?)" >&2
  exit 1
fi
rm -f export/AutobatLegions-web.zip
(cd export/web && zip -q -r ../AutobatLegions-web.zip .)
echo "Built export/web/ and export/AutobatLegions-web.zip"
echo "Try it locally:  python3 -m http.server 8000 --directory export/web   then open http://localhost:8000"
