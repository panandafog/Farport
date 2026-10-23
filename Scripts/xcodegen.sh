#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
VERSION=2.44.1
# Official xcodegen.zip release digest; pin the binary and its bundled presets together.
SHA256=a2e905fb68446e9bb4008cdfe2e13e3f176d0cbcca828b71770f8e53fca91b73
TOOLS="$ROOT/Build/Tools/XcodeGen"
INSTALL="$TOOLS/$VERSION"
BINARY="$INSTALL/bin/xcodegen"

if [ ! -x "$BINARY" ]; then
    mkdir -p "$TOOLS"
    (
        temporary=$(mktemp -d "$TOOLS/.download.XXXXXX")
        trap 'rm -rf "$temporary"' EXIT
        archive="$temporary/xcodegen.zip"
        curl --fail --location --silent --show-error --retry 3 \
            "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip" \
            --output "$archive"
        printf '%s  %s\n' "$SHA256" "$archive" | shasum -a 256 --check
        unzip -q "$archive" -d "$temporary"
        mv "$temporary/xcodegen" "$INSTALL"
    )
fi

if [ "$("$BINARY" --version)" != "Version: $VERSION" ]; then
    printf 'error: Expected XcodeGen %s in %s.\n' "$VERSION" "$INSTALL" >&2
    exit 1
fi

cd "$ROOT"
exec "$BINARY" "$@"
