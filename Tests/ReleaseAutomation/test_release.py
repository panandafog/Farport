import base64
import copy
import datetime
import io
import json
import os
import pathlib
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

import yaml

from Scripts.release.asc import (ApiError, Client, Store, Token, payload, relationship,
                                 sanitized, screenshots, upload_asset_operations)
from Scripts.release.cli import summary, verify_remote, status
from Scripts.release.metadata import (NeedsAction, ReleaseError, Waiting, ROOT, identity,
                                      metadata, release_notes, screenshot_files, complete_age_answers, asc_locale)
from Scripts.release.signing import binary, check_profile, expected_capabilities, archive_command, preflight, check_capabilities, provenance
from Scripts.release.artifact_source import validate_run


def resource(kind, id, attrs=None, rels=None):
    return payload(kind, attrs or {}, rels, id)["data"]


class FakeAPI:
    """In-memory Apple resource graph; never makes a network call."""
    def __init__(self):
        self.records = {}
        self.calls = []
        self.counter = 0
        self.app = self.add(resource("apps", "app", {"bundleId": "com.panandafog.harbor"}))
        for name in ("DEVELOPER_TOOLS",):
            self.add(resource("appCategories", name))
        self.pre = self.add(resource("preReleaseVersions", "pre", {"version": "0.1.1", "platform": "IOS"}))
        self.add(resource("builds", "build", {"version": identity("ios")["build"], "processingState": "VALID", "expired": False, "usesNonExemptEncryption": False},
                          {"app": ("apps", "app"), "preReleaseVersion": ("preReleaseVersions", "pre")}))
        self.add(resource("appInfos", "info", {"state": "PREPARE_FOR_SUBMISSION"}, {"app": ("apps", "app")}))
        self.add(resource("ageRatingDeclarations", "age", {"messagingAndChat": False, "unrestrictedWebAccess": False, "userGeneratedContent": False}, {"appInfo": ("appInfos", "info")}))

    def add(self, value):
        self.records[value["type"], value["id"]] = value
        return value

    def list(self, path, params=None):
        self.calls.append(("GET", path))
        parts = path.split("/")[2:]
        if len(parts) == 1:
            result = [v for (kind, _), v in self.records.items() if kind == parts[0]]
        else:
            parent, id, relation = parts
            parent_key = {"apps": "app", "appInfos": "appInfo", "appStoreVersions": "appStoreVersion",
                          "reviewSubmissions": "reviewSubmission", "appStoreVersionLocalizations": "appStoreVersionLocalization",
                          "appScreenshotSets": "appScreenshotSet"}[parent]
            kind = "reviewSubmissionItems" if relation == "items" else relation
            result = [v for (typ, _), v in self.records.items() if typ == kind and relationship(v, parent_key) == id]
        for key, value in (params or {}).items():
            if key in {"filter[platform]", "filter[versionString]", "filter[bundleId]", "filter[version]"}:
                attr = key[7:-1]
                result = [v for v in result if v["attributes"].get(attr) == value]
        return copy.deepcopy(result)

    def get(self, path):
        self.calls.append(("GET", path))
        parts = path.split("/")[2:]
        value = self.records[parts[0], parts[1]]
        if len(parts) == 3:
            rel = parts[2]
            if rel in {"ageRatingDeclaration", "appStoreReviewDetail"}:
                kind = {"ageRatingDeclaration": "ageRatingDeclarations", "appStoreReviewDetail": "appStoreReviewDetails"}[rel]
                parent_key = "appInfo" if rel == "ageRatingDeclaration" else "appStoreVersion"
                matches = [v for (typ, _), v in self.records.items() if typ == kind and relationship(v, parent_key) == value["id"]]
                if not matches:
                    raise ApiError(404)
                value = matches[0]
            else:
                data = value["relationships"][rel]["data"]
                value = self.records[data["type"], data["id"]]
        return copy.deepcopy(value)

    def create(self, kind, attrs=None, rels=None):
        self.calls.append(("POST", "/v1/" + kind))
        attrs = dict(attrs or {})
        if kind in {"appInfoLocalizations", "appStoreVersionLocalizations"} and attrs.get("locale") not in {"en-US", "ru"}:
            # Apple's locale shortcodes differ from repository folder names.
            raise ApiError(409, [{"code": "ENTITY_ERROR.ATTRIBUTE.INVALID", "source": {"pointer": "/data/attributes/locale"}}])
        if kind in {"reviewSubmissions", "reviewSubmissionItems"}:
            attrs["state"] = "READY_FOR_REVIEW"
        if kind == "appStoreVersions":
            attrs["appVersionState"] = "PREPARE_FOR_SUBMISSION"
        if kind == "appScreenshots":
            attrs |= {"assetDeliveryState": {"state": "AWAITING_UPLOAD"}, "uploadOperations": [dict(method="PUT", url="https://storage.example/upload", offset=0, length=attrs["fileSize"])]}
        self.counter += 1
        value = self.add(resource(kind, kind + "created" + str(self.counter), attrs, rels))
        if kind == "reviewSubmissionItems":
            self.records["appStoreVersions", relationship(value, "appStoreVersion")]["attributes"]["appVersionState"] = "READY_FOR_REVIEW"
        return copy.deepcopy(value)

    def update(self, value, attrs=None, rels=None):
        self.calls.append(("PATCH", f"/v1/{value['type']}/{value['id']}"))
        target = self.records[value["type"], value["id"]]
        target["attributes"].update(attrs or {})
        if rels:
            target.setdefault("relationships", {}).update(payload(value["type"], rels=rels)["data"]["relationships"])
        if (attrs or {}).get("uploaded"):
            target["attributes"]["assetDeliveryState"] = {"state": "COMPLETE"}
        return copy.deepcopy(target)

    def request(self, method, path, data=None, params=None):
        self.calls.append((method, path))
        parts = path.split("/")[2:]
        if method == "GET" and len(parts) == 4 and parts[2:] == ["relationships", "build"]:
            value = self.records[parts[0], parts[1]]
            return {"data": copy.deepcopy(value.get("relationships", {}).get("build", {}).get("data"))}
        if method == "DELETE":
            self.records.pop((parts[0], parts[1]), None)
        return {}


