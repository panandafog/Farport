#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
sh Scripts/xcodegen.sh --version
temporary=$(mktemp -d "$ROOT/Build/GenerationCheck.XXXXXX")
trap 'rm -rf "$temporary"' EXIT

# Snapshot only version-controlled inputs and new non-ignored files, never user data/build caches.
git ls-files --cached --others --exclude-standard -z |
    ruby -e 'paths = STDIN.read.split("\0").uniq; paths.each { |p| STDOUT.write(p + "\0") if File.file?(p) || File.symlink?(p) }' |
    tar -c -f "$temporary/source.tar" --null -T -
for name in Farport Harbor 'checkout with spaces'; do
    checkout="$temporary/$name"
    mkdir -p "$checkout/Build/Tools/XcodeGen"
    tar -x -f "$temporary/source.tar" -C "$checkout"
    ln -s "$ROOT/Build/Tools/XcodeGen/2.44.1" "$checkout/Build/Tools/XcodeGen/2.44.1"
    (cd "$checkout" && sh Scripts/xcodegen.sh generate)
    for path in \
        Farport.xcodeproj/project.pbxproj \
        Farport.xcodeproj/project.xcworkspace/contents.xcworkspacedata \
        Farport.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings \
        Farport.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved \
        Farport.xcodeproj/xcshareddata/xcschemes/Farport.xcscheme \
        Farport.xcodeproj/xcshareddata/xcschemes/FarportLocal.xcscheme \
        'Farport.xcodeproj/xcshareddata/xcschemes/Farport Attach.xcscheme' \
        App/Info.plist FinderExtension/Info.plist AppTests/Info.plist Package.resolved; do
        diff -u "$ROOT/$path" "$checkout/$path"
    done
    printf 'Generated files match for checkout: %s\n' "$name"
done
