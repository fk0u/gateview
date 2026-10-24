#!/bin/zsh
# Packages the Universal (Intel + Apple Silicon) GateView.app as .dmg, .pkg and .zip into ./dist
#
# Optional notarization: put these in ~/.config/gateview/release.env (needs an Apple Developer account):
#   APPLE_DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID="you@example.com"
#   APPLE_TEAM_ID="TEAMID"
#   APPLE_KEYCHAIN_PROFILE="gateview"   # once: xcrun notarytool store-credentials gateview --apple-id … --team-id …
# With those set, artifacts are Developer-ID signed, submitted to notarytool, stapled, then hashed.
set -euo pipefail
cd "${0:A:h}"

[[ -f ~/.config/gateview/release.env ]] && source ~/.config/gateview/release.env

./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" GateView/Info.plist)
NAME="GateView-$VERSION-universal"
rm -rf dist && mkdir -p dist/stage

# pkg: installs into /Applications (double-click installer)
# Not relocatable: always install to /Applications, even if another copy exists elsewhere.
mkdir -p dist/pkgroot && ditto build/GateView.app dist/pkgroot/GateView.app
pkgbuild --analyze --root dist/pkgroot dist/component.plist >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" dist/component.plist
PKG_SIGN=()
[[ -n "${APPLE_DEVELOPER_ID:-}" ]] && PKG_SIGN=(--sign "$APPLE_DEVELOPER_ID")
pkgbuild --root dist/pkgroot --component-plist dist/component.plist --install-location /Applications \
  --identifier com.alghani.GateView.pkg --version "$VERSION" "${PKG_SIGN[@]}" "dist/$NAME.pkg" >/dev/null
rm -rf dist/pkgroot dist/component.plist

# dmg with drag-to-Applications
ditto build/GateView.app dist/stage/GateView.app
ln -s /Applications dist/stage/Applications
hdiutil create -volname GateView -srcfolder dist/stage -ov -format UDZO "dist/$NAME.dmg" >/dev/null
rm -rf dist/stage

# zip (ditto keeps signature + extended attributes)
ditto -c -k --keepParent build/GateView.app "dist/$NAME.zip"

# Notarize + staple (dmg and pkg only; zips can't be stapled).
if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_KEYCHAIN_PROFILE:-}" ]]; then
  for f in "dist/$NAME.dmg" "dist/$NAME.pkg"; do
    xcrun notarytool submit "$f" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
      --keychain-profile "$APPLE_KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$f"
  done
else
  echo "Notarization skipped (no APPLE_ID/APPLE_TEAM_ID/APPLE_KEYCHAIN_PROFILE set)."
fi

(cd dist && shasum -a 256 *.dmg *.pkg *.zip > SHA256SUMS.txt)
ls -lh dist
