"""Offline coverage for the upload/review boundary and user-visible failure reports."""
import contextlib
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

import yaml

from Scripts.release import cli, plan, reporting, signing
from Scripts.release.asc import ApiError, Store
from Scripts.release.diagnostics import annotation
from Scripts.release.metadata import ROOT, NeedsAction, identity, metadata
from test_release import FakeAPI, resource


class UploadBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.api = FakeAPI()
        self.ident = identity("ios")
        self.config = metadata()[0]

    def call_stage(self, stage):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "AppStore").mkdir()
            (root / "AppStore/release.json").write_text(json.dumps(self.config))
            with patch.object(cli, "ROOT", root), patch.object(cli, "Client", return_value=self.api), \
                    patch.object(cli, "metadata", side_effect=AssertionError("Upload read review metadata")), \
                    patch.dict(os.environ, {"RELEASE_PIPELINE": "upload"}), contextlib.redirect_stdout(io.StringIO()):
                result = cli.main([stage, "--platform", "ios", "--build-number", self.ident["build"]])
            report = json.loads((root / "Build/Release/ios/report.json").read_text())
        return result, report

    def test_uploaded_build_succeeds_with_compliance_pending_and_does_not_mutate_apple(self):
        self.api.records["builds", "build"]["attributes"]["usesNonExemptEncryption"] = None
        result, report = self.call_stage("uploaded")
        self.assertEqual(result, 0)
        self.assertEqual(report["outcome"], "SUCCEEDED")
        self.assertTrue(report["uploadComplete"])
        self.assertEqual(report["encryption"], "ACTION_REQUIRED")
        self.assertIn("SAME build", report["nextAction"])
        self.assertTrue(all(method == "GET" for method, _ in self.api.calls))

    def test_probe_and_upload_platform_registration_leave_active_review_alone(self):
        self.api.add(resource("appStoreVersions", "old", {"versionString": self.ident["version"],
            "platform": "IOS", "appVersionState": "READY_FOR_REVIEW"}, {"app": ("apps", "app")}))
        self.api.add(resource("reviewSubmissions", "active", {"platform": "IOS", "state": "IN_REVIEW"},
                              {"app": ("apps", "app")}))
        result, _ = self.call_stage("probe")
        self.assertEqual(result, 0)
        store = Store(self.api, self.ident, self.config, {})
        store.prepare_upload_platform()
        self.assertTrue(all(method == "GET" for method, _ in self.api.calls))
        self.assertEqual(self.api.records["appStoreVersions", "old"]["attributes"]["appVersionState"], "READY_FOR_REVIEW")

    def test_upload_audit_does_not_read_review_assets_or_block_on_active_review(self):
        self.api.add(resource("reviewSubmissions", "active", {"platform": "IOS", "state": "IN_REVIEW"},
                              {"app": ("apps", "app")}))
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "AppStore").mkdir()
            (root / "AppStore/release.json").write_text(json.dumps(self.config))
            with patch.object(plan, "ROOT", root), patch.object(plan, "Client", return_value=self.api), \
                    patch.object(signing, "preflight"), patch.object(signing, "validate_materials"), \
                    patch.object(signing, "decode_secret", return_value=root / "not-a-real-key.p8"), \
                    patch.object(plan, "metadata", side_effect=AssertionError("Upload audit read review assets")), \
                    patch.object(plan, "public_urls", side_effect=AssertionError("Upload audit fetched metadata URLs")), \
                    patch.dict(os.environ, {"REQUESTED_PLATFORM": "ios", "RELEASE_MODE": "full",
                                           "RELEASE_BUILD_NUMBER": "13", "RUNNER_TEMP": temp}), \
                    contextlib.redirect_stdout(io.StringIO()):
                plan.main()
            report = json.loads((root / "Build/Release/audit/report.json").read_text())
        self.assertEqual(report["identity"]["build"], "13")
        self.assertEqual(report["outcome"], "SUCCEEDED")
        self.assertTrue(all(method == "GET" for method, _ in self.api.calls))

    def test_review_audit_requires_an_explicit_build_before_contacting_apple(self):
        with patch.dict(os.environ, {"RELEASE_MODE": "review", "RELEASE_BUILD_NUMBER": ""}), \
                patch.object(plan, "Client") as client:
            with self.assertRaises(NeedsAction) as caught:
                plan.main()
        self.assertEqual(caught.exception.code, "BUILD_NUMBER_REQUIRED")
        client.assert_not_called()

    def test_upload_pipeline_cannot_run_metadata_or_review_mutations(self):
        for stage in ("metadata", "review", "draft"):
            with self.subTest(stage=stage), contextlib.redirect_stderr(io.StringIO()):
                result, report = self.call_stage(stage)
                self.assertEqual(result, 1)
                self.assertEqual(report["outcome"], "ERROR")
        self.assertEqual(self.api.calls, [])

    def test_real_api_failure_during_compliance_inspection_is_not_hidden(self):
        store = Mock()
        store.find_build.return_value = {"attributes": {"processingState": "VALID"}}
        store.verify_encryption.side_effect = ApiError(403)
        with self.assertRaises(ApiError):
            cli.uploaded(store)

    def test_review_compliance_fails_before_any_apple_mutation(self):
        self.api.records["builds", "build"]["attributes"]["usesNonExemptEncryption"] = None
        with tempfile.TemporaryDirectory() as temp, patch.object(cli, "ROOT", pathlib.Path(temp)), \
                patch.object(cli, "Client", return_value=self.api), patch.dict(os.environ, {"RELEASE_PIPELINE": "review"}), \
                contextlib.redirect_stderr(io.StringIO()):
            result = cli.main(["compliance", "--platform", "ios", "--build-number", self.ident["build"]])
            report = json.loads((pathlib.Path(temp) / "Build/Release/ios/report.json").read_text())
        self.assertEqual(result, 2)
        self.assertEqual(report["errorCode"], "EXPORT_COMPLIANCE_REQUIRED")
        self.assertIn("TestFlight", report["nextAction"])
        self.assertTrue(all(method == "GET" for method, _ in self.api.calls))


