#!/bin/sh
set -eu

# SwiftTerm ships Metal shaders even when its optional GPU renderer is disabled.
# Recent Xcode versions distribute their compiler as a separate Apple component.
if ! xcrun metal --version >/dev/null 2>&1; then
    xcodebuild -downloadComponent MetalToolchain
fi
xcrun metal --version
