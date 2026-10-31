#!/bin/sh
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
build_directory=${1:-Build/iOSCompatibility}
sh Scripts/prepare-terminal-build.sh

# The reviewed, exact-pinned SwiftTermBuildInfoPlugin generates version metadata.
# CLI builds have no interactive Xcode dialog in which to enable the package plugin.

# Sessions includes Core, Cloud and Localization; the other adapters must compile independently.
for scheme in FarportSessions FarportSSH FarportSecurity; do
    xcodebuild -quiet -project Farport.xcodeproj -scheme "$scheme" \
        -configuration Debug -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$build_directory" -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation \
        CODE_SIGNING_ALLOWED=NO build
done

for configuration in Debug Release; do
    xcodebuild -quiet -project Farport.xcodeproj -scheme 'Farport iOS' \
        -configuration "$configuration" -destination 'generic/platform=iOS' \
        -derivedDataPath "$build_directory" -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation \
        CODE_SIGNING_ALLOWED=NO build
done
