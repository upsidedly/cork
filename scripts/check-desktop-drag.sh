#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CORK_SDK="${CORK_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
CORK_ARCH="$(uname -m)"
CORK_RELEASE="build/spm/$CORK_ARCH-apple-macosx/release"
# Reuse the native release's existing CorkCore objects; no second build cache.
swiftc -sdk "$CORK_SDK" -swift-version 6 -parse-as-library -I "$CORK_RELEASE/Modules" \
    Sources/Cork/PrintRenderer.swift Tests/DesktopDragChecks.swift \
    "$CORK_RELEASE"/CorkCore.build/*.swift.o -o build/check-desktop-drag
build/check-desktop-drag
