#!/bin/zsh
# Builds the menu-bar app + WidgetKit extension next to this script.
#   ./build.sh             build
#   ./build.sh --install   build, copy to /Applications and relaunch
#   ./build.sh --dmg       build and package a DMG to hand out
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

APP_NAME="${APP_NAME:-Filmo Time}"   # shown in Finder, the menu bar and the widget gallery
VERSION="1.0"
BUNDLE_ID="local.desktime-widget"
APP="$APP_NAME.app"
EXT="$APP/Contents/PlugIns/DeskTimeWidgetExtension.appex"
FLAGS=(-O -parse-as-library -swift-version 5 -target arm64-apple-macos14)

rm -rf "$APP"
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS" "$EXT/Contents/Resources"

# Icons from the brand SVGs (macOS icons keep ~10% margin around the artwork).
swiftc -O -o build/render Resources/render.swift
rm -rf build/AppIcon.iconset && mkdir build/AppIcon.iconset
for s in 16 32 128 256 512; do
  ./build/render Resources/filmo-icono-app.svg build/AppIcon.iconset/icon_${s}x${s}.png $s 0.09
  ./build/render Resources/filmo-icono-app.svg build/AppIcon.iconset/icon_${s}x${s}@2x.png $((s*2)) 0.09
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
./build/render Resources/filmo-simbolo.svg build/filmo-simbolo.png 128
cp build/filmo-simbolo.png "$APP/Contents/Resources/"
cp build/filmo-simbolo.png "$EXT/Contents/Resources/"

swiftc "${FLAGS[@]}" -o "$APP/Contents/MacOS/DeskTimeWidget" App/App.swift Shared/Shared.swift
# Widget extensions start in NSExtensionMain, not in their own main (Xcode does the same).
swiftc "${FLAGS[@]}" -application-extension -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$EXT/Contents/MacOS/DeskTimeWidgetExtension" Widget/Widget.swift Shared/Shared.swift

plist() { # id executable package-type extra-xml
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$1</string>
  <key>CFBundleExecutable</key><string>$2</string>
  <key>CFBundlePackageType</key><string>$3</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  $4
</dict></plist>
PLIST
}
plist "$BUNDLE_ID" DeskTimeWidget APPL '<key>LSUIElement</key><true/><key>CFBundleIconFile</key><string>AppIcon</string>' \
  > "$APP/Contents/Info.plist"
plist "$BUNDLE_ID.widget" DeskTimeWidgetExtension XPC! \
  '<key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>' \
  > "$EXT/Contents/Info.plist"

# Widget extensions must be sandboxed; it only needs the network and read access to the saved API key.
cat > build/widget.entitlements <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
  <array><string>/Library/Application Support/DeskTimeWidget/</string></array>
</dict></plist>
ENT
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
IDENTITY=${IDENTITY:--}
codesign --force --sign "$IDENTITY" --entitlements build/widget.entitlements "$EXT" >/dev/null
codesign --force --sign "$IDENTITY" "$APP" >/dev/null
echo "Built $PWD/$APP (signed with: $IDENTITY)"

case "${1:-}" in
--install)
  pkill -f "/Contents/MacOS/DeskTimeWidget$" || true
  rm -rf "/Applications/DeskTime Widget.app" "/Applications/$APP"
  cp -R "$APP" /Applications/
  pluginkit -a "/Applications/$EXT"
  open "/Applications/$APP"
  echo "Installed /Applications/$APP"
  ;;
--dmg)
  STAGE=build/dmg
  rm -rf "$STAGE" && mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Aplicaciones"
  cp Resources/LEEME.txt "$STAGE/LEEME.txt"
  DMG="dist/${APP_NAME// /-}.dmg"   # stable name so README links to releases/latest/download
  mkdir -p dist && rm -f "$DMG"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -quiet "$DMG"
  codesign --force --sign "$IDENTITY" "$DMG" >/dev/null
  echo "DMG: $PWD/$DMG"
  ;;
esac
