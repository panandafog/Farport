import copy
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

from Scripts.release import signing
from Scripts.release.metadata import ROOT, NeedsAction, ReleaseError, identity, metadata, complete_age_answers, screenshot_files
from Scripts.release.plan import choose_build
from test_release import FakeAPI, resource
from Scripts.release.asc import Store, screenshots


class FarportReleaseTests(unittest.TestCase):
    def test_native_schemes_and_extension_identity(self):
        self.assertEqual(identity("ios")["scheme"], "Farport iOS")
        mac = identity("macos", "42")
        self.assertEqual(mac["scheme"], "Farport")
        self.assertEqual(mac["extensionBundleId"], "com.panandafog.harbor.finder")
        self.assertEqual(mac["build"], "42")

    def test_platform_texts_and_public_review_credentials(self):
        _, ios, review, _ = metadata("ios")
        _, mac, mac_review, _ = metadata("macos")
        for locale in ios:
            self.assertNotEqual(ios[locale]["description"], mac[locale]["description"])
            self.assertNotEqual(ios[locale]["keywords"], mac[locale]["keywords"])
            self.assertEqual(ios[locale]["name"], mac[locale]["name"])
        self.assertEqual((review["demoAccountName"], review["demoAccountPassword"]), ("bandit0", "bandit0"))
        self.assertIn("2220", review["notes"])
        self.assertIn("Rebex", mac_review["notes"])
        self.assertNotEqual(review["notes"], mac_review["notes"])

    def test_deterministic_both_themes_and_limit(self):
        config, locales, _, _ = metadata()
        for group in config["screenshotGroups"]:
            for locale in locales:
                files = screenshot_files(group, locale)
                self.assertEqual([p.parent.name for p in files], ["light"] * (len(files)//2) + ["dark"] * (len(files)//2))
                self.assertLessEqual(len(files), 10)

    def test_profile_extension_needs_shared_groups_but_not_cloudkit(self):
        mac = identity("macos")
        ext = signing.expected_capabilities(mac, True)
        self.assertNotIn("com.apple.developer.icloud-services", ext)
        signing.check_capabilities(ext, mac, True, profile=True)
        for missing in ext:
            bad = ext.copy();bad.pop(missing)
            with self.assertRaises(NeedsAction):
                signing.check_capabilities(bad, mac, True, profile=True)

    def test_profile_wildcard_and_array_allowlists_are_not_signed_entitlement_values(self):
        ident = identity("ios")
        capabilities = signing.expected_capabilities(ident)
        profile = capabilities | {"com.apple.developer.icloud-services": "*",
                                   "com.apple.developer.icloud-container-environment": ["Development", "Production"]}
        signing.check_capabilities(profile, ident, profile=True)
        with self.assertRaises(NeedsAction):
            signing.check_capabilities(profile, ident)
        for invalid in (None, [], ["CloudDocuments"]):
            with self.assertRaises(NeedsAction):
                signing.check_capabilities(profile | {"com.apple.developer.icloud-services": invalid}, ident, profile=True)

    def test_production_push_and_cloud_are_required(self):
        for platform in ("ios", "macos"):
            ident = identity(platform);cap = signing.expected_capabilities(ident)
            signing.check_capabilities(cap, ident, profile=True)
            push = "aps-environment" if platform == "ios" else "com.apple.developer.aps-environment"
            with self.assertRaises(NeedsAction):
                signing.check_capabilities(cap | {push: "development"}, ident, profile=True)
            with self.assertRaises(NeedsAction):
                signing.check_capabilities(cap | {"com.apple.developer.icloud-container-environment": "Development"}, ident)

    def test_archive_does_not_apply_main_profile_globally(self):
        material = dict(appIdentity="a"*40, profileName="app-profile", extensionProfile="ext-profile", keychain="/temporary/keychain")
        for platform in ("ios", "macos"):
            command = signing.archive_command(identity(platform, "88"), pathlib.Path("/build"), material)
            self.assertIn("-onlyUsePackageVersionsFromResolvedFile", command)
            self.assertIn("-skipPackagePluginValidation", command)
            self.assertNotIn("-disablePackagePluginSandbox", command)
            self.assertIn("FARPORT_FINDER_PROVISIONING_PROFILE=ext-profile", command)
            self.assertFalse(any(s.startswith("PROVISIONING_PROFILE_SPECIFIER=") for s in command))
            self.assertIn("CURRENT_PROJECT_VERSION=88", command)
            self.assertIn(identity(platform)["scheme"], command)

    def test_early_preflight_reports_all_missing_inputs(self):
        with patch.dict(os.environ, {}, clear=True), self.assertRaises(NeedsAction) as caught:
            signing.preflight(["ios", "macos"], "full")
        for name in ["IOS_PROVISION_PROFILE_BASE64", "MAC_PROVISION_PROFILE_BASE64", "MAC_FINDER_PROVISION_PROFILE_BASE64", "MAC_INSTALLER_P12_PASSWORD", "ASC_REVIEW_CONTACT_PHONE"]:
            self.assertIn(name, str(caught.exception))

    def test_status_does_not_require_signing_material(self):
        env = {name: "dGVzdA==" for name in signing.required_secrets("ios", "status")}
        with patch.dict(os.environ, env, clear=True):
            signing.preflight(["ios", "macos"], "status")

    def test_unanswered_remote_capabilities_need_owner_not_game_defaults(self):
        config, _, _, _ = metadata()
        for field in ("unrestrictedWebAccess", "messagingAndChat", "userGeneratedContent"):
            self.assertIsNone(config["ageRating"][field])
        with self.assertRaises(NeedsAction):
            complete_age_answers(config["ageRating"], {})

    def test_build_auto_avoids_both_platforms_and_explicit_retries_stay_same(self):
        self.assertEqual(choose_build("10", ["9", "10", "12"], "", "full"), "13")
        self.assertEqual(choose_build("10", ["9", "12"], "11", "full"), "11")
        self.assertEqual(choose_build("10", ["12"], "", "status"), "10")

    def test_owner_encryption_answer_is_never_invented(self):
        api = FakeAPI(); ident = identity("ios");config, _, _, _ = metadata()
        store = Store(api, ident, config, {})
        build = store.find_build(); build["attributes"]["usesNonExemptEncryption"] = None
        with self.assertRaisesRegex(NeedsAction, "SSH encryption"):
            store.verify_encryption(build)
        self.assertFalse(any(m != "GET" for m, _ in api.calls))

    def test_non_exempt_build_requires_approved_matching_declaration(self):
        api = FakeAPI();config, _, _, _ = metadata();store = Store(api, identity("ios"), config, {})
        build = store.find_build();build["attributes"]["usesNonExemptEncryption"] = True
        declaration = resource("appEncryptionDeclarations", "declaration", {"appEncryptionDeclarationState": "IN_REVIEW"})
        with patch.object(api, "get", return_value=declaration), self.assertRaises(NeedsAction):
            store.verify_encryption(build)
        declaration["attributes"]["appEncryptionDeclarationState"] = "APPROVED"
        with patch.object(api, "get", side_effect=[declaration, {"id": "app"}]):
            store.verify_encryption(build)
        with patch.object(api, "get", side_effect=[declaration, {"id": "other"}]), self.assertRaises(ReleaseError):
            store.verify_encryption(build)

    def test_identical_manual_screenshots_reused_without_upload_or_deletion(self):
        api = FakeAPI();config, locales, _, cp = metadata();store = Store(api, identity("ios"), config, {})
        version=store.ensure_version();loc=store.metadata(version,locales,cp)["en-US"];group=config["screenshotGroups"][0];files=screenshot_files(group,"en-US")
        with patch("Scripts.release.asc.upload_asset_operations"):
            screenshots(store,loc,group,files)
        for (kind,_),record in api.records.items():
            if kind=="appScreenshots":record["attributes"]["fileName"]="owner-"+record["id"]+".png"
        api.calls.clear()
        with patch("Scripts.release.asc.upload_asset_operations") as upload:
            screenshots(store,loc,group,files)
            upload.assert_not_called()
        self.assertFalse(any(m in {"POST","DELETE"} for m,_ in api.calls))

    def test_artifact_sha_is_bound_to_verified_run(self):
        ident=identity("ios")
        with tempfile.TemporaryDirectory() as temp:
            root=pathlib.Path(temp);export=root/"Artifact";export.mkdir();artifact=export/"Farport.ipa";artifact.write_bytes(b"artifact")
            import hashlib
            source={"repository":"panandafog/Farport","sha":"a"*40,"runId":"123","workflow":".github/workflows/app-store-release.yml"}
            (export/"artifact.json").write_text(json.dumps(dict(identity=ident,source=source,file=artifact.name,sha256=hashlib.sha256(artifact.read_bytes()).hexdigest())))
            (root/"artifact-source.json").write_text(json.dumps(source))
            self.assertEqual(signing.binary(root,ident),artifact)
            (root/"artifact-source.json").write_text(json.dumps(source|{"sha":"b"*40}))
            with self.assertRaises(ReleaseError):signing.binary(root,ident)


class ReleaseSafetyTests(unittest.TestCase):
    def test_app_prefixed_owner_screenshot_is_preserved(self):
        api = FakeAPI()
        config, locales, _, copyright = metadata()
        store = Store(api, identity("ios"), config, {})
        version = store.ensure_version()
        localization = store.metadata(version, locales, copyright)["en-US"]
        group = config["screenshotGroups"][0]
        aset = api.create("appScreenshotSets", {"screenshotDisplayType": group["displayType"]},
                          {"appStoreVersionLocalization": ("appStoreVersionLocalizations", localization["id"])})
        owner = api.create("appScreenshots", {"fileName": "farport-owner.png", "fileSize": 5},
                           {"appScreenshotSet": ("appScreenshotSets", aset["id"])})
        api.calls.clear()
        with self.assertRaises(NeedsAction):
            screenshots(store, localization, group, screenshot_files(group, "en-US"))
        self.assertIn(("appScreenshots", owner["id"]), api.records)
        self.assertFalse(any(method != "GET" for method, _ in api.calls))

    def test_api_cannot_set_an_encryption_exemption(self):
        from Scripts.release.asc import Client, payload
        from test_release import Opener
        opener = Opener()
        client = Client(lambda: "offline", opener)
        with self.assertRaises(ReleaseError):
            client.request("PATCH", "/v1/builds/build", payload("builds", {"usesNonExemptEncryption": False}, id="build"))
        self.assertEqual(opener.requests, [])


class PortableAPIStagesTests(unittest.TestCase):
    def test_review_and_cleanup_require_no_macos_tools(self):
        from Scripts.release import cli
        for platform in ("ios", "macos"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as temp:
                api = FakeAPI()
                ident = identity(platform)
                api.pre["attributes"]["platform"] = ident["platform"]
                with patch.object(cli, "ROOT", pathlib.Path(temp)), patch.object(cli, "Client", return_value=api):
                    with patch.object(signing, "run", side_effect=AssertionError("API-only stage invoked a native tool")):
                        with patch.dict(os.environ, {"ASC_REVIEW_CONTACT_PHONE": "+10000000000"}):
                            self.assertEqual(cli.main(["review", "--platform", platform,
                                                       "--build-number", ident["build"]]), 0)
                            self.assertEqual(cli.main(["cleanup", "--platform", platform,
                                                       "--build-number", ident["build"]]), 0)
                self.assertTrue(any(method == "POST" and path == "/v1/appStoreReviewDetails" for method, path in api.calls))
