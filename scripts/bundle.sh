#!/bin/zsh
set -euo pipefail
cd "${0:a:h}/.."
swift build -c release
APP=".build/vphone-ws.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/vphone-ws "$APP/Contents/MacOS/vphone-ws"
echo "built $APP"
