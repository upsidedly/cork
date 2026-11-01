#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ $# != 1 ]]; then print -u2 'Pass a local video fixture path.'; exit 1; fi
CORK_SDK="${CORK_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
CORK_RELEASE="build/spm/$(uname -m)-apple-macosx/release"
swiftc -sdk "$CORK_SDK" -swift-version 6 -parse-as-library -I "$CORK_RELEASE/Modules" \
    Sources/Cork/PrintRenderer.swift Sources/Cork/VideoPrintView.swift Tests/VideoHoverChecks.swift \
    "$CORK_RELEASE"/CorkCore.build/*.swift.o -o build/check-video-hover
build/check-video-hover "$1"
