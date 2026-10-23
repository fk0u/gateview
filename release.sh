#!/bin/zsh
# Packages the Universal (Intel + Apple Silicon) GateView.app as .dmg and .zip into ./dist
set -euo pipefail
cd "${0:A:h}"

./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" GateView/Info.plist)
NAME="GateView-$VERSION-universal"
rm -rf dist && mkdir -p dist/stage

# zip (ditto keeps signature + extended attributes)
ditto -c -k --keepParent build/GateView.app "dist/$NAME.zip"

# dmg with drag-to-Applications
ditto build/GateView.app dist/stage/GateView.app
ln -s /Applications dist/stage/Applications
hdiutil create -volname GateView -srcfolder dist/stage -ov -format UDZO "dist/$NAME.dmg" >/dev/null
rm -rf dist/stage

(cd dist && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt)
ls -lh dist
