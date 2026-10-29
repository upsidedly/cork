#!/bin/zsh
set -euo pipefail
CORK_ROOT="${0:A:h:h}"
CORK_SDK="${CORK_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [[ ! -d "$CORK_SDK" ]]; then CORK_SDK="$(xcrun --show-sdk-path)"; fi
cd "$CORK_ROOT"
swift build -c release --scratch-path build/spm -Xswiftc -sdk -Xswiftc "$CORK_SDK" -Xcc -isysroot -Xcc "$CORK_SDK"
CORK_APP="$CORK_ROOT/build/Cork.app"
mkdir -p "$CORK_APP/Contents/MacOS" "$CORK_APP/Contents/Resources"
cp build/spm/release/Cork "$CORK_APP/Contents/MacOS/Cork"
cp build/spm/release/cork-mcp "$CORK_APP/Contents/MacOS/cork-mcp"
cp Resources/Info.plist "$CORK_APP/Contents/Info.plist"
swiftc -sdk "$CORK_SDK" -parse-as-library Sources/Cork/CorkIcon.swift scripts/make-icon.swift -o build/make-icon
build/make-icon "$CORK_APP/Contents/Resources" "$CORK_ROOT/docs/assets"
plutil -lint "$CORK_APP/Contents/Info.plist"
codesign --force --sign - "$CORK_APP/Contents/MacOS/cork-mcp"
codesign --force --sign - --options runtime "$CORK_APP"
print "Built $CORK_APP"
