#!/bin/zsh
# Packages the Universal (Intel + Apple Silicon) GateView.app as .dmg, .pkg and .zip into ./dist
set -euo pipefail
cd "${0:A:h}"

./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" GateView/Info.plist)
NAME="GateView-$VERSION-universal"
rm -rf dist && mkdir -p dist/stage

# zip (ditto keeps signature + extended attributes)
ditto -c -k --keepParent build/GateView.app "dist/$NAME.zip"

# pkg: installs into /Applications (double-click installer)
# Not relocatable: always install to /Applications, even if another copy exists elsewhere.
mkdir -p dist/pkgroot && ditto build/GateView.app dist/pkgroot/GateView.app
pkgbuild --analyze --root dist/pkgroot dist/component.plist >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" dist/component.plist
pkgbuild --root dist/pkgroot --component-plist dist/component.plist --install-location /Applications \
  --identifier com.alghani.GateView.pkg --version "$VERSION" "dist/$NAME.pkg" >/dev/null
rm -rf dist/pkgroot dist/component.plist

# dmg with drag-to-Applications
ditto build/GateView.app dist/stage/GateView.app
ln -s /Applications dist/stage/Applications
hdiutil create -volname GateView -srcfolder dist/stage -ov -format UDZO "dist/$NAME.dmg" >/dev/null
rm -rf dist/stage

(cd dist && shasum -a 256 *.dmg *.pkg *.zip > SHA256SUMS.txt)
ls -lh dist