class StateTests(unittest.TestCase):
    def setUp(self):
        self.api = FakeAPI()
        self.ident = identity("ios")
        self.config, self.locales, self.review, self.copyright = metadata()
        self.report = {"identity": self.ident, "actions": []}
        self.time = 0
        self.store = Store(self.api, self.ident, self.config, self.report, sleep=self.tick, clock=lambda: self.time)

    def tick(self, value):
        self.time += value

    def test_initial_age_declaration_covers_fields_reported_by_live_apple_409(self):
        # Independent regression fixture from the first real Apple validation
        # response: the old seven-boolean payload omitted all sixteen below.
        required_by_apple = {
            "medicalOrTreatmentInformation", "horrorOrFearThemes", "violenceCartoonOrFantasy",
            "violenceRealisticProlongedGraphicOrSadistic", "gunsOrOtherWeapons", "profanityOrCrudeHumor",
            "ageAssurance", "gamblingSimulated", "contests", "healthOrWellnessTopics", "sexualContentOrNudity",
            "alcoholTobaccoOrDrugUseOrReferences", "parentalControls", "matureOrSuggestiveThemes",
            "sexualContentGraphicAndNudity", "violenceRealistic"
        }
        original = self.api.update
        def apple_update(resource, attrs=None, rels=None):
            if resource["type"] == "ageRatingDeclarations":
                self.assertFalse(required_by_apple - attrs.keys())
                self.assertEqual(len(attrs), 24)
                self.assertNotIn("kidsAgeBand", attrs)
                self.assertNotIn("ageRatingOverrideV2", attrs)
            return original(resource, attrs, rels)
        with patch.object(self.api, "update", side_effect=apple_update):
            self.store.metadata(self.store.ensure_version(), self.locales, self.copyright)
        self.assertIn("SUCCEEDED", self.report["ageRating"])

    def test_unspecified_age_overrides_are_preserved(self):
        self.api.records["ageRatingDeclarations", "age"]["attributes"]["ageRatingOverrideV2"] = "NINE_PLUS"
        self.store.configure_age_rating(self.api.get("/v1/appInfos/info"))
        self.assertEqual(self.api.records["ageRatingDeclarations", "age"]["attributes"]["ageRatingOverrideV2"], "NINE_PLUS")

    def test_partial_config_reuses_explicit_existing_answers_including_false(self):
        existing = {k: v if v is not None else False for k, v in self.config["ageRating"].items()}
        result = complete_age_answers({"advertising": False}, existing)
        self.assertEqual(result, existing)
        self.assertIs(result["ageAssurance"], False)

    def test_missing_age_answer_is_not_guessed(self):
        self.store.config = {**self.config, "ageRating": {k: v for k, v in self.config["ageRating"].items() if k != "medicalOrTreatmentInformation"}}
        with self.assertRaises(NeedsAction) as error:
            self.store.configure_age_rating(self.api.get("/v1/appInfos/info"))
        self.assertIn("medicalOrTreatmentInformation", str(error.exception))
        self.assertFalse(any(method == "PATCH" for method, _ in self.api.calls))

    def test_invalid_age_answer_types_are_rejected_before_patch(self):
        for values in ({"ageAssurance": "false"}, {"contests": "AUTOMATIC"}, {"contests": []}):
            with self.subTest(values=values), self.assertRaises(NeedsAction):
                complete_age_answers(self.config["ageRating"] | values, {})

    def test_age_answers_are_not_patched_again_when_unchanged(self):
        info = self.api.get("/v1/appInfos/info")
        self.store.configure_age_rating(info)
        self.api.calls.clear()
        self.store.configure_age_rating(info)
        self.assertFalse(any(method == "PATCH" for method, _ in self.api.calls))

    def test_age_success_requires_readback_of_supplied_answers(self):
        with patch.object(self.api, "update", return_value=resource("ageRatingDeclarations", "age", {})):
            with self.assertRaises(NeedsAction):
                self.store.configure_age_rating(self.api.get("/v1/appInfos/info"))
        self.assertNotIn("SUCCEEDED", self.report["ageRating"])

    def test_create_version_once_and_preserve_existing_release_setting(self):
        version = self.store.ensure_version()
        self.assertEqual(version["attributes"]["releaseType"], "MANUAL")
        self.api.records["appStoreVersions", version["id"]]["attributes"]["releaseType"] = "AFTER_APPROVAL"
        self.assertEqual(self.store.ensure_version()["id"], version["id"])
        self.assertEqual(sum(m == "POST" and p == "/v1/appStoreVersions" for m, p in self.api.calls), 1)
        self.assertEqual(self.store.ensure_version()["attributes"]["releaseType"], "AFTER_APPROVAL")

    def test_active_review_blocks_all_mutations(self):
        self.api.add(resource("reviewSubmissions", "active", {"state": "IN_REVIEW", "platform": "IOS"}, {"app": ("apps", "app")}))
        with self.assertRaises(NeedsAction):
            self.store.ensure_version()
        self.assertFalse(any(m != "GET" for m, _ in self.api.calls))

    def test_published_version_is_readonly(self):
        version = self.store.ensure_version()
        self.api.records["appStoreVersions", version["id"]]["attributes"]["appVersionState"] = "READY_FOR_DISTRIBUTION"
        with self.assertRaises(NeedsAction):
            self.store.ensure_version()

    def test_another_editable_version_is_not_repurposed(self):
        self.api.create("appStoreVersions", {"versionString": "0.2.0", "platform": "IOS"}, {"app": ("apps", "app")})
        with self.assertRaises(NeedsAction):
            self.store.ensure_version()

    def initial_draft(self, version="1.0", **attrs):
        return self.api.create("appStoreVersions", {"versionString": version, "platform": "IOS", "releaseType": "AFTER_APPROVAL", **attrs}, {"app": ("apps", "app")})

    def test_initial_empty_draft_is_reused_without_changing_id_or_release_policy(self):
        initial = self.initial_draft()
        self.store.upsert_locale(initial, "appStoreVersionLocalizations", "appStoreVersionLocalizations", "en-US", {})
        version = self.store.ensure_version()
        self.assertEqual(version["id"], initial["id"])
        self.assertEqual(version["attributes"]["versionString"], "0.1.1")
        self.assertEqual(version["attributes"]["releaseType"], "AFTER_APPROVAL")
        self.assertIn("REUSED_EMPTY_INITIAL_DRAFT", self.report["versionPreparation"])
        self.store.ensure_version()
        self.assertEqual(sum(m == "POST" and p == "/v1/appStoreVersions" for m, p in self.api.calls), 1)
        self.assertEqual(self.api.calls.count(("PATCH", f"/v1/appStoreVersions/{initial['id']}")), 1)

    def test_initial_draft_with_selected_build_is_preserved(self):
        initial = self.initial_draft()
        self.api.update(initial, rels={"build": ("builds", "build")})
        with self.assertRaises(NeedsAction):
            self.store.ensure_version()
        self.assertEqual(self.api.get(f"/v1/appStoreVersions/{initial['id']}")["attributes"]["versionString"], "1.0")

    def test_initial_100_placeholder_is_supported(self):
        initial = self.initial_draft("1.0.0")
        self.assertEqual(self.store.ensure_version()["id"], initial["id"])
        self.assertIn("1.0.0 -> 0.1.1", self.report["versionPreparation"])

    def test_unknown_build_relationship_does_not_mean_unbound(self):
        self.initial_draft()
        with patch.object(self.api, "request", return_value={}), self.assertRaises(NeedsAction):
            self.store.ensure_version()
        self.assertFalse(any(method == "PATCH" for method, _ in self.api.calls))

    def test_concurrently_changed_initial_draft_is_not_renumbered(self):
        initial = self.initial_draft()
        original_get = self.api.get
        def changed_get(path):
            if path == f"/v1/appStoreVersions/{initial['id']}":
                self.api.records["appStoreVersions", initial["id"]]["attributes"]["appVersionState"] = "IN_REVIEW"
            return original_get(path)
        with patch.object(self.api, "get", side_effect=changed_get), self.assertRaises(NeedsAction):
            self.store.ensure_version()
        self.assertFalse(any(method == "PATCH" for method, _ in self.api.calls))

    def test_mac_initial_draft_uses_only_matching_native_mac_build(self):
        initial = self.api.create("appStoreVersions", {"versionString": "1.0", "platform": "MAC_OS"}, {"app": ("apps", "app")})
        self.api.add(resource("preReleaseVersions", "mac-pre", {"version": "0.1.1", "platform": "MAC_OS"}))
        self.api.add(resource("builds", "mac-build", {"version": identity("ios")["build"], "processingState": "VALID", "expired": False},
                              {"app": ("apps", "app"), "preReleaseVersion": ("preReleaseVersions", "mac-pre")}))
        mac = Store(self.api, identity("macos"), self.config, {})
        version = mac.ensure_version()
        self.assertEqual(version["id"], initial["id"])
        self.assertEqual(version["attributes"]["platform"], "MAC_OS")
        self.assertEqual(version["attributes"]["versionString"], "0.1.1")

    def test_initial_draft_with_localized_content_is_preserved(self):
        initial = self.initial_draft()
        self.store.upsert_locale(initial, "appStoreVersionLocalizations", "appStoreVersionLocalizations", "en-US", {"description": "Owner's existing release"})
        with self.assertRaises(NeedsAction):
            self.store.ensure_version()

    def test_initial_draft_with_media_is_preserved(self):
        initial = self.initial_draft()
        locale = self.store.upsert_locale(initial, "appStoreVersionLocalizations", "appStoreVersionLocalizations", "en-US", {})
        self.api.create("appScreenshotSets", {"screenshotDisplayType": "APP_IPHONE_67"}, {"appStoreVersionLocalization": ("appStoreVersionLocalizations", locale["id"])})
        with self.assertRaises(NeedsAction):
            self.store.ensure_version()

    def test_initial_draft_after_published_history_is_preserved(self):
        self.initial_draft()
        published = self.api.create("appStoreVersions", {"versionString": "0.0.1", "platform": "IOS"}, {"app": ("apps", "app")})
        self.api.records["appStoreVersions", published["id"]]["attributes"]["appVersionState"] = "READY_FOR_DISTRIBUTION"
        with self.assertRaises(NeedsAction):
            self.store.ensure_version()

    def test_initial_draft_with_review_history_is_preserved(self):
        self.initial_draft()
        self.api.add(resource("reviewSubmissions", "history", {"state": "COMPLETE", "platform": "IOS"}, {"app": ("apps", "app")}))
        with self.assertRaises(NeedsAction):
            self.store.ensure_version()

    def test_initial_draft_waits_for_valid_target_build(self):
        self.initial_draft()
        self.api.records["builds", "build"]["attributes"]["processingState"] = "PROCESSING"
        with self.assertRaises(NeedsAction):
            self.store.ensure_version()

    def test_ready_for_review_placeholder_is_not_renumbered(self):
        initial = self.initial_draft()
        self.api.records["appStoreVersions", initial["id"]]["attributes"]["appVersionState"] = "READY_FOR_REVIEW"
        with self.assertRaises(NeedsAction):
            self.store.ensure_version()

    def test_status_explains_version_mismatch_without_mutations(self):
        from Scripts.release.cli import status
        self.initial_draft()
        self.api.calls.clear()
        with self.assertRaises(NeedsAction) as caught:
            status(self.store, self.locales)
        self.assertIn("1.0 (PREPARE_FOR_SUBMISSION)", str(caught.exception))
        self.assertIn("VALID", str(caught.exception))
        self.assertFalse(any(method != "GET" for method, _ in self.api.calls))

    def test_build_filter_is_independently_verified(self):
        self.assertEqual(self.store.find_build()["id"], "build")
        self.api.records["preReleaseVersions", "pre"]["attributes"]["platform"] = "MAC_OS"
        self.assertIsNone(self.store.find_build())

    def test_wrong_app_build_is_not_selected(self):
        self.api.records["apps", "app"]["attributes"]["bundleId"] = "com.other.app"
        self.assertIsNone(self.store.find_build())

    def test_invalid_expired_build_requires_new_number(self):
        for attrs in [{"processingState": "INVALID"}, {"expired": True}]:
            with self.subTest(attrs=attrs):
                self.api.records["builds", "build"]["attributes"].update(attrs)
                with self.assertRaises(NeedsAction):
                    self.store.wait_build()

    def test_wait_for_processing_instead_of_upload_success(self):
        self.api.records["builds", "build"]["attributes"]["processingState"] = "PROCESSING"
        def sleep(value):
            self.tick(value)
            if self.time >= 40:
                self.api.records["builds", "build"]["attributes"]["processingState"] = "VALID"
        self.store.sleep = sleep
        self.assertEqual(self.store.wait_build()["id"], "build")
        self.assertEqual(self.time, 40)

    def test_processing_timeout_is_waiting_not_invalid(self):
        self.api.records["builds", "build"]["attributes"]["processingState"] = "PROCESSING"
        self.store.config = {**self.config, "processingTimeoutSeconds": 40}
        with self.assertRaises(Waiting):
            self.store.wait_build()
        self.assertEqual(self.report["processing"], "PROCESSING")

    def test_not_yet_visible_timeout(self):
        self.api.records.pop(("builds", "build"))
        self.store.config = {**self.config, "processingTimeoutSeconds": 20}
        with self.assertRaises(Waiting):
            self.store.wait_build()
        self.assertEqual(self.report["processing"], "NOT_VISIBLE_YET")

    def test_upload_receipt_prevents_duplicate_before_build_is_visible(self):
        self.api.records.pop(("builds", "build"))
        self.api.add(resource("buildUploads", "receipt", {"cfBundleShortVersionString": "0.1.1", "cfBundleVersion": self.ident["build"], "platform": "IOS", "state": {"state": "PROCESSING"}}, {"app": ("apps", "app")}))
        self.assertIsNone(self.store.find_build())
        self.assertEqual(self.store.find_upload()["id"], "receipt")
        self.assertIn("ALREADY_RECEIVED", self.report["upload"])

    def test_failed_upload_receipt_is_not_deleted_or_overwritten(self):
        self.api.add(resource("buildUploads", "receipt", {"cfBundleShortVersionString": "0.1.1", "cfBundleVersion": self.ident["build"], "platform": "IOS", "state": {"state": "FAILED"}}, {"app": ("apps", "app")}))
        with self.assertRaises(NeedsAction):
            self.store.find_upload()
        self.assertFalse(any(m == "DELETE" for m, _ in self.api.calls))

    def test_receipt_of_another_version_is_ignored(self):
        self.api.add(resource("buildUploads", "receipt", {"cfBundleShortVersionString": "0.2.0", "cfBundleVersion": self.ident["build"], "platform": "IOS", "state": {"state": "PROCESSING"}}, {"app": ("apps", "app")}))
        self.assertIsNone(self.store.find_upload())

    def test_bind_and_review_do_not_invent_phone_or_account(self):
        version = self.store.ensure_version()
        self.store.bind(version, self.store.find_build())
        with patch.dict(os.environ, {}, clear=True), self.assertRaises(NeedsAction):
            self.store.configure_review(version, self.review)
        with patch.dict(os.environ, {"ASC_REVIEW_CONTACT_PHONE": "+10000000000"}):
            self.store.configure_review(version, self.review)
        review = self.api.get(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")
        self.assertTrue(review["attributes"]["demoAccountRequired"])
        self.assertEqual(review["attributes"]["demoAccountPassword"], "bandit0")
        with patch.dict(os.environ, {}, clear=True):
            self.store.configure_review(version, self.review)

    def test_localization_omissions_preserve_remote_values(self):
        version = self.store.ensure_version()
        locale = self.store.upsert_locale(version, "appStoreVersionLocalizations", "appStoreVersionLocalizations", "en-US", {"description": "old", "marketingUrl": "https://example.org"})
        updated = self.store.upsert_locale(version, "appStoreVersionLocalizations", "appStoreVersionLocalizations", "en-US", {"description": "new", "marketingUrl": ""})
        self.assertEqual(updated["attributes"]["marketingUrl"], "https://example.org")
        self.assertEqual(updated["id"], locale["id"])

    def test_russian_metadata_uses_apple_shortcode_without_changing_source_keys(self):
        locales = self.store.metadata(self.store.ensure_version(), self.locales, self.copyright)
        self.assertEqual(set(locales), {"en-US", "ru-RU"})
        self.assertEqual(locales["ru-RU"]["attributes"]["locale"], "ru")
        info = self.api.list("/v1/appInfos/info/appInfoLocalizations")
        self.assertEqual({x["attributes"]["locale"] for x in info}, {"en-US", "ru"})
        self.assertEqual(locales["ru-RU"]["attributes"]["description"], self.locales["ru-RU"]["description"])

    def test_existing_russian_localizations_are_reused_on_repeated_runs(self):
        version = self.store.ensure_version()
        existing = {}
        for kind, parent, relation in [
            ("appInfoLocalizations", ("appInfos", "info"), "appInfo"),
            ("appStoreVersionLocalizations", ("appStoreVersions", version["id"]), "appStoreVersion")
        ]:
            existing[kind] = self.api.create(kind, {"locale": "ru"}, {relation: parent})["id"]
        self.store.metadata(version, self.locales, self.copyright)
        self.api.calls.clear()
        locales = self.store.metadata(version, self.locales, self.copyright)
        self.assertEqual(locales["ru-RU"]["id"], existing["appStoreVersionLocalizations"])
        for kind, id in existing.items():
            matches = [v for (typ, _), v in self.api.records.items() if typ == kind and v["attributes"]["locale"] == "ru"]
            self.assertEqual([v["id"] for v in matches], [id])
            self.assertNotIn(("POST", "/v1/" + kind), self.api.calls)
            self.assertNotIn(("PATCH", f"/v1/{kind}/{id}"), self.api.calls)

    def test_locale_mapping_preserves_regions_and_rejects_unknown_languages(self):
        self.assertEqual(asc_locale("en-US"), "en-US")
        self.assertEqual(asc_locale("ru-RU"), "ru")
        with self.assertRaises(ReleaseError):
            asc_locale("en-GB")

    def test_live_app_information_is_not_edited(self):
        self.api.records["appInfos", "info"]["attributes"]["state"] = "READY_FOR_DISTRIBUTION"
        with self.assertRaises(NeedsAction):
            self.store.metadata(self.store.ensure_version(), self.locales, self.copyright)

    def test_mac_reuses_identical_shared_info_after_ios_draft_readonly(self):
        self.store.metadata(self.store.ensure_version(), self.locales, self.copyright)
        self.api.records["appInfos", "info"]["attributes"]["state"] = "READY_FOR_REVIEW"
        self.api.calls.clear()
        mac = Store(self.api, identity("macos"), self.config, {}, sleep=self.tick, clock=lambda: self.time)
        mac.metadata(mac.ensure_version(), self.locales, self.copyright)
        self.assertFalse(any(m == "PATCH" and any(part in p for part in ("/appInfos/", "/appInfoLocalizations/", "/ageRatingDeclarations/")) for m, p in self.api.calls))

    def test_missing_mac_platform_is_registered_before_first_upload(self):
        mac = Store(self.api, identity("macos"), self.config, {}, sleep=self.tick, clock=lambda: self.time)
        mac.prepare_upload_platform()
        mac.prepare_upload_platform()
        versions = mac.versions()
        self.assertEqual(len(versions), 1)
        self.assertEqual(versions[0]["attributes"]["platform"], "MAC_OS")
        self.assertEqual(versions[0]["attributes"]["versionString"], mac.identity["version"])
        self.assertEqual(versions[0]["attributes"]["releaseType"], "MANUAL")
        self.assertIsNone(mac.find_build())
        self.assertEqual(self.api.calls.count(("POST", "/v1/appStoreVersions")), 1)

    def test_upload_registration_preserves_existing_initial_placeholder(self):
        initial = self.api.create("appStoreVersions", {"platform": "IOS", "versionString": "1.0"}, {"app": ("apps", "app")})
        self.api.records.pop(("builds", "build"))
        self.api.calls.clear()
        self.store.prepare_upload_platform()
        self.assertEqual(self.api.records["appStoreVersions", initial["id"]]["attributes"]["versionString"], "1.0")
        self.assertFalse(any(method in {"POST", "PATCH", "DELETE"} for method, _ in self.api.calls))

    def test_upload_registration_preserves_platform_in_active_review(self):
        self.api.create("reviewSubmissions", {"platform": "IOS"}, {"app": ("apps", "app")})
        for (kind, _), value in self.api.records.items():
            if kind == "reviewSubmissions":
                value["attributes"]["state"] = "IN_REVIEW"
        self.api.calls.clear()
        with self.assertRaises(NeedsAction):
            self.store.prepare_upload_platform()
        self.assertFalse(any(method in {"POST", "PATCH", "DELETE"} for method, _ in self.api.calls))

    def test_draft_creation_is_idempotent_and_never_submits(self):
        version = self.store.ensure_version()
        build = self.store.find_build()
        self.store.bind(version, build)
        self.store.draft(version, build)
        self.store.draft(version, build)
        self.assertEqual(self.report["draftState"], "READY_FOR_REVIEW")
        self.assertEqual(sum(m == "POST" and p == "/v1/reviewSubmissions" for m, p in self.api.calls), 1)
        self.assertEqual(sum(m == "POST" and p == "/v1/reviewSubmissionItems" for m, p in self.api.calls), 1)
        self.assertFalse(any(m == "PATCH" and "/reviewSubmissions" in p for m, p in self.api.calls))

    def test_blocked_review_item_preserves_draft_and_reuses_it_after_owner_setup(self):
        version = self.store.ensure_version()
        build = self.store.find_build()
        self.store.bind(version, build)
        create = self.api.create
        def blocked(kind, attrs=None, rels=None):
            if kind == "reviewSubmissionItems":
                raise ApiError(409, [{"code": "STATE_ERROR.ENTITY_STATE_INVALID"}], "POST /v1/reviewSubmissionItems")
            return create(kind, attrs, rels)
        with patch.object(self.api, "create", side_effect=blocked), self.assertRaises(ApiError):
            self.store.draft(version, build)
        draft_id = self.report["draftId"]
        self.assertEqual(self.report["draftState"], "READY_FOR_REVIEW")
        self.assertEqual(self.report["versionState"], "PREPARE_FOR_SUBMISSION")
        self.assertNotIn("verification", self.report)
        self.store.draft(version, build)
        self.assertEqual(self.report["draftId"], draft_id)
        self.assertEqual(sum(m == "POST" and p == "/v1/reviewSubmissions" for m, p in self.api.calls), 1)

    def test_status_rereads_version_when_collection_lags_after_draft(self):
        version = self.store.ensure_version()
        build = self.store.find_build()
        self.store.bind(version, build)
        self.store.draft(version, build)
        stale = copy.deepcopy(version)
        stale["attributes"]["appVersionState"] = "PREPARE_FOR_SUBMISSION"
        with patch.object(self.store, "versions", return_value=[stale]), patch("Scripts.release.cli.verify_remote"):
            status(self.store, self.locales)
        self.assertTrue(self.report["verification"].startswith("READY_FOR_REVIEW"))

    def test_status_does_not_assume_ready_when_version_resource_is_unprepared(self):
        self.store.ensure_version()
        with self.assertRaisesRegex(NeedsAction, "PREPARE_FOR_SUBMISSION"):
            status(self.store, self.locales)
        self.assertNotIn("verification", self.report)

    def test_status_rejects_changed_identity_in_version_resource(self):
        version = self.store.ensure_version()
        self.api.records["appStoreVersions", version["id"]]["attributes"]["platform"] = "MAC_OS"
        with patch.object(self.store, "versions", return_value=[version]), self.assertRaisesRegex(NeedsAction, "identity changed"):
            status(self.store, self.locales)
        self.assertNotIn("verification", self.report)

    def test_draft_wrong_build_is_rejected(self):
        version = self.store.ensure_version()
        self.store.bind(version, self.store.find_build())
        with self.assertRaises(ReleaseError):
            self.store.draft(version, resource("builds", "wrong"))

    def test_other_version_in_draft_is_preserved(self):
        version = self.store.ensure_version()
        build = self.store.find_build(); self.store.bind(version, build)
        draft = self.api.create("reviewSubmissions", {"platform": "IOS"}, {"app": ("apps", "app")})
        self.api.add(resource("reviewSubmissionItems", "other", {"state": "READY_FOR_REVIEW"}, {"reviewSubmission": ("reviewSubmissions", draft["id"]), "appStoreVersion": ("appStoreVersions", "other")}))
        with self.assertRaises(NeedsAction):
            self.store.draft(version, build)
        self.assertIn(("reviewSubmissionItems", "other"), self.api.records)

    def test_screenshots_resume_without_duplicates(self):
        version = self.store.ensure_version()
        locales = self.store.metadata(version, self.locales, self.copyright)
        group = self.config["screenshotGroups"][0]
        files = screenshot_files(group, "en-US")
        with patch("Scripts.release.asc.upload_asset_operations") as upload:
            screenshots(self.store, locales["en-US"], group, files)
            self.assertEqual(upload.call_count, 8)
            upload.reset_mock()
            screenshots(self.store, locales["en-US"], group, files)
            upload.assert_not_called()
        self.assertEqual(sum(kind == "appScreenshots" for kind, _ in self.api.records), 8)

    def test_screenshot_partial_upload_is_resumable(self):
        version = self.store.ensure_version()
        locales = self.store.metadata(version, self.locales, self.copyright)
        group = self.config["screenshotGroups"][0]
        files = screenshot_files(group, "en-US")
        with patch("Scripts.release.asc.upload_asset_operations", side_effect=ReleaseError("transfer interrupted")):
            with self.assertRaises(ReleaseError):
                screenshots(self.store, locales["en-US"], group, files)
        with patch("Scripts.release.asc.upload_asset_operations"):
            screenshots(self.store, locales["en-US"], group, files)
        self.assertEqual(sum(kind == "appScreenshots" for kind, _ in self.api.records), 8)

    def test_unmanaged_screenshots_are_not_deleted(self):
        version = self.store.ensure_version()
        locales = self.store.metadata(version, self.locales, self.copyright)
        aset = self.api.create("appScreenshotSets", {"screenshotDisplayType": "APP_IPHONE_67"}, {"appStoreVersionLocalization": ("appStoreVersionLocalizations", locales["en-US"]["id"])})
        self.api.create("appScreenshots", {"fileName": "owner.png", "fileSize": 5}, {"appScreenshotSet": ("appScreenshotSets", aset["id"])})
        with self.assertRaises(NeedsAction):
            screenshots(self.store, locales["en-US"], self.config["screenshotGroups"][0], screenshot_files(self.config["screenshotGroups"][0], "en-US"))
        self.assertFalse(any(m == "DELETE" for m, _ in self.api.calls))

    def test_failed_managed_asset_is_replaced_and_deleted_only_once(self):
        version = self.store.ensure_version()
        locales = self.store.metadata(version, self.locales, self.copyright)
        group = self.config["screenshotGroups"][0]; files = screenshot_files(group, "en-US")
        with patch("Scripts.release.asc.upload_asset_operations"):
            screenshots(self.store, locales["en-US"], group, files)
            failed = next(v for (kind, _), v in self.api.records.items() if kind == "appScreenshots")
            failed["attributes"]["assetDeliveryState"] = {"state": "FAILED"}
            screenshots(self.store, locales["en-US"], group, files)
        self.assertEqual(self.api.calls.count(("DELETE", "/v1/appScreenshots/" + failed["id"])), 1)

    def test_full_preparation_readback(self):
        version = self.store.ensure_version()
        build = self.store.find_build()
        self.store.bind(version, build)
        locales = self.store.metadata(version, self.locales, self.copyright)
        with patch("Scripts.release.asc.upload_asset_operations"):
            for group in self.config["screenshotGroups"]:
                if group["platform"] == "IOS" and group["displayType"]:
                    for locale, value in locales.items():
                        screenshots(self.store, value, group, screenshot_files(group, locale))
        with patch.dict(os.environ, {"ASC_REVIEW_CONTACT_PHONE": "+10000000000"}):
            self.store.configure_review(version, self.review)
        verify_remote(self.store, version, build, self.locales)
        # Readback must also validate Russian metadata and its matching local PNGs.
        russian = locales["ru-RU"]
        self.assertEqual(russian["attributes"]["locale"], "ru")
        self.api.records[russian["type"], russian["id"]]["attributes"]["description"] = "different Russian copy"
        with self.assertRaises(NeedsAction):
            verify_remote(self.store, version, build, self.locales)
        self.api.records[russian["type"], russian["id"]]["attributes"]["description"] = self.locales["ru-RU"]["description"]
        self.store.draft(version, build)
        self.assertEqual(self.report["versionState"], "READY_FOR_REVIEW")


class Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class Opener:
    def __init__(self, *responses):
        self.responses = list(responses)
        self.requests = []

    def open(self, request, timeout=None):
        self.requests.append(request)
        value = self.responses.pop(0)
        if isinstance(value, Exception):
            raise value
        return Response(json.dumps(value).encode())


class TransportTests(unittest.TestCase):
    def test_get_retries_429_and_5xx(self):
        opener = Opener(urllib.error.HTTPError("", 429, "", {"Retry-After": "1"}, io.BytesIO(b"{}")),
                        urllib.error.HTTPError("", 503, "", {}, io.BytesIO(b"{}")), {"data": []})
        sleep = []
        self.assertEqual(Client(lambda: "fake", opener, sleep.append).list("/v1/apps"), [])
        self.assertEqual(sleep, [1, 2])

    def test_ambiguous_post_is_not_retried(self):
        opener = Opener(TimeoutError())
        with self.assertRaises(ReleaseError):
            Client(lambda: "fake", opener).create("reviewSubmissions", {"platform": "IOS"})
        self.assertEqual(len(opener.requests), 1)

    def test_api_errors_do_not_echo_sensitive_body(self):
        error = urllib.error.HTTPError("", 409, "", {}, io.BytesIO(json.dumps({"errors": [{"code": "ENTITY_ERROR", "detail": "private demo password", "source": {"pointer": "/data/attributes/contactPhone"}}]}).encode()))
        with self.assertRaises(ApiError) as captured:
            Client(lambda: "fake", Opener(error)).create("reviewSubmissions")
        self.assertNotIn("private demo password", str(captured.exception))
        self.assertIn("ENTITY_ERROR", str(captured.exception))

    def test_review_item_error_reports_nested_apple_prerequisites(self):
        errors = [{"code": "STATE_ERROR.ENTITY_STATE_INVALID", "detail": "This resource cannot be reviewed; check associated errors.",
                   "meta": {"associatedErrors": {"/apps/app": [
                       {"code": "STATE_ERROR.APP_PRIVACY_REQUIRED", "detail": "An Admin must provide privacy practices in App Privacy."},
                       {"code": "STATE_ERROR.PRICE_REQUIRED", "detail": "You must choose a price tier in Pricing."},
                       {"code": "STATE_ERROR.CONTENT_RIGHTS_REQUIRED", "detail": "Set up Content Rights Information in App Information."}
                   ]}, "unrelated": {"detail": "private unrelated body"}}}]
        response = urllib.error.HTTPError("", 409, "", {}, io.BytesIO(json.dumps({"errors": errors}).encode()))
        with self.assertRaises(ApiError) as captured:
            Client(lambda: "fake", Opener(response)).create("reviewSubmissionItems", rels={"reviewSubmission": ("reviewSubmissions", "draft")})
        error = captured.exception
        self.assertEqual(len(error.codes), 4)
        self.assertIn("App Privacy", str(error))
        self.assertIn("price tier", str(error))
        self.assertIn("Content Rights", str(error))
        self.assertNotIn("private unrelated body", str(error))

    def test_review_validation_redacts_sensitive_details(self):
        errors = [{"code": "STATE_ERROR", "detail": "Check settings.", "meta": {"associatedErrors": {"/apps/app": [
            {"code": "INVALID", "detail": "Value is 79991234567", "source": {"pointer": "/data/attributes/contactPhone"}},
            {"code": "INVALID", "detail": "Incorrect demoAccountPassword: private-demo-value"},
            {"code": "INVALID", "detail": "Contact user@example.org at +1 (999) 123-4567."},
            {"code": "INVALID", "detail": "Owner value: test-sensitive-value"}
        ]}}}]
        with patch.dict(os.environ, {"ASC_REVIEW_CONTACT_PHONE": "test-sensitive-value"}):
            error = ApiError(409, errors, "POST /v1/reviewSubmissionItems")
        for secret in ("79991234567", "private-demo-value", "user@example.org", "+1 (999) 123-4567", "test-sensitive-value"):
            self.assertNotIn(secret, str(error))
        self.assertIn("[REDACTED", str(error))

    def test_nested_errors_remain_codes_only_for_metadata_endpoints(self):
        error = ApiError(409, [{"code": "ENTITY_ERROR", "detail": "private metadata value", "meta": {"associatedErrors": {
            "/appStoreReviewDetails/review": [{"code": "ENTITY_ERROR.ATTRIBUTE.INVALID", "detail": "private demo password",
                                                "source": {"pointer": "/data/attributes/demoAccountPassword"}}]}}}],
                         "PATCH /v1/appStoreReviewDetails/review")
        self.assertEqual(error.codes, ["ENTITY_ERROR", "ENTITY_ERROR.ATTRIBUTE.INVALID"])
        self.assertIn("/data/attributes/demoAccountPassword", error.fields)
        self.assertNotIn("private", str(error))
        self.assertEqual(error.details, [])

    def test_apple_validation_output_is_bounded(self):
        error = ApiError(409, [{"code": "STATE_ERROR", "detail": "x" * 1000 + str(i)} for i in range(100)], "POST /v1/reviewSubmissionItems")
        self.assertEqual(len(error.codes), 20)
        self.assertTrue(all(len(detail) <= 500 for detail in error.details))
        self.assertLess(len(str(error)), 11000)

    def test_unauthorized_api_call_does_not_retry_forever(self):
        opener = Opener(urllib.error.HTTPError("", 401, "", {}, io.BytesIO(b"{}")))
        with self.assertRaises(ApiError):
            Client(lambda: "fake", opener).get("/v1/apps/app")
        self.assertEqual(len(opener.requests), 1)

    def test_all_submission_and_publishing_mutations_are_denied(self):
        client = Client(lambda: "fake", Opener())
        for method, path, data in [
            ("PATCH", "/v1/reviewSubmissions/draft", {"submitted": True}),
            ("POST", "/v1/appStoreVersionSubmissions", {}),
            ("POST", "/v1/appStoreVersionReleaseRequests", {}),
            ("PATCH", "/v1/appStoreVersions/version", payload("appStoreVersions", {"releaseType": "AFTER_APPROVAL"}, id="version")),
            ("PATCH", "/v1/appStoreVersions/version?foo=bar", {}),
            ("DELETE", "/v1/reviewSubmissionItems/item", {})]:
            with self.subTest(path=path), self.assertRaises(ReleaseError):
                client.request(method, path, data)

    def test_foreign_pagination_origin_is_denied(self):
        client = Client(lambda: "fake", Opener({"data": [], "links": {"next": "https://attacker.example/"}}))
        with self.assertRaises(ReleaseError):
            client.list("/v1/apps")

    def test_asset_upload_does_not_send_asc_bearer_token(self):
        opener = Opener({})
        upload_asset_operations([dict(method="PUT", url="https://storage.example/signed", offset=1, length=2, requestHeaders=[dict(name="Content-Type", value="image/png")])], b"abcd", opener=opener)
        self.assertIsNone(opener.requests[0].get_header("Authorization"))
        self.assertEqual(opener.requests[0].data, b"bc")

    def test_es256_token_is_cached_and_has_bounded_lifetime(self):
        import jwt
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives import serialization
        key = ec.generate_private_key(ec.SECP256R1())
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "test-key.p8"
            path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
            with patch.dict(os.environ, {"ASC_KEY_PATH": str(path), "ASC_KEY_ID": "TEST", "ASC_ISSUER_ID": "test-issuer"}):
                token = Token(); encoded = token()
                self.assertEqual(encoded, token())
                claims = jwt.decode(encoded, key.public_key(), algorithms=["ES256"], audience="appstoreconnect-v1")
                self.assertEqual(claims["iss"], "test-issuer")
                self.assertLessEqual(claims["exp"] - claims["iat"], 1200)

    def test_invalid_private_key_reports_configuration_without_echo(self):
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "test-key.p8"
            path.write_text("not a valid PRIVATE KEY: test-sensitive-value")
            with patch.dict(os.environ, {"ASC_KEY_PATH": str(path), "ASC_KEY_ID": "TEST", "ASC_ISSUER_ID": "test"}):
                with self.assertRaises(NeedsAction) as captured:
                    Token()()
                self.assertNotIn("test-sensitive-value", str(captured.exception))

    def test_secret_redaction(self):
        with patch.dict(os.environ, {"ASC_REVIEW_CONTACT_PHONE": "+1234567890", "MAC_INSTALLER_P12_PASSWORD": "sensitive"}):
            value = sanitized("+1234567890 sensitive eyJabc.def.ghi -----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----")
            for secret in ("+1234567890", "sensitive", "eyJabc", "\nsecret\n"):
                self.assertNotIn(secret, value)


class ConfigTests(unittest.TestCase):
    def test_metadata_and_native_screenshot_matrix(self):
        config, locales, review, _ = metadata()
        total = sum(len(screenshot_files(g, locale)) for g in config["screenshotGroups"] for locale in locales)
        self.assertEqual(total, 84)
        self.assertTrue(review["demoAccountRequired"])
        self.assertNotIn("contactPhone", review)
        self.assertNotIn("marketingUrl", locales["en-US"])

    def test_version_build_source_and_injection_rejection(self):
        self.assertEqual(identity("macos")["platform"], "MAC_OS")
        self.assertEqual(identity("ios", "123")["build"], "123")
        for value in ("0", "$(secret)", "1\n2", "1;foo"):
            with self.assertRaises(ReleaseError):
                identity("ios", value)

    def test_absent_release_notes_do_not_clear_values(self):
        self.assertIsNone(release_notes("999.0.0", "en-US"))

    def test_workflow_is_manual_only_and_serialized(self):
        workflow = yaml.load((ROOT / ".github/workflows/app-store-release.yml").read_text(), Loader=yaml.BaseLoader)
        self.assertEqual(set(workflow["on"]), {"workflow_dispatch"})
        self.assertEqual(workflow["concurrency"]["cancel-in-progress"], "false")
        self.assertEqual(workflow["jobs"]["prepare"]["strategy"]["max-parallel"], "1")
        self.assertEqual(workflow["permissions"], {"contents": "read", "actions": "read"})
        self.assertNotIn("write-all", str(workflow))
        self.assertIn("submit_for_review: false", (ROOT / "fastlane/Fastfile").read_text())

    def test_invalid_profile_types_and_identity_are_rejected(self):
        ident = identity("ios")
        profile = {"ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=10), "Platform": ["iOS"],
                   "TeamIdentifier": [ident["teamId"]], "Entitlements": {"application-identifier": ident["teamId"] + "." + ident["bundleId"], "get-task-allow": False, **expected_capabilities(ident)}}
        check_profile(profile, ident)
        for change in ({"ProvisionedDevices": ["test-device"]}, {"ProvisionsAllDevices": True}, {"Platform": ["OSX"]}, {"ExpirationDate": datetime.datetime.now() - datetime.timedelta(days=1)}):
            with self.subTest(change=change), self.assertRaises(NeedsAction):
                check_profile(profile | change, ident)

    def test_artifact_identity_and_checksum(self):
        ident = identity("ios")
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp); export = root / "Artifact"; export.mkdir()
            artifact = export / "Farport.ipa"; artifact.write_bytes(b"test artifact")
            import hashlib
            manifest = dict(identity=ident, source=provenance(), file=artifact.name, sha256=hashlib.sha256(artifact.read_bytes()).hexdigest())
            (export / "artifact.json").write_text(json.dumps(manifest))
            self.assertEqual(binary(root, ident), artifact)
            artifact.write_bytes(b"tampered")
            with self.assertRaises(ReleaseError):
                binary(root, ident)

    def test_artifact_provenance_rejects_prs_forks_and_wrong_workflows(self):
        valid = dict(repository={"full_name": "owner/repo"}, head_repository={"full_name": "owner/repo"},
                     head_sha="a" * 40, head_branch="master", event="workflow_dispatch", path=".github/workflows/app-store-release.yml", status="completed")
        validate_run(valid, "owner/repo", "master")
        for change in ({"event": "pull_request"}, {"head_branch": "feature"}, {"head_repository": {"full_name": "fork/repo"}},
                       {"path": ".github/workflows/other.yml"}, {"status": "in_progress"}):
            with self.subTest(change=change), self.assertRaises(ReleaseError):
                validate_run(valid | change, "owner/repo", "master")

    def test_summary_does_not_claim_ready_without_apple_confirmation(self):
        with tempfile.TemporaryDirectory() as temp, patch("builtins.print"):
            report = {"identity": identity("ios"), "outcome": "WAITING_FOR_APPLE", "processing": "PROCESSING", "actions": []}
            summary(report, pathlib.Path(temp))
            text = (pathlib.Path(temp) / "summary.md").read_text()
            self.assertIn("WAITING_FOR_APPLE", text)
            self.assertNotIn("manually click **Submit", text)


if __name__ == "__main__":
    unittest.main()
