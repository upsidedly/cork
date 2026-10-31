#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CORK_SDK="${CORK_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
mkdir -p build
swiftc -sdk "$CORK_SDK" -swift-version 6 -parse-as-library Sources/Cork/SystemWallpaperSync.swift Tests/WallpaperSyncChecks.swift -o build/check-wallpaper-sync
build/check-wallpaper-sync
