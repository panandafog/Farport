"""Always-visible release outcomes; deliberately uses only Python's standard library."""
import argparse
import html
import json
import os
import pathlib

from .diagnostics import annotation, sanitized

ROOT = pathlib.Path(__file__).resolve().parents[2]
LABELS = {
    "install_api": "Install Apple API dependencies", "configure_xcode": "Configure Xcode",
    "init": "Initialize release", "probe": "Check exact build and App Store state",
    "prepare_tools": "Prepare signing/build tools", "archive": "Archive and sign",
    "save_package": "Preserve signed package", "source": "Verify artifact provenance",
    "restore": "Restore signed package", "upload": "Upload to Apple", "wait": "Wait for Apple processing",
    "compliance": "Check Export Compliance", "uploaded": "Verify uploaded build",
    "metadata": "Update metadata and screenshots", "review": "Select build and configure review",
    "draft": "Prepare review draft", "status": "Verify Apple state", "cleanup": "Remove temporary credentials",
    "audit": "Validate release inputs", "checkout": "Checkout source", "python": "Set up Python",
}


def save(report, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")


def next_action(report):
    if report.get("nextAction"):
        return report["nextAction"]
    ident = report["identity"]
    build = ident.get("build", "the same number")
    if report.get("verification", "").startswith("READY_FOR_REVIEW") and report.get("outcome") == "SUCCEEDED":
        return "Check the draft in App Store Connect, then manually choose Submit for Review. Nothing was submitted or published."
    if report.get("uploadComplete") and report.get("outcome") == "SUCCEEDED":
        return f"Run Prepare App Store Review with build_number {build} and the same platform(s). No rebuild is needed."
    if ident.get("platform") == "PREFLIGHT" and report.get("outcome") == "SUCCEEDED":
        return "Release inputs validated. See the platform results below."
    return f"Resolve the reason above, then retry the affected workflow with the SAME build_number ({build}). Do not choose a new build for a retry."


def render(report):
    ident = report["identity"]
    outcome = report.get("outcome", "ERROR")
    verified = outcome == "SUCCEEDED" and report.get("verification", "").startswith("READY_FOR_REVIEW")
    uploaded = outcome == "SUCCEEDED" and report.get("uploadComplete")
    title = ("✅ Ready for review" if verified else "✅ Build uploaded to Apple" if uploaded else
             "✅ Preflight passed" if outcome == "SUCCEEDED" else
             "⏳ Waiting for Apple" if outcome == "WAITING_FOR_APPLE" else
             "⚠️ Action required" if outcome == "USER_ACTION_REQUIRED" else "❌ Release step failed")
    lines = [f"## {title} — {ident.get('platform', 'Unknown')}", "",
             f"**Version {ident.get('version', '—')} · Build {ident.get('build', '—')}**", ""]
    details = ""
    if report.get("error"):
        stage = LABELS.get(report.get("failedStage"), report.get("failedStage", "startup"))
        error = sanitized(report["error"])
        reason = error.splitlines()[0][:500]
        if reason != error:
            details = "\n<details><summary>Technical details</summary>\n\n<pre>" + html.escape(error) + "</pre>\n</details>\n"
        lines += [f"**Stopped at:** {stage} · `{report.get('errorCode', outcome)}`", "",
                  "**Reason:** " + reason, ""]
    elif report.get("encryption") == "ACTION_REQUIRED":
        lines += ["**⚠️ Export Compliance needs the owner's answer. Upload completed successfully.**", ""]
    lines += ["**Next step:** " + next_action(report), "", "| Step | Result |", "| --- | --- |"]
    for key in ("archive", "upload", "processing", "encryption", "metadata", "screenshots", "review", "draft",
                "versionState", "draftState", "verification", "outcome"):
        value = report.get(key, "—")
        lines.append(f"| {LABELS.get(key, key)} | {str(value).replace('|', '/').replace(chr(10), ' ')} |")
    app = "https://appstoreconnect.apple.com/apps/" + report.get("appId", "6826320378")
    repository = "https://github.com/" + os.environ.get("GITHUB_REPOSITORY", "panandafog/Farport")
    lines += ["", f"[TestFlight / Compliance]({app}/testflight) · [App Review]({app}/appreview)",
              f"[Upload workflow]({repository}/actions/workflows/app-store-release.yml) · "
              f"[Prepare review workflow]({repository}/actions/workflows/app-store-review.yml)"]
    for warning in report.get("warnings", []):
        lines += ["", "Note: " + str(warning).replace("\n", " ")]
    return sanitized("\n".join(lines) + "\n") + details


def emit(content):
    print(content)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as file:
            file.write(content)


def platform_report(platform, build, job_status, steps):
    path = ROOT / "Build/Release" / platform / "report.json"
    report = json.loads(path.read_text()) if path.exists() else {
        "identity": dict(name="Farport", platform={"ios": "IOS", "macos": "MAC_OS", "audit": "PREFLIGHT"}[platform],
                         version="—", build=build or "not selected"),
        "outcome": "ERROR", "error": "The job stopped before release initialization completed.",
        "errorCode": "STARTUP_FAILED",
    }
    failed = next((key for key, value in steps.items() if value.get("outcome") in {"failure", "cancelled"}), None)
    if failed or job_status in {"failure", "cancelled"}:
        report.setdefault("failedStage", failed or "startup")
        if report.get("outcome") == "SUCCEEDED":
            report.update(outcome="ERROR", errorCode="WORKFLOW_STEP_FAILED",
                          error=f"{LABELS.get(failed, failed or 'Job cleanup')} failed outside the Apple API stages.")
            report.pop("nextAction", None)
    save(report, path)
    content = render(report)
    (path.parent / "summary.md").write_text(content)
    emit(content)
    if report.get("outcome") != "SUCCEEDED":
        annotation(report.get("error", "Release job did not finish") + " Next: " + next_action(report),
                   report.get("errorCode", "Release job failed"))
    return report


def aggregate(directory, selected, audit_status, platform_status):
    reports = [json.loads(path.read_text()) for path in pathlib.Path(directory).rglob("report.json")]
    requested = ["IOS", "MAC_OS"] if selected == "both" else ["IOS" if selected == "ios" else "MAC_OS"]
    lines = ["# Farport release result", "", "| Platform | Version | Build | Result |", "| --- | --- | --- | --- |"]
    failed = audit_status != "success" or platform_status != "success"
    ordered = []
    for platform in requested:
        matches = [r for r in reports if r.get("identity", {}).get("platform") == platform]
        if len(matches) != 1:
            failed = True
            reason = "Preflight failed; no platform work was started." if audit_status != "success" else \
                     "Platform report is missing or ambiguous. Check checkout, dependency setup and report artifact delivery."
            report = {"identity": dict(platform=platform, version="—", build="—"), "outcome": "ERROR",
                      "errorCode": "REPORT_UNAVAILABLE", "error": reason}
        else:
            report = matches[0]
        failed |= report.get("outcome") != "SUCCEEDED"
        ordered.append(report)
        ident = report["identity"]
        result = "READY_FOR_REVIEW" if report.get("verification", "").startswith("READY_FOR_REVIEW") else \
                 "UPLOADED · owner action required" if report.get("uploadComplete") and report.get("encryption") == "ACTION_REQUIRED" else \
                 "UPLOADED" if report.get("uploadComplete") else report.get("outcome", "ERROR")
        if report.get("outcome") != "SUCCEEDED":
            result = report.get("outcome", "ERROR")
        lines.append(f"| {platform} | {ident.get('version', '—')} | {ident.get('build', '—')} | {result} |")
    if failed:
        lines += ["", "**Preparation did not finish. See the reason and next action below.**"]
        if all(r.get("outcome") == "SUCCEEDED" for r in ordered):
            lines += ["A workflow/artifact/post-job step failed after the recorded stages. Check the failed job on this page."]
    audits = [r for r in reports if r.get("identity", {}).get("platform") == "PREFLIGHT"]
    content = "\n".join(lines) + "\n\n" + "\n".join(render(r) for r in [*audits, *ordered])
    emit(sanitized(content))
    if failed:
        annotation("See Farport release result on the Summary page for the reason and exact next action.", "Release preparation incomplete")
    return int(failed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("platform", "aggregate"))
    parser.add_argument("--platform", choices=("ios", "macos", "audit"))
    parser.add_argument("--build-number", default="")
    parser.add_argument("--reports", default="Build/ReleaseReports")
    args = parser.parse_args()
    if args.kind == "aggregate":
        return aggregate(args.reports, os.environ["REQUESTED_PLATFORM"], os.environ["AUDIT_STATUS"], os.environ["PLATFORM_STATUS"])
    platform_report(args.platform, args.build_number, os.environ.get("RELEASE_JOB_STATUS", "failure"),
                    json.loads(os.environ.get("RELEASE_STEPS_JSON", "{}")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
