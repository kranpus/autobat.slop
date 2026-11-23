#!/usr/bin/env bash
# Upload the builds in export/legion-<version>/ to itch.io with butler
# (itch's command-line uploader: https://itch.io/docs/butler/).
#
#   tools/itch_push.sh <itch-user>/<game> [version]
#   e.g. tools/itch_push.sh yourname/autobat-legions
#
# First time: install butler and run `butler login` (or set BUTLER_API_KEY to
# an API key from https://itch.io/user/settings/api-keys). Build first with
# tools/export_all.sh. Each platform goes to its own channel, so itch tags
# them for you (web, windows, linux, android); butler only uploads what
# changed. The web channel still needs "This file will be played in the
# browser" ticked once on the itch upload page.
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-}"
if [[ -z "$TARGET" || "$TARGET" != */* ]]; then
  echo "Usage: tools/itch_push.sh <itch-user>/<game> [version]"
  exit 1
fi
VERSION="${2:-$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)}"
DIR="export/legion-$VERSION"
if [[ ! -d "$DIR" ]]; then
  echo "No builds in $DIR. Run tools/export_all.sh first."
  exit 1
fi
if ! command -v butler >/dev/null; then
  echo "butler isn't installed: https://itch.io/docs/butler/installing.html"
  exit 1
fi

push() {   # <path> <channel>
  if [[ -e "$1" ]]; then
    echo "== $2  <-  $1"
    butler push "$1" "$TARGET:$2" --userversion "$VERSION"
  else
    echo "== $2: $1 not found, skipped"
  fi
}

push "$DIR/web" web
push "$DIR/windows" windows
push "$DIR/linux" linux
push "$DIR/legion-$VERSION-android.apk" android
echo "Done. Check https://itch.io/dashboard for the new uploads (version $VERSION)."
