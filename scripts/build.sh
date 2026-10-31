#!/bin/zsh
set -euo pipefail
CORK_ROOT="${0:A:h:h}"
CORK_SDK="${CORK_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [[ ! -d "$CORK_SDK" ]]; then CORK_SDK="$(xcrun --show-sdk-path)"; fi
cd "$CORK_ROOT"
for CORK_RUNNING_BINARY in "$CORK_ROOT/build/Cork.app/Contents/MacOS/Cork" "$CORK_ROOT/build/Cork Importer.app/Contents/MacOS/cork-importer" "$CORK_ROOT/build/Cork.app/Contents/Helpers/Cork Importer.app/Contents/MacOS/cork-importer"; do
    if [[ -f "$CORK_RUNNING_BINARY" ]] && lsof -t "$CORK_RUNNING_BINARY" >/dev/null 2>&1; then
        print -u2 "Quit the app using $CORK_RUNNING_BINARY before rebuilding it."; exit 1
    fi
done
CORK_ARCHS=("$(uname -m)")
if [[ ${CORK_UNIVERSAL:-0} == 1 ]]; then CORK_ARCHS=(arm64 x86_64); fi
for CORK_ARCH in "${CORK_ARCHS[@]}"; do
    for CORK_PRODUCT in Cork cork-mcp cork-importer; do
        swift build -c release --product "$CORK_PRODUCT" --arch "$CORK_ARCH" --scratch-path build/spm -Xswiftc -sdk -Xswiftc "$CORK_SDK" -Xcc -isysroot -Xcc "$CORK_SDK"
    done
done
CORK_APP="$CORK_ROOT/build/Cork.app"
CORK_IMPORTER="$CORK_ROOT/build/Cork Importer.app"
mkdir -p "$CORK_APP/Contents/MacOS" "$CORK_APP/Contents/Resources"
mkdir -p "$CORK_IMPORTER/Contents/MacOS" "$CORK_IMPORTER/Contents/Resources"
for CORK_PRODUCT in Cork cork-mcp cork-importer; do
    CORK_INPUTS=()
    for CORK_ARCH in "${CORK_ARCHS[@]}"; do CORK_INPUTS+=("build/spm/$CORK_ARCH-apple-macosx/release/$CORK_PRODUCT"); done
    if [[ $CORK_PRODUCT == cork-importer ]]; then CORK_TARGET="$CORK_IMPORTER/Contents/MacOS/$CORK_PRODUCT"; else CORK_TARGET="$CORK_APP/Contents/MacOS/$CORK_PRODUCT"; fi
    if [[ ${#CORK_INPUTS[@]} == 1 ]]; then cp "$CORK_INPUTS[1]" "$CORK_TARGET"; else lipo -create "${CORK_INPUTS[@]}" -output "$CORK_TARGET"; fi
done
cp Resources/Info.plist "$CORK_APP/Contents/Info.plist"
cp Resources/Importer-Info.plist "$CORK_IMPORTER/Contents/Info.plist"
swiftc -sdk "$CORK_SDK" -parse-as-library Sources/Cork/CorkIcon.swift scripts/make-icon.swift -o build/make-icon
build/make-icon "$CORK_APP/Contents/Resources" "$CORK_ROOT/docs/assets"
build/make-icon "$CORK_IMPORTER/Contents/Resources" "$CORK_ROOT/docs/assets" --importer
plutil -lint "$CORK_IMPORTER/Contents/Info.plist"
codesign --force --sign - --options runtime "$CORK_IMPORTER"
mkdir -p "$CORK_APP/Contents/Helpers"
if [[ -d "$CORK_APP/Contents/Helpers/Cork Importer.app" ]]; then rm -rf "$CORK_APP/Contents/Helpers/Cork Importer.app"; fi
ditto "$CORK_IMPORTER" "$CORK_APP/Contents/Helpers/Cork Importer.app"
plutil -lint "$CORK_APP/Contents/Info.plist"
codesign --force --sign - "$CORK_APP/Contents/MacOS/cork-mcp"
codesign --force --sign - --options runtime "$CORK_APP"
codesign --verify --deep --strict "$CORK_APP"
print "Built $CORK_APP"
