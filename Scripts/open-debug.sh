#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/Build/Build/Products/Debug/Harbor.app"
if [ ! -x "$APP/Contents/MacOS/Harbor" ]; then
    printf '%s\n' 'Build the Harbor or Harbor Attach scheme in Debug first.' >&2
    exit 1
fi

# Use Launch Services, not a direct binary launch with Terminal's networking privileges.
if [ "$#" -eq 0 ]; then
    /usr/bin/open "$APP"
else
    /usr/bin/open "$APP" --args "$@"
fi
