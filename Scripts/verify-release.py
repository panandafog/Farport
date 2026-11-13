"""Verify Farport Release resources; signing is checked separately on each bundle."""
import pathlib
import plistlib
import subprocess
import sys


def verify(app):
    if app.suffix != ".app" or not app.is_dir():
        raise ValueError("Expected an existing Farport.app bundle")
    mac = (app / "Contents").is_dir()
    info = plistlib.loads((app / ("Contents/Info.plist" if mac else "Info.plist")).read_bytes())
    if info["CFBundleIdentifier"] != "com.panandafog.harbor":
        raise ValueError("Unexpected app Bundle ID")
    # Missing compliance is an explicit owner gate at the Apple review stage.
    # A game-style hardcoded false is deliberately not required here.
    resources = app / "Contents/Resources" if mac else app
    manifest = plistlib.loads((resources / "PrivacyInfo.xcprivacy").read_bytes())
    expected = plistlib.loads(pathlib.Path("Resources/PrivacyInfo.xcprivacy").read_bytes())
    if manifest != expected:
        raise ValueError("Main app privacy manifest differs from the audited source")
    if mac:
        ext = app / "Contents/PlugIns/FarportFinderExtension.appex"
        privacy = plistlib.loads((ext / "Contents/Resources/PrivacyInfo.xcprivacy").read_bytes())
        if privacy != plistlib.loads(pathlib.Path("Resources/Finder/PrivacyInfo.xcprivacy").read_bytes()):
            raise ValueError("Finder extension privacy manifest differs from the audited source")
    if list(app.rglob("*.xctest")):
        raise ValueError("Test bundles must not ship")
    subprocess.run([sys.executable, "Scripts/verify-demo-release.py", str(app)], check=True)
    print(f"Release resources verified: {'macOS' if mac else 'iOS'} {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")


if __name__ == "__main__":
    try:
        verify(pathlib.Path(sys.argv[1]))
    except (OSError, KeyError, ValueError, IndexError) as error:
        raise SystemExit("Release verification failed: " + str(error))
