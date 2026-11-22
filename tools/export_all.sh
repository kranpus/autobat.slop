#!/usr/bin/env bash
# Build every release into a fresh folder named after the release version
# (Project Settings -> Application -> Config -> Version), e.g. export/legion-0.7/:
#   legion-0.7-web.zip       browser version (index.html at the top, for itch.io)
#   legion-0.7-windows.zip   legion-0.7.exe
#   legion-0.7-linux.zip     legion-0.7.x86_64
#   legion-0.7-android.apk
# plus the unpacked web/, windows/, linux/ and android/ folders.
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
BUILD="$(grep -oP '^config/version="\K[^"]+' project.godot)"
PROTOCOL="$(grep -oP 'const GAME_VERSION := "\K[^"]+' scripts/net/party.gd)"
NAME="legion-${BUILD:-dev}"
OUT="export/$NAME"
LOG="$OUT/export.log"
rm -rf "$OUT"
mkdir -p "$OUT"/{web,windows,linux,android}
# Keep Godot from importing the exported files as project assets.
touch export/.gdignore
echo "Exporting Autobat Legions $BUILD (protocol $PROTOCOL) into $OUT"
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
build windows "Windows Desktop" "$OUT/windows/$NAME.exe"
build linux "Linux" "$OUT/linux/$NAME.x86_64"
if [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
  build android "Android" "$OUT/android/$NAME.apk" release
else
  build android "Android" "$OUT/android/$NAME.apk" debug
fi

# Zips to hand out / upload.
(cd "$OUT/web" && [ -f index.html ] && zip -q -r "../$NAME-web.zip" .)
(cd "$OUT/windows" && [ -f "$NAME.exe" ] && zip -q -r "../$NAME-windows.zip" .)
(cd "$OUT/linux" && [ -f "$NAME.x86_64" ] && chmod +x "$NAME.x86_64" && zip -q -r "../$NAME-linux.zip" .)
[ -f "$OUT/android/$NAME.apk" ] && cp "$OUT/android/$NAME.apk" "$OUT/$NAME-android.apk"
echo "Done: $ok built, $failed failed. Files in $OUT/"
[ "$failed" -eq 0 ]
