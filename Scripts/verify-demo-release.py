"""Reject sample-mode code/data in a built Release app (including embedded bundles)."""
import pathlib
import sys

MARKERS = (
    b"Farport sample environment",
    b"farport.example",
    b"DemoCatalogO",
    b"DemoConnectionProviderV",
    b"DemoTerminalSessionC",
    b"DemoSecretStoreC",
    b"DemoScreenshotSceneO",
    b"ScreenshotSupportO",
    b"ScreenshotWindowViewC",
    b"test.rebex.net",
    b"bandit.labs.overthewire.org",
    b"demo.wftpserver.com",
)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 Scripts/verify-demo-release.py /path/to/Farport.app")
    root = pathlib.Path(sys.argv[1])
    if root.suffix != ".app" or not root.is_dir():
        raise SystemExit("Expected an existing .app bundle")
    overlap = max(map(len, MARKERS)) - 1
    failures = []
    for path in root.rglob("*"):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as stream:
            previous = b""
            while chunk := stream.read(1_048_576):
                chunk = previous + chunk
                if any(marker in chunk for marker in MARKERS):
                    failures.append(str(path.relative_to(root)))
                    break
                previous = chunk[-overlap:]
    if failures:
        raise SystemExit("Debug demo content found in app:\n" + "\n".join(failures))
    print("Release demo isolation checks passed:", root)


if __name__ == "__main__":
    main()