class ReportingTests(unittest.TestCase):
    def setUp(self):
        # Handwritten legacy reports also run inside CI, with a real GITHUB_RUN_ID.
        environment = patch.dict(os.environ, {"GITHUB_RUN_ID": "", "GITHUB_RUN_ATTEMPT": ""})
        environment.start()
        self.addCleanup(environment.stop)

    def test_upload_success_and_pending_owner_action_are_visible_without_false_readiness(self):
        report = dict(identity=identity("ios"), outcome="SUCCEEDED", uploadComplete=True,
                      encryption="ACTION_REQUIRED", verification="UPLOADED (VALID; review not prepared)")
        text = reporting.render(report)
        self.assertIn("Build uploaded to Apple", text)
        self.assertIn("owner's answer", text)
        self.assertIn("Prepare App Store Review", text)
        self.assertNotIn("Ready for review", text)

    def test_dependency_failure_produces_summary_without_initialization(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(reporting, "ROOT", pathlib.Path(temp)), \
                contextlib.redirect_stdout(io.StringIO()):
            report = reporting.platform_report("ios", "42", "failure", {"install_api": {"outcome": "failure"}})
            text = (pathlib.Path(temp) / "Build/Release/ios/summary.md").read_text()
        self.assertEqual(report["outcome"], "ERROR")
        self.assertIn("Install Apple API dependencies", text)
        self.assertIn("Build 42", text)

    def test_cleanup_failure_overrides_previously_successful_upload(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(reporting, "ROOT", pathlib.Path(temp)), \
                contextlib.redirect_stdout(io.StringIO()):
            path = pathlib.Path(temp) / "Build/Release/ios/report.json"
            reporting.save(dict(identity=identity("ios"), outcome="SUCCEEDED", uploadComplete=True), path)
            report = reporting.platform_report("ios", "", "failure", {"cleanup": {"outcome": "failure"}})
        self.assertEqual(report["errorCode"], "WORKFLOW_STEP_FAILED")
        self.assertIn("Remove temporary credentials", report["error"])
        self.assertNotIn("✅ Build uploaded", reporting.render(report))

    def test_mixed_platform_outcomes_and_absent_reports_are_reported(self):
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()) as output:
            reporting.save(dict(identity=identity("ios"), outcome="SUCCEEDED", uploadComplete=True),
                           pathlib.Path(temp) / "ios/report.json")
            code = reporting.aggregate(temp, "both", "success", "failure")
        self.assertEqual(code, 1)
        self.assertIn("IOS", output.getvalue())
        self.assertIn("MAC_OS", output.getvalue())
        self.assertIn("REPORT_UNAVAILABLE", output.getvalue())
        self.assertIn("UPLOADED", output.getvalue())

    def test_only_the_requested_platform_is_required(self):
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()):
            reporting.save(dict(identity=identity("ios"), outcome="SUCCEEDED", uploadComplete=True,
                                encryption="ACTION_REQUIRED"), pathlib.Path(temp) / "ios/report.json")
            self.assertEqual(reporting.aggregate(temp, "ios", "success", "success"), 0)

    def test_failed_audit_explains_the_cause_when_platform_jobs_never_started(self):
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()) as output:
            reporting.save(dict(identity=dict(platform="PREFLIGHT", build="42"), outcome="USER_ACTION_REQUIRED",
                                errorCode="ACTION_REQUIRED", error="Mac signing profile expired", failedStage="audit"),
                           pathlib.Path(temp) / "audit/report.json")
            self.assertEqual(reporting.aggregate(temp, "both", "failure", "skipped"), 1)
        self.assertIn("Mac signing profile expired", output.getvalue())
        self.assertIn("no platform work was started", output.getvalue())

    def test_summary_is_available_even_when_third_party_python_dependencies_are_missing(self):
        # -S omits site-packages, simulating a failed dependency-install step.
        result = subprocess.run([sys.executable, "-S", "-m", "Scripts.release.reporting", "--help"],
                                cwd=ROOT, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_annotations_redact_secrets_and_cannot_inject_new_workflow_commands(self):
        with patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "TEST_TOKEN": "private-test-token"}), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            annotation("private-test-token\n::error::injected", "Compliance, test\r\n", warning=True)
        value = output.getvalue()
        self.assertNotIn("private-test-token", value)
        self.assertEqual(len(value.splitlines()), 1)
        self.assertIn("%0A::error::injected", value)
        self.assertIn("%2C", value)

    def test_long_tool_errors_keep_a_short_reason_and_safe_expandable_details(self):
        report = dict(identity=identity("ios"), outcome="ERROR", failedStage="archive",
                      error="xcodebuild exited 65\nCompiler error: <script>example</script> test-secret")
        with patch.dict(os.environ, {"TEST_TOKEN": "test-secret"}):
            text = reporting.render(report)
        self.assertIn("**Reason:** xcodebuild exited 65\n", text)
        self.assertIn("Technical details", text)
        self.assertIn("&lt;script&gt;", text)
        self.assertNotIn("test-secret", text)


class ReportingRetryTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {"GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "10"})
        environment.start()
        self.addCleanup(environment.stop)

    def report(self, platform, attempt, outcome="SUCCEEDED", run_id="123"):
        return dict(identity=dict(platform=platform, version="0.1.1", build="13"), outcome=outcome,
                    workflowRun=dict(id=run_id, attempt=attempt))

    def aggregate(self, reports, **statuses):
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()) as output:
            for index, report in enumerate(reports):
                reporting.save(report, pathlib.Path(temp) / str(index) / "report.json")
            result = reporting.aggregate(temp, "both", statuses.get("audit", "success"),
                                         statuses.get("platform", "success"))
        return result, output.getvalue()

    def test_platform_report_stamps_the_actual_run_and_attempt(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(reporting, "ROOT", pathlib.Path(temp)), \
                contextlib.redirect_stdout(io.StringIO()):
            report = reporting.platform_report("macos", "13", "failure", {})
            saved = json.loads((pathlib.Path(temp) / "Build/Release/macos/report.json").read_text())
        self.assertEqual(report["workflowRun"], dict(id="123", attempt=10))
        self.assertEqual(saved["workflowRun"], report["workflowRun"])

    def test_partial_retry_replaces_stale_compliance_error_but_keeps_successful_ios(self):
        ios = self.report("IOS", 1)
        ios["verification"] = "READY_FOR_REVIEW"
        old_mac = self.report("MAC_OS", 1, "USER_ACTION_REQUIRED")
        old_mac.update(errorCode="EXPORT_COMPLIANCE_REQUIRED", error="Old compliance failure")
        new_mac = self.report("MAC_OS", 2)
        new_mac["verification"] = "READY_FOR_REVIEW"
        old_audit = self.report("PREFLIGHT", 1, "ERROR")
        old_audit["error"] = "Old preflight failure"
        result, text = self.aggregate([old_mac, self.report("PREFLIGHT", 2), new_mac, ios, old_audit])
        self.assertEqual(result, 0)
        self.assertIn("| IOS | 0.1.1 | 13 | READY_FOR_REVIEW |", text)
        self.assertIn("| MAC_OS | 0.1.1 | 13 | READY_FOR_REVIEW |", text)
        self.assertNotIn("Old compliance failure", text)
        self.assertNotIn("Old preflight failure", text)
        self.assertIn("Workflow attempt: 1", text)
        self.assertIn("Workflow attempt: 2", text)

    def test_newer_failure_is_not_hidden_by_old_success_and_attempts_are_numeric(self):
        reports = [self.report("IOS", 2), self.report("MAC_OS", 2), self.report("MAC_OS", 10, "ERROR")]
        reports[-1]["error"] = "Latest attempt failed"
        result, text = self.aggregate(reports)
        self.assertEqual(result, 1)
        self.assertIn("Latest attempt failed", text)
        self.assertIn("| MAC_OS | 0.1.1 | 13 | ERROR |", text)

    def test_rerunning_only_summary_reuses_latest_available_platform_reports(self):
        result, _ = self.aggregate([self.report("IOS", 1), self.report("MAC_OS", 2),
                                    self.report("PREFLIGHT", 1)])
        self.assertEqual(result, 0)

    def test_ambiguous_or_foreign_or_invalid_reports_cannot_produce_green_result(self):
        cases = [
            [self.report("MAC_OS", 2), self.report("MAC_OS", 2)],
            [self.report("MAC_OS", 1, run_id="another-run")],
            [self.report("MAC_OS", 11)],
            [self.report("MAC_OS", "2")],
            [dict(identity=dict(platform="MAC_OS"), outcome="SUCCEEDED")],
            [dict(identity=dict(platform="MAC_OS"), outcome="SUCCEEDED", workflowRun=dict(id="123"))],
            [],
        ]
        for mac_reports in cases:
            with self.subTest(reports=mac_reports):
                result, text = self.aggregate([self.report("IOS", 1), *mac_reports])
                self.assertEqual(result, 1)
                self.assertIn("REPORT_UNAVAILABLE", text)

    def test_latest_audit_failure_and_job_failure_still_fail_the_result(self):
        platforms = [self.report("IOS", 1), self.report("MAC_OS", 1)]
        result, _ = self.aggregate([*platforms, self.report("PREFLIGHT", 1),
                                    self.report("PREFLIGHT", 2, "ERROR")])
        self.assertEqual(result, 1)
        result, _ = self.aggregate(platforms, platform="failure")
        self.assertEqual(result, 1)


class WorkflowBoundaryTests(unittest.TestCase):
    def test_both_manual_workflows_share_serialization_and_always_publish_a_result(self):
        workflows = []
        for name in ("app-store-release.yml", "app-store-review.yml"):
            workflow = yaml.load((ROOT / ".github/workflows" / name).read_text(), Loader=yaml.BaseLoader)
            workflows.append(workflow)
            self.assertEqual(set(workflow["on"]), {"workflow_dispatch"})
            self.assertIn("always()", workflow["jobs"]["result"]["if"])
            self.assertEqual(workflow["jobs"]["prepare"]["strategy"]["max-parallel"], "1")
            self.assertIn("inputs.build_number", workflow["run-name"])
            for job in ("audit", "prepare"):
                reports = [s for s in workflow["jobs"][job]["steps"]
                           if s.get("with", {}).get("name", "").startswith("app-store-report-")]
                self.assertEqual(len(reports), 1)
                self.assertIn("${{ github.run_id }}-attempt-${{ github.run_attempt }}", reports[0]["with"]["name"])
            download = next(s for s in workflow["jobs"]["result"]["steps"]
                            if s.get("uses", "").startswith("actions/download-artifact@"))
            self.assertEqual(download["with"]["pattern"], "app-store-report-*-${{ github.run_id }}-attempt-*")
            self.assertNotEqual(download["with"].get("merge-multiple"), "true")
        self.assertEqual(workflows[0]["concurrency"], workflows[1]["concurrency"])
        upload = workflows[0]["jobs"]["prepare"]["steps"]
        upload_commands = "\n".join(s.get("run", "") for s in upload)
        for stage in ("metadata", "review", "draft"):
            self.assertNotIn("Scripts.release.cli " + stage + " ", upload_commands)
        self.assertIn("Scripts.release.cli uploaded ", upload_commands)
        review_text = (ROOT / ".github/workflows/app-store-review.yml").read_text()
        for forbidden in ("P12", "PROVISION_PROFILE", "xcodebuild", "ruby/setup-ruby", "fastlane"):
            self.assertNotIn(forbidden, review_text)
        steps = workflows[1]["jobs"]["prepare"]["steps"]
        ids = [s.get("id") for s in steps]
        self.assertLess(ids.index("compliance"), ids.index("metadata"))
        inputs = workflows[1]["on"]["workflow_dispatch"]["inputs"]
        self.assertEqual(inputs["build_number"]["required"], "true")
