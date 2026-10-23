#!/bin/zsh
# Builds a Universal (arm64 + x86_64) GateView.app into ./build
set -euo pipefail
cd "${0:A:h}"

swift build -c release --arch arm64 --arch x86_64
APP=build/GateView.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/apple/Products/Release/GateView "$APP/Contents/MacOS/"
cp GateView/Info.plist "$APP/Contents/"
xcrun actool GateView/Assets.xcassets --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon \
  --output-partial-info-plist build/assets-info.plist >/dev/null

# Ad-hoc signature: runs on this Mac. Use a Developer ID to distribute.
codesign --force --sign - --entitlements GateView/GateView.entitlements "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/GateView"))"
