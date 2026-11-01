#!/bin/sh
# Local tooling only: FramePilot is not an application/package dependency.
set -eu
farport_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
framepilot_root=${FRAMEPILOT_ROOT:-"$farport_root/../FramePilot"}
framepilot_cli=${FRAMEPILOT_CLI:-"$farport_root/Build/FramePilot/Tool/debug/framepilot"}
action=${1:-prepare}

case "$action" in
    prepare|capture) ;;
    *)
        echo 'Usage: sh Scripts/framepilot.sh prepare'
        echo '       sh Scripts/framepilot.sh capture ios-light|ios-dark|macos-light|macos-dark'
        echo 'Optional: FRAMEPILOT_ROOT=/path/to/FramePilot or FRAMEPILOT_CLI=/path/to/framepilot'
        exit 2 ;;
esac

if [ -z "${FRAMEPILOT_CLI:-}" ]; then
    swift build --package-path "$framepilot_root" --scratch-path "$farport_root/Build/FramePilot/Tool" \
        --product framepilot >&2
elif [ ! -x "$framepilot_cli" ]; then
    echo "FramePilot CLI is not executable: $framepilot_cli" >&2
    exit 1
fi

if [ "$action" = prepare ]; then
    python3 "$farport_root/Scripts/prepare-framepilot.py" "$framepilot_cli"
    exit
fi

case "${2:-}" in
    ios-light|ios-dark|macos-light|macos-dark) preset=$2 ;;
    *) echo 'Choose ios-light, ios-dark, macos-light or macos-dark.' >&2; exit 2 ;;
esac
configuration="$farport_root/Build/FramePilot/$preset.json"
if [ ! -f "$configuration" ]; then
    echo 'Run sh Scripts/framepilot.sh prepare first.' >&2
    exit 1
fi
exec "$framepilot_cli" capture "$configuration"
