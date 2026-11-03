#!/bin/bash
# Build a signed, notarized Cherry.dmg (universal: Apple silicon + Intel).
#
#   packaging/release.sh 1.1.0
#
# Needs (from the environment, never committed):
#   SIGN_ID          "Developer ID Application: NAME (TEAMID)"
#   NOTARY_KEY       path to an App Store Connect API key (.p8)
#   NOTARY_KEY_ID    its Key ID
#   NOTARY_ISSUER    its Issuer ID
# Without SIGN_ID it builds an ad-hoc signed DMG and skips notarization.
# Output: dist/Cherry-<version>.dmg and dist/Cherry-<version>.dmg.sha256
set -euo pipefail
VERSION="${1:?usage: packaging/release.sh <version>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$HERE/dist"; WORK="$DIST/work"; APP="$WORK/Cherry.app"
rm -rf "$WORK"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

echo "› compiling (arm64 + x86_64)"
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos14.0" -o "$WORK/Cherry-$arch" "$HERE"/Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/Cherry" "$WORK/Cherry-arm64" "$WORK/Cherry-x86_64"

cp "$HERE/packaging/Cherry.icns" "$APP/Contents/Resources/"
cp "$HERE/Scripts/rebuild.sh" "$HERE/Scripts/make-launchers.sh" "$HERE/examples/welcome.md" "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/"*.sh

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Cherry</string>
  <key>CFBundleDisplayName</key><string>Cherry</string>
  <key>CFBundleIdentifier</key><string>com.hico.nasnotes</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Cherry</string>
  <key>CFBundleIconFile</key><string>Cherry</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>com.hico.nasnotes.url</string>
    <key>CFBundleURLSchemes</key><array><string>nasnote</string></array>
  </dict></array>
</dict></plist>
EOF

notarize() {   # $1 = file to submit
  [ -n "${SIGN_ID:-}" ] && [ -n "${NOTARY_KEY:-}" ] || { echo "› skipping notarization"; return 0; }
  xcrun notarytool submit "$1" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait --timeout 45m
}

if [ -n "${SIGN_ID:-}" ]; then
  echo "› signing app with $SIGN_ID"
  codesign --force --timestamp --options runtime -s "$SIGN_ID" "$APP"
else
  codesign --force -s - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

if [ -n "${SIGN_ID:-}" ] && [ -n "${NOTARY_KEY:-}" ]; then
  echo "› notarizing app"
  ditto -c -k --keepParent "$APP" "$WORK/Cherry.zip"
  notarize "$WORK/Cherry.zip"
  xcrun stapler staple "$APP"
fi

echo "› building dmg"
DMG="$DIST/Cherry-$VERSION.dmg"; STAGE="$WORK/dmg"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Cherry" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --timestamp -s "$SIGN_ID" "$DMG"
  if [ -n "${NOTARY_KEY:-}" ]; then
    echo "› notarizing dmg"; notarize "$DMG"; xcrun stapler staple "$DMG"
  fi
fi
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "✓ $DMG"; cat "$DMG.sha256"
