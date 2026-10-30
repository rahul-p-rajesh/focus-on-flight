#!/bin/bash
# Builds Focus on Flight, installs it to /Applications and removes the build copy,
# so only one copy of the app exists. Quit the app first.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Focus on Flight.app"
DST="/Applications/Focus on Flight.app"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if pgrep -f "$DST/Contents/MacOS/" >/dev/null; then
  echo "Focus on Flight is running. Quit it (menu bar plane > Quit) and run this again." >&2
  exit 1
fi
bash scripts/build-app.sh
rm -rf "$DST.new"
ditto "$APP" "$DST.new"
codesign --verify --deep "$DST.new"
rm -rf "$DST"
mv "$DST.new" "$DST"
"$LSR" -f "$DST"
"$LSR" -u "$PWD/$APP" 2>/dev/null || true
rm -rf "$APP"
echo "Installed $DST"
