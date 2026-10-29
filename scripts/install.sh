#!/bin/zsh
set -euo pipefail
CORK_ROOT="${0:A:h:h}"
if pgrep -x Cork >/dev/null; then
    print -u2 'Quit Cork before installing an update.'
    exit 1
fi
if [[ ${1:-} != --no-build ]]; then "$CORK_ROOT/scripts/build.sh"; fi
if [[ -e /Applications/Cork.app ]]; then
    CORK_BACKUP="$HOME/Library/Application Support/Cork/Backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$CORK_BACKUP"
    mv /Applications/Cork.app "$CORK_BACKUP/Cork.app"
    print "Previous app saved to $CORK_BACKUP"
fi
ditto "$CORK_ROOT/build/Cork.app" /Applications/Cork.app
codesign --verify --deep --strict /Applications/Cork.app
print 'Installed /Applications/Cork.app'
