#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CORK_SDK="${CORK_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
swift run --scratch-path build/spm -Xswiftc -sdk -Xswiftc "$CORK_SDK" -Xcc -isysroot -Xcc "$CORK_SDK" CorkChecks
