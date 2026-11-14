"""Resumable release stages. No command submits to App Review."""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import urllib.error
import urllib.request

from . import signing
from .asc import ApiError, Client, Store, EDITABLE, payload, relationship, sanitized, screenshots, state
from .metadata import NeedsAction, ReleaseError, Waiting, ROOT, asc_locale, identity, metadata, screenshot_files
from .diagnostics import annotation
from .reporting import render, emit

STAGES = ("init", "probe", "build", "upload", "wait", "uploaded", "compliance", "metadata", "review", "draft", "status", "summary", "cleanup")


def save(path, report):
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")


def output(key, value):
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as file:
            file.write(f"{key}={value}\n")


def public_urls(localizations):
    for url in sorted({v for attrs in localizations.values() for k, v in attrs.items() if k.endswith("Url")}):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "Farport-Release-Preflight"})
            with urllib.request.urlopen(request, timeout=30) as response:
                if response.status != 200 or not response.read(1):
                    raise NeedsAction("Support/privacy/marketing URL is not publicly readable. Publish the repository pages before releasing.")
        except (OSError, TimeoutError):
            raise NeedsAction("Support/privacy/marketing URL is not publicly readable. Publish the repository pages before releasing.") from None


def verify_remote(store, version, build, localizations):
    """Read back required information; readiness is confirmed from Apple, not local flags."""
    store.verify_encryption(build)
    selected = store.api.get(f"/v1/appStoreVersions/{version['id']}/build")
    if not selected or selected["id"] != build["id"] or selected["attributes"].get("processingState") != "VALID":
        raise NeedsAction("Requested processed build is not selected on this version.", code="EXACT_BUILD_NOT_SELECTED",
                          next_action="If the version is Ready for Review with an older build, remove it from the unsubmitted draft in App Store Connect. "
                                      "Then run Prepare App Store Review → prepare with this exact build number.")
    try:
        review = store.api.get(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")
    except ApiError as error:
        if error.status == 404:
            raise NeedsAction("App Review Information is absent. Run review with the configured contact phone.") from None
        raise
    attrs = review["attributes"]
    if not all(attrs.get(k) for k in ("contactFirstName", "contactLastName", "contactEmail", "contactPhone", "notes")):
        raise NeedsAction("App Review contact/notes are incomplete. Rerun review with the configured contact secret.")
    if attrs.get("demoAccountRequired") and not all(attrs.get(k) for k in ("demoAccountName", "demoAccountPassword")):
        raise NeedsAction("App Review requires missing demo credentials.")
    locales = store.api.list(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations", {"limit": 200})
    by_locale = {l["attributes"]["locale"]: l for l in locales}
    for locale, expected in localizations.items():
        current = by_locale.get(asc_locale(locale))
        if not current or any(current["attributes"].get(k) != value for k, value in expected.items()
                              if k not in {"name", "subtitle", "privacyPolicyUrl"}):
            raise NeedsAction("App Store localized version metadata differs from the repository. Rerun metadata while the version is editable.")
        sets = store.api.list(f"/v1/appStoreVersionLocalizations/{current['id']}/appScreenshotSets", {"limit": 200})
        for group in store.config["screenshotGroups"]:
            if group["platform"] != store.identity["platform"] or not group["displayType"]:
                continue
            matches = [s for s in sets if s["attributes"]["screenshotDisplayType"] == group["displayType"]]
            if len(matches) != 1:
                raise NeedsAction("Required screenshot set is missing or ambiguous. Rerun metadata.")
            assets = store.api.list(f"/v1/appScreenshotSets/{matches[0]['id']}/appScreenshots", {"limit": 200})
            expected_checksums = [hashlib.md5(f.read_bytes()).hexdigest() for f in screenshot_files(group, locale)]
            if [a["attributes"].get("sourceFileChecksum", "").lower() for a in assets] != expected_checksums or any(
                    a["attributes"].get("assetDeliveryState", {}).get("state") != "COMPLETE" for a in assets):
                raise NeedsAction("Screenshots differ, are out of order, or are not fully processed. Rerun metadata.")
    # App Information may be shared by platforms; never mutate it here.
    info, _ = store.editable_info()
    store.verify_info(info, localizations)


def status(store, localizations):
    all_versions = store.versions()
    versions = [v for v in all_versions if v["attributes"]["versionString"] == store.identity["version"]]
    build = store.find_build()
    if build is None or build["attributes"]["processingState"] != "VALID":
        raise Waiting("Build is not yet processed/visible in Apple. Rerun status, or the same release stage after processing.")
    if len(versions) != 1:
        existing = ", ".join(store.report["availableVersions"]) or "none"
        raise NeedsAction(f"Build {store.identity['version']} ({store.identity['build']}) is VALID; requested App Store version "
                          f"{store.identity['version']} is not present uniquely. Existing versions: {existing}. "
                          "status is read-only; run full to prepare the version and metadata.")
    # The collection can lag behind the resource after adding a review item.
    # Re-read the exact version before judging its current state.
    version = store.api.get(f"/v1/appStoreVersions/{versions[0]['id']}")
    if (version["attributes"].get("platform") != store.identity["platform"] or
            version["attributes"].get("versionString") != store.identity["version"]):
        raise NeedsAction("Target version identity changed during status verification. Inspect ASC before retrying.")
    store.report["versionState"] = state(version)
    if state(version) != "READY_FOR_REVIEW":
        raise NeedsAction(f"Version is {state(version)}, not READY_FOR_REVIEW. Run the missing preparation stages; inspect App Privacy, age rating, agreements and availability in ASC.")
    verify_remote(store, version, build, localizations)
    drafts = [s for s in store.submissions() if state(s) == "READY_FOR_REVIEW"]
    matching = []
    for draft in drafts:
        items = store.api.list(f"/v1/reviewSubmissions/{draft['id']}/items", {"include": "appStoreVersion", "limit": 200})
        if any(relationship(i, "appStoreVersion") == version["id"] and state(i) == "READY_FOR_REVIEW" for i in items):
            matching.append(draft)
    if len(matching) != 1:
        raise NeedsAction("Apple has not confirmed one ready draft containing this exact version.")
    store.report.update(draftState="READY_FOR_REVIEW", draftId=matching[0]["id"], selectedBuild=build["id"],
                        verification="READY_FOR_REVIEW (confirmed by Apple; not submitted)")


def uploaded(store):
    """Upload success is independent of the owner's later encryption declaration."""
    build = store.find_build()
    if not build or build["attributes"].get("processingState") != "VALID":
        raise Waiting("This exact build is not yet VALID in Apple. Retry Upload App Store Build with the SAME build number.")
    try:
        store.verify_encryption(build)
    except NeedsAction as error:
        if error.code not in {"EXPORT_COMPLIANCE_REQUIRED", "ENCRYPTION_DECLARATION_REQUIRED"}:
            raise
        store.report["encryption"] = "ACTION_REQUIRED"
        store.report["nextAction"] = error.next_action
        annotation(str(error) + " " + error.next_action, error.code, warning=True)
    store.report.update(uploadComplete=True, verification="UPLOADED (VALID; review not prepared)")


def summary(report, path):
    content = render(report)
    (path / "summary.md").write_text(content)
    emit(content)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=STAGES)
    parser.add_argument("--platform", choices=("ios", "macos"), required=True)
    parser.add_argument("--build-number", default="")
    args = parser.parse_args(argv)
    ident = identity(args.platform, args.build_number)
    path = ROOT / "Build/Release" / args.platform
    path.mkdir(parents=True, exist_ok=True)
    report_path = path / "report.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else {"identity": ident, "actions": []}
    if report["identity"] != ident:
        raise ReleaseError("Local release state belongs to another identity. Use a clean CI run.")
    if args.stage == "summary":
        if os.environ.get("RELEASE_JOB_STATUS") in {"failure", "cancelled"} and report.get("outcome") == "SUCCEEDED":
            report["outcome"] = "ERROR"
            report["error"] = "A workflow bootstrap, artifact or cleanup step failed outside the API stages. Check the failed GitHub Actions step."
            save(report_path, report)
        summary(report, path)
        return 0
    if args.stage == "cleanup":
        signing.cleanup(path)
        return 0
    phase = "archive" if args.stage == "build" else args.stage
    try:
        upload_pipeline = os.environ.get("RELEASE_PIPELINE") == "upload"
        if upload_pipeline and args.stage not in {"init", "probe", "build", "upload", "wait", "uploaded"}:
            raise ReleaseError("Upload pipeline cannot modify metadata, select a review build or prepare a draft.")
        if upload_pipeline:
            config = json.loads((ROOT / "AppStore/release.json").read_text())
            localizations, review, copyright = {}, {}, ""
        else:
            config, localizations, review, copyright = metadata(args.platform)
        if args.stage == "init":
            signing.preflight([args.platform], os.environ.get("RELEASE_MODE", "status"), os.environ.get("ARTIFACT_RUN_ID", ""))
            report["warnings"] = [] if upload_pipeline else ["Existing November 1–2 screenshots are reused; no UI tests/captures were run. Host-default/tab-mode controls have since changed; owner should review screenshot freshness."]
            if args.platform == "ios" and not upload_pipeline:
                report["warnings"].append("Duo PNGs validated but excluded: official OpenAPI 4.6 has no Duo screenshot display types.")
            for group in ([] if upload_pipeline else config["screenshotGroups"]):
                if group["platform"] == ident["platform"]:
                    for locale in localizations:
                        screenshot_files(group, locale)
            key = signing.decode_secret("ASC_PRIVATE_KEY_P8_BASE64", pathlib.Path(os.environ.get("RUNNER_TEMP", path)) / f"farport-{args.platform}-AuthKey.p8")
            if not key.read_text().startswith("-----BEGIN PRIVATE KEY-----"):
                raise NeedsAction("ASC_PRIVATE_KEY_P8_BASE64 must contain the base64-encoded original Apple .p8 file.")
            signing.require("ASC_KEY_ID"); signing.require("ASC_ISSUER_ID")
            if os.environ.get("GITHUB_ENV"):
                with open(os.environ["GITHUB_ENV"], "a") as file:
                    file.write(f"ASC_KEY_PATH={key}\n")
            os.environ["ASC_KEY_PATH"] = str(key)
        elif args.stage == "build":
            report["archive"] = "RUNNING"
            save(report_path, report)
            signing.build(ident, path)
            report["archive"] = "SUCCEEDED (signed App Store package)"
        else:
            store = Store(Client(), ident, config, report)
            if args.stage == "probe":
                version = None if upload_pipeline else store.guard(allow_ready=True)
                already_ready = bool(version and state(version) == "READY_FOR_REVIEW")
                existing = store.find_build()
                receipt = None if existing else store.find_upload()
                output("existing", "true" if existing or receipt else "false")
                output("ready", "true" if already_ready else "false")
                if existing:
                    report["upload"] = "ALREADY_PRESENT (not uploaded again)"
                if already_ready:
                    status(store, localizations)
            elif args.stage == "upload":
                if store.find_build():
                    report["upload"] = "ALREADY_PRESENT (not uploaded again)"
                elif store.find_upload():
                    pass
                else:
                    if os.environ.get("ASC_ALLOW_UPLOAD") != "1":
                        raise NeedsAction("Binary upload is disabled. Dispatch the release workflow explicitly; never upload during local tests.")
                    artifact = signing.binary(path, ident)
                    store.prepare_upload_platform()
                    env = os.environ | {"ASC_BINARY_PATH": str(artifact), "ASC_PLATFORM": ident["platform"], "ASC_BUNDLE_ID": ident["bundleId"],
                                        "FASTLANE_SKIP_UPDATE_CHECK": "1", "FASTLANE_HIDE_CHANGELOG": "1", "FASTLANE_OPT_OUT_USAGE": "1",
                                        "FASTLANE_DISABLE_COLORS": "1", "CI": "true"}
                    signing.run(["bundle", "exec", "fastlane", "upload_binary"], env=env, timeout=1800)
                    report["upload"] = "SUCCEEDED (transport only; processing checked separately)"
            elif args.stage == "wait":
                store.wait_build()
            elif args.stage == "uploaded":
                uploaded(store)
            elif args.stage == "compliance":
                store.verify_encryption(store.wait_build())
            elif args.stage == "metadata":
                public_urls(localizations)
                version = store.ensure_version()
                locales = store.metadata(version, localizations, copyright)
                phase = "screenshots"
                report["screenshots"] = "RUNNING"
                save(report_path, report)
                for group in config["screenshotGroups"]:
                    if group["platform"] == ident["platform"] and group["displayType"]:
                        for locale, resource in locales.items():
                            screenshots(store, resource, group, screenshot_files(group, locale))
                report["screenshots"] = "SUCCEEDED (documented API slots; Duo excluded)" if args.platform == "ios" else "SUCCEEDED"
            elif args.stage == "review":
                version = store.ensure_version()
                build = store.wait_build()
                store.verify_encryption(build)
                store.bind(version, build)
                store.configure_review(version, review)
            elif args.stage == "draft":
                version = store.guard(allow_ready=True)
                if not version:
                    raise NeedsAction("Prepare the target version first.")
                build = store.wait_build()
                verify_remote(store, version, build, localizations)
                store.draft(version, build)
            elif args.stage == "status":
                status(store, localizations)
        report["outcome"] = "SUCCEEDED"
        report.pop("error", None)
        report.pop("errorCode", None)
        report.pop("failedStage", None)
        if args.stage != "uploaded":
            report.pop("nextAction", None)
        report["actions"] = []
        save(report_path, report)
        print(f"{args.stage}: SUCCEEDED ({ident['platform']} {ident['version']} build {ident['build']})")
        return 0
    except (ReleaseError, OSError, ValueError, KeyError) as error:
        action_required = isinstance(error, NeedsAction) or isinstance(error, ApiError) and error.status in {401, 403, 409, 422}
        report["outcome"] = "WAITING_FOR_APPLE" if isinstance(error, Waiting) else "USER_ACTION_REQUIRED" if action_required else "ERROR"
        report["error"] = sanitized(str(error))
        report["failedStage"] = phase
        report["errorCode"] = getattr(error, "code", "APPLE_PROCESSING_PENDING" if isinstance(error, Waiting) else
                                       "APPLE_API_" + str(error.status) if isinstance(error, ApiError) else report["outcome"])
        if getattr(error, "next_action", ""):
            report["nextAction"] = error.next_action
        report[phase] = report["outcome"]
        if action_required and report["error"] not in report["actions"]:
            report["actions"].append(report["error"])
        save(report_path, report)
        print(report["outcome"] + ": " + report["error"], file=sys.stderr)
        annotation(report["error"] + " " + report.get("nextAction", ""), phase + ": " + report["errorCode"])
        return 3 if isinstance(error, Waiting) else 2 if action_required else 1


if __name__ == "__main__":
    sys.exit(main())
