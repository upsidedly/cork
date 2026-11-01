#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ $# != 2 ]]; then print -u2 'Pass a local video and PNG cover fixture.'; exit 1; fi
CORK_SDK="${CORK_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
CORK_RELEASE="build/spm/$(uname -m)-apple-macosx/release"
swiftc -sdk "$CORK_SDK" -swift-version 6 -parse-as-library -I "$CORK_RELEASE/Modules" \
    Sources/Cork/PrintRenderer.swift Sources/Cork/VideoPrintView.swift Sources/Cork/VideoWallpaperPreview.swift \
    Sources/Cork/DesktopEnvironment.swift Sources/Cork/DesktopWidgets.swift Sources/Cork/SystemWallpaperSync.swift \
    Tests/VideoWallpaperChecks.swift "$CORK_RELEASE"/CorkCore.build/*.swift.o -o build/check-video-wallpaper
build/check-video-wallpaper "$1" "$2"
