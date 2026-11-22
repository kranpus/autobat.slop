#!/usr/bin/env bash
# Build every release into a fresh folder:  export/<game version>/
#   web/      browser version  (+ AutobatLegions-web.zip for itch.io)
#   windows/  AutobatLegions.exe (+ zip)
#   linux/    AutobatLegions.x86_64 (+ zip)
#   android/  AutobatLegions.apk
#
# Usage: tools/export_all.sh [path-to-godot-4.3]
# Needs the export templates (python3 tools/fetch_export_templates.py web windows linux android).
# Android also needs Java 17+ and the Android SDK (build-tools + platform-tools):
#   ANDROID_HOME=/path/to/android-sdk
# and, for a release-signed APK (needed to publish and to update installs later):
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH, GODOT_ANDROID_KEYSTORE_RELEASE_USER,
#   GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
# Without a release key the APK is debug-signed (fine for testing on your phone).
set -uo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
VERSION="$(grep -oP 'const GAME_VERSION := "\K[^"]+' scripts/net/party.gd)"
OUT="export/$VERSION"
LOG="$OUT/export.log"
rm -rf "$OUT"
mkdir -p "$OUT"/{web,windows,linux,android}
# Keep Godot from importing the exported files as project assets.
touch export/.gdignore
echo "Exporting $VERSION into $OUT"
"$GODOT" --headless --path . --import > "$LOG" 2>&1 || true

# Point Godot at the Android SDK (it reads the path from its editor settings).
if [ -n "${ANDROID_HOME:-}" ]; then
  for f in "$HOME/.config/godot/editor_settings-4.3.tres"; do
    [ -f "$f" ] && sed -i "s#^export/android/android_sdk_path = .*#export/android/android_sdk_path = \"$ANDROID_HOME\"#" "$f"
  done
fi

ok=0; failed=0
build() {  # name preset path mode
  local name="$1" preset="$2" path="$3" mode="${4:-release}"
  printf '  %-8s ' "$name"
  "$GODOT" --headless --path . "--export-$mode" "$preset" "$path" >> "$LOG" 2>&1
  if [ -s "$path" ]; then
    echo "ok ($(du -h "$path" | cut -f1))"; ok=$((ok+1))
  else
    echo "FAILED (see $LOG)"; failed=$((failed+1))
  fi
}
build web "Web" "$OUT/web/index.html"
build windows "Windows Desktop" "$OUT/windows/AutobatLegions.exe"
build linux "Linux" "$OUT/linux/AutobatLegions.x86_64"
if [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
  build android "Android" "$OUT/android/AutobatLegions.apk" release
else
  build android "Android" "$OUT/android/AutobatLegions.apk" debug
fi

# Zips to hand out / upload.
(cd "$OUT/web" && [ -f index.html ] && zip -q -r ../AutobatLegions-web.zip .)
(cd "$OUT/windows" && [ -f AutobatLegions.exe ] && zip -q -r ../AutobatLegions-windows.zip .)
(cd "$OUT/linux" && [ -f AutobatLegions.x86_64 ] && chmod +x AutobatLegions.x86_64 && zip -q -r ../AutobatLegions-linux.zip .)
[ -f "$OUT/android/AutobatLegions.apk" ] && cp "$OUT/android/AutobatLegions.apk" "$OUT/AutobatLegions-android.apk"
echo "Done: $ok built, $failed failed. Files in $OUT/"
[ "$failed" -eq 0 ]
