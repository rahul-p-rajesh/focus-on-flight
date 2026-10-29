#!/bin/zsh
# Builds "build/Focus on Flight.app" (release), with icon, resources and an ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")/.."
# Fall back to the Command Line Tools if the Xcode license has not been accepted yet.
if ! swift --version >/dev/null 2>&1; then export DEVELOPER_DIR=/Library/Developer/CommandLineTools; fi
swift build -c release --product Contrail
BIN="$(swift build -c release --show-bin-path)/Contrail"
APP="build/Focus on Flight.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FocusOnFlight"
cp Resources/airports.json "$APP/Contents/Resources/"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"

if [[ ! -f build/AppIcon.icns || tools/icon/make_icon.swift -nt build/AppIcon.icns ]]; then
  ICONSET=build/AppIcon.iconset; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  swift tools/icon/make_icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>FocusOnFlight</string>
  <key>CFBundleIdentifier</key><string>com.rahulprajesh.contrail</string>
  <key>CFBundleName</key><string>Focus on Flight</string>
  <key>CFBundleDisplayName</key><string>Focus on Flight</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocationUsageDescription</key><string>Focus on Flight uses your location only when you choose Near me, to find a departure point close to you.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Focus on Flight uses your location only when you choose Near me, to find a departure point close to you.</string>
</dict>
</plist>
PLIST
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"
