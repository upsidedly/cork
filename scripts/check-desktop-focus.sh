#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CORK_SDK="${CORK_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
CORK_RELEASE="build/spm/$(uname -m)-apple-macosx/release"
swiftc -sdk "$CORK_SDK" -swift-version 6 -parse-as-library -I "$CORK_RELEASE/Modules" \
    Sources/Cork/DesktopEnvironment.swift Sources/Cork/DesktopWidgets.swift Sources/Cork/VideoWallpaperPreview.swift \
    Sources/Cork/SystemWallpaperSync.swift Sources/Cork/VideoPrintView.swift Sources/Cork/PrintRenderer.swift \
    Tests/DesktopFocusChecks.swift "$CORK_RELEASE"/CorkCore.build/*.swift.o -o build/check-desktop-focus
build/check-desktop-focus
