"""Early, read-only Apple inventory and release input validation for all platforms."""
import json
import os
import pathlib
import re
import sys
import tempfile

from . import signing
from .asc import Client, Store, sanitized
from .cli import output, public_urls
from .metadata import ROOT, NeedsAction, ReleaseError, identity, metadata, screenshot_files
from .diagnostics import annotation
from .reporting import save


def choose_build(project_build, existing, requested, mode):
    if requested:
        if not re.fullmatch(r"[1-9]\d{0,8}", requested):
            raise ReleaseError("build_number must be a positive integer.")
        return requested
    if mode != "full":
        return project_build
    return str(max(int(project_build), max([0, *[int(n) for n in existing if re.fullmatch(r"[1-9]\d{0,8}", n)]]) + 1))


def main():
    selected = os.environ.get("REQUESTED_PLATFORM", "both")
    if selected not in {"both", "ios", "macos"}:
        raise ReleaseError("Unknown platform.")
    platforms = ["ios", "macos"] if selected == "both" else [selected]
    mode = os.environ.get("RELEASE_MODE", "status")
    if mode not in {"full", "upload", "metadata", "review", "status"}:
        raise ReleaseError("Unknown mode.")
    if mode in {"upload", "review", "status"} and not os.environ.get("RELEASE_BUILD_NUMBER"):
        raise NeedsAction("An exact build_number is required for artifact upload, review and status. Use the number from the successful upload Summary.",
                          code="BUILD_NUMBER_REQUIRED")
    signing.preflight(platforms, mode, os.environ.get("ARTIFACT_RUN_ID", ""))
    if mode == "full":
        failures = []
        for platform in platforms:
            try:
                signing.validate_materials(platform)
            except (ReleaseError, ValueError) as error:
                failures.append(platform + ": " + sanitized(error))
        if failures:
            raise ReleaseError("Signing audit: " + " | ".join(failures))
    existing = []
    root = pathlib.Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir()))
    with tempfile.TemporaryDirectory(prefix="farport-preflight-", dir=root) as temp:
        key = signing.decode_secret("ASC_PRIVATE_KEY_P8_BASE64", pathlib.Path(temp) / "AuthKey.p8")
        os.environ["ASC_KEY_PATH"] = str(key)
        api = Client()
        for platform in platforms:
            ident = identity(platform)
            upload_pipeline = mode in {"full", "upload"}
            if upload_pipeline:
                config = json.loads((ROOT / "AppStore/release.json").read_text())
                locales = {}
            else:
                config, locales, _, _ = metadata(platform)
            for group in ([] if upload_pipeline else config["screenshotGroups"]):
                if group["platform"] == ident["platform"]:
                    for locale in locales:
                        screenshot_files(group, locale)
            if mode in {"metadata", "review"}:
                public_urls(locales)
            report = {}
            store = Store(api, ident, config, report)
            versions = store.versions()
            if mode not in {"full", "upload", "status"}:
                store.guard(allow_ready=True)
            builds = api.list("/v1/builds", {"filter[app]": store.app["id"],
                "filter[preReleaseVersion.platform]": ident["platform"], "limit": 200})
            uploads = api.list(f"/v1/apps/{store.app['id']}/buildUploads", {"filter[platform]": ident["platform"], "limit": 200})
            existing += [b["attributes"]["version"] for b in builds]
            existing += [b["attributes"]["cfBundleVersion"] for b in uploads]
            print(json.dumps(dict(platform=platform, appId=store.app["id"], versions=report["availableVersions"],
                                  builds=[dict(build=b["attributes"]["version"], state=b["attributes"].get("processingState")) for b in builds]), ensure_ascii=False), flush=True)
    chosen = choose_build(identity(platforms[0])["build"], existing, os.environ.get("RELEASE_BUILD_NUMBER", ""), mode)
    print("Selected build " + chosen + ". Use this SAME value for every retry.", flush=True)
    output("build", chosen)
    save({"identity": dict(name="Farport", platform="PREFLIGHT", version=identity(platforms[0])["version"], build=chosen),
          "outcome": "SUCCEEDED", "verification": "INPUTS_VALIDATED"}, ROOT / "Build/Release/audit/report.json")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as file:
            file.write(f"## Farport release preflight\n\nPlatforms: {selected}; mode: {mode}; exact build: **{chosen}**. Reuse this build on retries.\n")


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, OSError, ValueError, KeyError) as error:
        message = sanitized(error)
        code = getattr(error, "code", "PREFLIGHT_FAILED")
        save({"identity": dict(name="Farport", platform="PREFLIGHT", version="—",
                               build=os.environ.get("RELEASE_BUILD_NUMBER") or "not selected"),
              "outcome": "USER_ACTION_REQUIRED" if isinstance(error, NeedsAction) else "ERROR",
              "failedStage": "audit", "errorCode": code, "error": message,
              "nextAction": getattr(error, "next_action", "")}, ROOT / "Build/Release/audit/report.json")
        annotation(message, "Preflight: " + code)
        print("Release preflight failed: " + message, file=sys.stderr)
        sys.exit(1)
