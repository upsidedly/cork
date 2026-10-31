#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ ${1:-} != --no-build ]]; then CORK_UNIVERSAL=1 ./scripts/build.sh; fi
CORK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Cork.app/Contents/Info.plist)"
CORK_OUTPUT="$PWD/build/Cork-$CORK_VERSION-universal.dmg"
CORK_STAGE="$PWD/build/release-staging"
if [[ -e "$CORK_OUTPUT" ]]; then print -u2 "Release image already exists: $CORK_OUTPUT"; exit 1; fi
for CORK_BINARY in build/Cork.app/Contents/MacOS/Cork build/Cork.app/Contents/MacOS/cork-mcp 'build/Cork.app/Contents/Helpers/Cork Importer.app/Contents/MacOS/cork-importer'; do
    lipo "$CORK_BINARY" -verify_arch arm64 x86_64
done
codesign --verify --deep --strict build/Cork.app
mkdir -p "$CORK_STAGE"
trap 'rm -rf "$CORK_STAGE"' EXIT
ditto build/Cork.app "$CORK_STAGE/Cork.app"
ln -s /Applications "$CORK_STAGE/Applications"
cp LICENSE "$CORK_STAGE/LICENSE.txt"
cp docs/INSTALL.txt "$CORK_STAGE/Read Me.txt"
hdiutil create -volname "Cork $CORK_VERSION" -srcfolder "$CORK_STAGE" -ov -format UDZO "$CORK_OUTPUT"
hdiutil verify "$CORK_OUTPUT"
(cd build && shasum -a 256 "${CORK_OUTPUT:t}" > "${CORK_OUTPUT:t}.sha256")
print "Packaged $CORK_OUTPUT"
