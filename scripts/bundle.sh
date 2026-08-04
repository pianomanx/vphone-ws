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

# Stamp the release version (from the git tag, passed by CI) so the About panel
# shows it. Dev builds leave VPHONE_WS_VERSION unset and keep the plist default.
if [[ -n "${VPHONE_WS_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VPHONE_WS_VERSION}" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VPHONE_WS_VERSION}" "$APP/Contents/Info.plist"
  echo "stamped version ${VPHONE_WS_VERSION}"
fi
echo "built $APP"
