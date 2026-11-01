"""Generate machine-local FramePilot configs. Inspect only; never launch or capture UI."""
import copy
import json
import pathlib
import plistlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "Build" / "FramePilot"
MOBILE_SCENES = ["hosts", "terminal", "logs", "host-settings"]
MAC_SCENES = MOBILE_SCENES + ["files"]


def include_current_iphone(configuration):
    """FramePilot's model-name recommendation can lag behind installed Xcode devices."""
    if any(device["family"] == "iPhone" for device in configuration["devices"]):
        return
    types = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"], timeout=30))
    # These are the primary portrait sizes accepted by the current sibling FramePilot exporter.
    accepted = {(1260, 2736), (1290, 2796), (1320, 2868), (1284, 2778), (1242, 2688)}
    eligible = set()
    for device in types["devicetypes"]:
        if device.get("productFamily") != "iPhone":
            continue
        path = pathlib.Path(device["bundlePath"]) / "Contents/Resources/capabilities.plist"
        try:
            screen = plistlib.loads(path.read_bytes())["capabilities"]["ScreenDimensionsCapability"]
        except (OSError, KeyError, plistlib.InvalidFileException):
            continue
        if (screen.get("main-screen-width"), screen.get("main-screen-height")) in accepted:
            eligible.add(device["identifier"])
    listing = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], timeout=30))
    runtimes = sorted(listing["devices"], key=lambda value: tuple(map(int, re.findall(r"\d+", value))), reverse=True)
    for runtime in runtimes:
        for device in listing["devices"][runtime]:
            if device.get("deviceTypeIdentifier") in eligible and not device["name"].startswith("FramePilot "):
                configuration["devices"].insert(0, dict(id=device["udid"], name=device["name"], family="iPhone",
                    runtime=runtime, deviceType=device["deviceTypeIdentifier"]))
                return
    raise SystemExit("No iPhone simulator with a supported App Store screenshot size. "
                     "Install an iPhone Pro Max simulator in Xcode, then run prepare again.")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 Scripts/prepare-framepilot.py /path/to/framepilot")
    result = subprocess.run(
        [sys.argv[1], "inspect", str(ROOT / "Farport.xcodeproj"), "Farport iOS Demo"],
        check=False, capture_output=True, text=True,
    )
    if result.returncode:
        raise SystemExit(result.stderr.strip() or "FramePilot could not inspect the project.")
    mobile = json.loads(result.stdout)
    include_current_iphone(mobile)
    if not mobile["devices"]:
        raise SystemExit("FramePilot found no recommended iPhone/iPad simulators. "
                         "Install an iPhone Pro Max or 13-inch iPad Pro simulator in Xcode and run prepare again.")
    mobile.update(mode="scenes", scenes=MOBILE_SCENES, languages=["en-US", "ru-RU"],
                  sceneArgumentPrefix="--screenshot-scene=", settlingSeconds=3,
                  outputPath=str(DESTINATION / "Runs"), onlyTesting="")
    desktop = copy.deepcopy(mobile)
    desktop.update(scheme="Farport Screenshots", mode="uiTests", scenes=MAC_SCENES,
                   devices=[dict(id="local-mac", name="Mac", family="macOS", runtime="macOS", deviceType="mac")])
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for platform, base in [("ios", mobile), ("macos", desktop)]:
        for appearance in ["light", "dark"]:
            configuration = copy.deepcopy(base)
            configuration["appearance"] = appearance
            if platform == "macos":
                suffixes = ["Hosts", "Terminal", "Logs", "HostSettings", "Files"]
                configuration["onlyTesting"] = "\n".join(
                    f"FarportScreenshots/StoreScreenshots/test{appearance.title()}{index:02d}{suffix}"
                    for index, suffix in enumerate(suffixes, 1)
                )
            path = DESTINATION / f"{platform}-{appearance}.json"
            path.write_text(json.dumps(configuration, ensure_ascii=False, indent=2) + "\n")
            print(path)
    print("Prepared configs only. No simulators were booted and no screenshots/tests were run.")


if __name__ == "__main__":
    main()
