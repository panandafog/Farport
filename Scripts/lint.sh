#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v swiftlint >/dev/null 2>&1; then
    echo "error: SwiftLint is required. Install with: brew install swiftlint" >&2
    exit 1
fi
exec swiftlint lint --strict --no-cache --config .swiftlint.yml "$@"
