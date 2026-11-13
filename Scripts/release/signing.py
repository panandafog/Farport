"""App Store signing in a disposable keychain, with a separately signed File Provider."""
import base64
import datetime
import fnmatch
import hashlib
import json
import os
import pathlib
import plistlib
import re
import secrets
import shutil
import subprocess
import tempfile
import zipfile

from .asc import sanitized
from .metadata import NeedsAction, ReleaseError, ROOT, identity as project_identity


def run(args, env=None, timeout=120):
    # security's password arguments must never be echoed, nor raw tool logs saved.
    try:
        result = subprocess.run(args, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout, text=True)
    except subprocess.TimeoutExpired:
        raise ReleaseError(f"{pathlib.Path(args[0]).name} timed out; rerun the affected stage.") from None
    if result.returncode:
        raise ReleaseError(f"{pathlib.Path(args[0]).name} exited {result.returncode}: " +
                           sanitized(result.stdout + "\n" + result.stderr)[-6000:])
    return result.stdout


def require(name):
    if not os.environ.get(name):
        raise NeedsAction(f"Configure GitHub Secret {name}.")
    return os.environ[name]


def required_secrets(platform, mode):
    names = ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_P8_BASE64"]
    if mode in {"full", "upload", "review"}:
        names += ["ASC_REVIEW_CONTACT_PHONE"]
    if mode == "full":
        prefix = "IOS" if platform == "ios" else "MAC_APP"
        names += [prefix + "_DISTRIBUTION_P12_BASE64", prefix + "_DISTRIBUTION_P12_PASSWORD",
                  "IOS_PROVISION_PROFILE_BASE64" if platform == "ios" else "MAC_PROVISION_PROFILE_BASE64"]
        if platform == "macos":
            names += ["MAC_INSTALLER_P12_BASE64", "MAC_INSTALLER_P12_PASSWORD", "MAC_FINDER_PROVISION_PROFILE_BASE64"]
    return names


def preflight(platforms, mode, artifact_run_id=""):
    missing = sorted({name for platform in platforms for name in required_secrets(platform, mode)
                      if not os.environ.get(name)})
    if mode == "upload" and not re.fullmatch(r"[0-9]+", artifact_run_id):
        missing += ["numeric artifact_run_id for upload mode"]
    if missing:
        raise NeedsAction("Missing release configuration (checked together, before building): " + ", ".join(missing))
    for name in {n for p in platforms for n in required_secrets(p, mode) if n.endswith("_BASE64")}:
        try:
            if not base64.b64decode(os.environ[name], validate=True):
                raise ValueError()
        except ValueError:
            raise NeedsAction(f"{name} must be nonempty, single-line base64.") from None


def validate_materials(platform):
    """Fail on wrong profiles/certificates before Xcode/Metal/Ruby preparation."""
    from cryptography.hazmat.primitives.serialization import pkcs12, Encoding
    from cryptography.x509.oid import NameOID
    ident = project_identity(platform)
    prefix = "IOS" if platform == "ios" else "MAC_APP"
    try:
        key, cert, _ = pkcs12.load_key_and_certificates(base64.b64decode(require(prefix + "_DISTRIBUTION_P12_BASE64")),
                                                      require(prefix + "_DISTRIBUTION_P12_PASSWORD").encode())
        if not key or not cert or cert.not_valid_after_utc <= datetime.datetime.now(datetime.timezone.utc):
            raise ValueError()
        subject = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
        if not subject.startswith(("Apple Distribution:", "iPhone Distribution:", "3rd Party Mac Developer Application:")):
            raise ValueError()
    except (ValueError, IndexError):
        raise NeedsAction(prefix + " distribution P12/password is invalid, expired, or not App Store signing material.") from None
    specs = [(False, "IOS_PROVISION_PROFILE_BASE64" if platform == "ios" else "MAC_PROVISION_PROFILE_BASE64")]
    if platform == "macos":
        specs.append((True, "MAC_FINDER_PROVISION_PROFILE_BASE64"))
    with tempfile.TemporaryDirectory(prefix="farport-profile-audit-") as temp:
        for extension, secret in specs:
            path = decode_secret(secret, pathlib.Path(temp) / secret)
            profile = plistlib.loads(run(["openssl", "cms", "-verify", "-noverify", "-inform", "DER", "-in", str(path)]).encode())
            check_profile(profile, ident, extension)
            if cert.public_bytes(Encoding.DER) not in profile.get("DeveloperCertificates", []):
                raise NeedsAction(secret + " does not include the imported distribution certificate.")
    if platform == "macos":
        try:
            installer_key, installer, _ = pkcs12.load_key_and_certificates(base64.b64decode(require("MAC_INSTALLER_P12_BASE64")),
                                                                          require("MAC_INSTALLER_P12_PASSWORD").encode())
            name = installer.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value if installer else ""
            if (not installer_key or not name.startswith("3rd Party Mac Developer Installer:") or
                    not name.endswith("(" + ident["teamId"] + ")") or
                    installer.not_valid_after_utc <= datetime.datetime.now(datetime.timezone.utc)):
                raise ValueError()
        except (ValueError, IndexError):
            raise NeedsAction("Mac Installer P12/password must contain a valid Mac App Store installer certificate and key.") from None
    print(platform + ": profiles, certificate matching, expiry and production capabilities validated.", flush=True)


def decode_secret(name, path):
    try:
        data = base64.b64decode(require(name), validate=True)
    except ValueError:
        raise NeedsAction(f"GitHub Secret {name} must be a single-line base64 value.") from None
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    path.chmod(0o600)
    return path


def expected_capabilities(identity, extension=False):
    team = identity["teamId"]
    values = {"keychain-access-groups": [team + ".dev.harbor.shared"]}
    if identity["platform"] == "MAC_OS":
        values["com.apple.security.application-groups"] = ["group.dev.harbor.shared." + team]
    if not extension:
        values.update({"com.apple.developer.icloud-container-identifiers": ["iCloud.com.panandafog.harbor"],
                       "com.apple.developer.icloud-services": ["CloudKit"],
                       "com.apple.developer.icloud-container-environment": "Production",
                       "com.apple.developer.aps-environment" if identity["platform"] == "MAC_OS" else "aps-environment": "production"})
    return values


def check_capabilities(entitlements, identity, extension=False, profile=False):
    failures = []
    for key, required in expected_capabilities(identity, extension).items():
        actual = entitlements.get(key)
        if profile:
            # Apple's profile allowlist may encode iCloud services as a scalar
            # wildcard, even though the signed entitlement must be an array.
            allowed = actual if isinstance(actual, list) else [actual] if isinstance(actual, str) else []
            wanted = required if isinstance(required, list) else [required]
            valid = all(any(isinstance(pattern, str) and fnmatch.fnmatchcase(value, pattern)
                            for pattern in allowed) for value in wanted)
        elif isinstance(required, list):
            valid = isinstance(actual, list) and set(actual) == set(required)
        else:
            valid = actual == required
        if not valid:
            # Only these public capability identifiers/types are reported,
            # never an entire provisioning payload or credentials.
            failures.append(key + " (expected " + repr(required) + "; allowed " + repr(actual) + ")")
    if failures:
        bundle_id = identity.get("extensionBundleId", "Finder extension") if extension else identity["bundleId"]
        raise NeedsAction(f"{'Profile' if profile else 'Signed bundle'} does not authorize " +
                          bundle_id + ": " + "; ".join(failures))
    if not profile and any(key.startswith("com.apple.security.temporary-exception.") for key in entitlements):
        raise ReleaseError("Test-only sandbox exceptions must not ship.")


def check_profile(profile, identity, extension=False):
    expiry = profile.get("ExpirationDate")
    if not expiry or expiry.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        raise NeedsAction("Provisioning profile is expired or lacks its expiry date.")
    entitlements = profile.get("Entitlements", {})
    bundle_id = identity["extensionBundleId"] if extension else identity["bundleId"]
    expected = identity["teamId"] + "." + bundle_id
    app_id = entitlements.get("application-identifier", entitlements.get("com.apple.application-identifier"))
    platform = "iOS" if identity["platform"] == "IOS" else "OSX"
    if app_id != expected or identity["teamId"] not in profile.get("TeamIdentifier", []) or platform not in profile.get("Platform", []):
        raise NeedsAction("Provisioning profile does not match this platform, team and exact Bundle ID: " + bundle_id)
    if (profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices") or
            entitlements.get("get-task-allow") or entitlements.get("com.apple.security.get-task-allow")):
        raise NeedsAction("Use an App Store distribution profile, not development, Ad Hoc, enterprise or Developer ID.")
    check_capabilities(entitlements, identity, extension, profile=True)


def setup(identity, state_dir):
    work = pathlib.Path(tempfile.mkdtemp(prefix="farport-signing-", dir=os.environ.get("RUNNER_TEMP", tempfile.gettempdir())))
    work.chmod(0o700)
    keychain = work / "release.keychain-db"
    old = re.findall(r'"([^"\n]+)"', run(["security", "list-keychains", "-d", "user"]))
    state = dict(work=str(work), keychain=str(keychain), oldKeychains=old, profilePaths=[])
    state_path = state_dir / "signing-state.json"
    def save():
        state_path.write_text(json.dumps(state)); state_path.chmod(0o600)
    save()
    password = secrets.token_urlsafe(32)
    run(["security", "create-keychain", "-p", password, str(keychain)])
    run(["security", "set-keychain-settings", "-lut", "21600", str(keychain)])
    run(["security", "unlock-keychain", "-p", password, str(keychain)])
    run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *old])
    prefix = "IOS" if identity["platform"] == "IOS" else "MAC_APP"
    p12 = decode_secret(prefix + "_DISTRIBUTION_P12_BASE64", work / "app.p12")
    run(["security", "import", str(p12), "-P", require(prefix + "_DISTRIBUTION_P12_PASSWORD"), "-k", str(keychain),
         "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"])
    if identity["platform"] == "MAC_OS":
        p12 = decode_secret("MAC_INSTALLER_P12_BASE64", work / "installer.p12")
        run(["security", "import", str(p12), "-P", require("MAC_INSTALLER_P12_PASSWORD"), "-k", str(keychain), "-T", "/usr/bin/productbuild"])
    run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-k", password, str(keychain)])
    profiles = {}
    specs = [(False, "IOS_PROVISION_PROFILE_BASE64" if identity["platform"] == "IOS" else "MAC_PROVISION_PROFILE_BASE64")]
    if identity["platform"] == "MAC_OS":
        specs.append((True, "MAC_FINDER_PROVISION_PROFILE_BASE64"))
    for extension, secret in specs:
        profile_file = decode_secret(secret, work / secret)
        profile = plistlib.loads(run(["security", "cms", "-D", "-i", str(profile_file)]).encode())
        check_profile(profile, identity, extension)
        directory = pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
        directory.mkdir(parents=True, exist_ok=True)
        installed = directory / (profile["UUID"] + (".mobileprovision" if identity["platform"] == "IOS" else ".provisionprofile"))
        if installed.exists():
            if installed.read_bytes() != profile_file.read_bytes():
                raise ReleaseError("Conflicting provisioning profile already installed.")
        else:
            # Register ownership before writing so cleanup survives later errors.
            state["profilePaths"].append(str(installed)); save()
            installed.write_bytes(profile_file.read_bytes())
        profiles["extension" if extension else "app"] = profile
    identities = re.findall(r'([0-9A-Fa-f]{40}) "([^"\n]+)"', run(["security", "find-identity", "-v", str(keychain)]))
    hashes = set.intersection(*[{hashlib.sha1(cert).hexdigest().upper() for cert in profile.get("DeveloperCertificates", [])}
                                for profile in profiles.values()])
    matches = [(sha, name) for sha, name in identities if sha.upper() in hashes and name.endswith("(" + identity["teamId"] + ")")]
    if len(matches) != 1:
        raise NeedsAction("No unique imported distribution identity matches BOTH profiles and team.")
    sha, name = matches[0]
    prefixes = ("Apple Distribution:", "iPhone Distribution:") if identity["platform"] == "IOS" else ("3rd Party Mac Developer Application:", "Apple Distribution:")
    if not name.startswith(prefixes):
        raise NeedsAction("Certificate is not an App Store distribution signing identity.")
    installer = None
    if identity["platform"] == "MAC_OS":
        matches = [(sha, name) for sha, name in identities if name.startswith("3rd Party Mac Developer Installer:") and name.endswith("(" + identity["teamId"] + ")")]
        if len(matches) != 1:
            raise NeedsAction("Import exactly one matching Mac App Store installer identity, not Developer ID Installer.")
        installer = matches[0][1]
    return dict(work=work, keychain=keychain, appIdentity=sha, installerIdentity=installer,
                profileName=profiles["app"]["UUID"], extensionProfile=profiles.get("extension", {}).get("UUID"))


def cleanup(state_dir):
    state_path = state_dir / "signing-state.json"
    if not state_path.exists():
        return
    state = json.loads(state_path.read_text())
    run(["security", "list-keychains", "-d", "user", "-s", *state["oldKeychains"]])
    if pathlib.Path(state["keychain"]).exists():
        run(["security", "delete-keychain", state["keychain"]])
    for path in state.get("profilePaths", []):
        pathlib.Path(path).unlink(missing_ok=True)
    shutil.rmtree(state["work"])
    state_path.unlink()


def verify_bundle(app, identity, extension=False):
    mac = identity["platform"] == "MAC_OS"
    info = plistlib.loads((app / ("Contents/Info.plist" if mac else "Info.plist")).read_bytes())
    bundle_id = identity["extensionBundleId"] if extension else identity["bundleId"]
    for field, value in [("CFBundleIdentifier", bundle_id), ("CFBundleShortVersionString", identity["version"]), ("CFBundleVersion", identity["build"])]:
        if str(info.get(field)) != value:
            raise ReleaseError(f"Artifact {field} does not match requested identity: {bundle_id}.")
    if info.get("CFBundleSupportedPlatforms") != (["MacOSX"] if mac else ["iPhoneOS"]):
        raise ReleaseError("Artifact SDK/platform is not the expected native App Store platform.")
    run(["codesign", "--verify", "--deep", "--strict", str(app)])
    entitlements = plistlib.loads(run(["codesign", "-d", "--entitlements", ":-", str(app)]).encode())
    if entitlements.get("get-task-allow") or entitlements.get("com.apple.security.get-task-allow"):
        raise ReleaseError("Distribution app has debugging entitlement.")
    if mac and entitlements.get("com.apple.security.app-sandbox") is not True:
        raise ReleaseError("Mac App Store app/extension lacks sandbox entitlement.")
    check_capabilities(entitlements, identity, extension)
    profile_path = app / ("Contents/embedded.provisionprofile" if mac else "embedded.mobileprovision")
    profile = plistlib.loads(run(["security", "cms", "-D", "-i", str(profile_path)]).encode())
    check_profile(profile, identity, extension)
    with tempfile.TemporaryDirectory(prefix="farport-cert-") as temp:
        prefix = str(pathlib.Path(temp) / "signer")
        run(["codesign", "-d", "--extract-certificates=" + prefix, str(app)])
        if pathlib.Path(prefix + "0").read_bytes() not in profile["DeveloperCertificates"]:
            raise ReleaseError("Signed bundle certificate is not authorized by its embedded profile.")
    print("Verified production signature/capabilities: " + bundle_id, flush=True)


def verify_app(app, identity):
    verify_bundle(app, identity)
    run(["python3", "Scripts/verify-release.py", str(app)], timeout=180)
    if identity["platform"] == "MAC_OS":
        verify_bundle(app / "Contents/PlugIns/FarportFinderExtension.appex", identity, extension=True)
        run(["xcrun", "swift", "Scripts/verify-sandbox.swift", str(app)], timeout=180)
    run(["python3", "Scripts/verify-demo-release.py", str(app)], timeout=180)


def archive_command(identity, state_dir, signing):
    destination = "generic/platform=iOS" if identity["platform"] == "IOS" else "generic/platform=macOS"
    args = ["xcodebuild", "-project", "Farport.xcodeproj", "-scheme", identity["scheme"], "-configuration", "Release",
            "-destination", destination, "-archivePath", str(state_dir / "Farport.xcarchive"),
            "-derivedDataPath", str(state_dir / "DerivedData"),
            "-onlyUsePackageVersionsFromResolvedFile", "-skipPackagePluginValidation",
            "CURRENT_PROJECT_VERSION=" + identity["build"], "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=" + identity["teamId"],
            "CODE_SIGN_IDENTITY=" + signing["appIdentity"], "FARPORT_APP_PROVISIONING_PROFILE=" + signing["profileName"],
            "OTHER_CODE_SIGN_FLAGS=--keychain " + str(signing["keychain"])]
    if signing.get("extensionProfile"):
        args += ["FARPORT_FINDER_PROVISIONING_PROFILE=" + signing["extensionProfile"]]
    return args + ["archive"]


def provenance():
    return dict(repository=os.environ.get("GITHUB_REPOSITORY", "local"), sha=os.environ.get("GITHUB_SHA", run(["git", "rev-parse", "HEAD"]).strip()),
                runId=os.environ.get("GITHUB_RUN_ID", "local"), workflow=".github/workflows/app-store-release.yml")


def build(identity, state_dir):
    signing = setup(identity, state_dir)
    archive = state_dir / "Farport.xcarchive"
    print("Archiving " + identity["scheme"] + " (Release, distribution; may take several minutes).", flush=True)
    run(archive_command(identity, state_dir, signing), timeout=3600)
    app = archive / "Products/Applications/Farport.app"
    verify_app(app, identity)
    export = state_dir / "Artifact"
    export.mkdir(parents=True, exist_ok=True)
    if identity["platform"] == "IOS":
        options = signing["work"] / "ExportOptions.plist"
        options.write_bytes(plistlib.dumps(dict(method="app-store-connect", destination="export", signingStyle="manual", teamID=identity["teamId"],
            signingCertificate=signing["appIdentity"], provisioningProfiles={identity["bundleId"]: signing["profileName"]},
            manageAppVersionAndBuildNumber=False, uploadSymbols=True)))
        run(["xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportOptionsPlist", str(options), "-exportPath", str(export)], timeout=1200)
        files = list(export.glob("*.ipa"))
        if len(files) != 1:
            raise ReleaseError("Export did not produce one ipa.")
        artifact = files[0]
        with tempfile.TemporaryDirectory(dir=signing["work"]) as temp:
            with zipfile.ZipFile(artifact) as zip:
                if any(pathlib.PurePosixPath(n).is_absolute() or ".." in pathlib.PurePosixPath(n).parts for n in zip.namelist()):
                    raise ReleaseError("Unsafe IPA path.")
            run(["ditto", "-x", "-k", str(artifact), temp])
            verify_app(pathlib.Path(temp) / "Payload/Farport.app", identity)
    else:
        artifact = export / "Farport.pkg"
        run(["productbuild", "--component", str(app), "/Applications", "--sign", signing["installerIdentity"],
             "--keychain", str(signing["keychain"]), str(artifact)], timeout=300)
        signature = run(["pkgutil", "--check-signature", str(artifact)])
        if signing["installerIdentity"] not in signature:
            raise ReleaseError("Exported PKG does not report the requested installer identity.")
        with tempfile.TemporaryDirectory(dir=signing["work"]) as temp:
            expanded = pathlib.Path(temp) / "expanded"
            run(["pkgutil", "--expand-full", str(artifact), str(expanded)], timeout=300)
            apps = list(expanded.rglob("Farport.app"))
            if len(apps) != 1:
                raise ReleaseError("PKG must contain exactly one Farport.app.")
            verify_app(apps[0], identity)
    manifest = dict(identity=identity, source=provenance(), file=artifact.name, sha256=hashlib.sha256(artifact.read_bytes()).hexdigest())
    (export / "artifact.json").write_text(json.dumps(manifest, indent=2) + "\n")
    for path in export.iterdir():
        if path.name not in {artifact.name, "artifact.json"}:
            shutil.rmtree(path) if path.is_dir() else path.unlink()
    return artifact


def binary(state_dir, identity):
    export = state_dir / "Artifact"
    if not (export / "artifact.json").exists():
        raise NeedsAction("No signed artifact. Run full, or upload with the previous artifact_run_id.")
    manifest = json.loads((export / "artifact.json").read_text())
    if manifest["identity"] != identity or pathlib.Path(manifest["file"]).name != manifest["file"]:
        raise ReleaseError("Downloaded artifact identity differs from the requested release.")
    source_path = state_dir / "artifact-source.json"
    expected = json.loads(source_path.read_text()) if source_path.exists() else provenance()
    if manifest.get("source") != expected:
        raise ReleaseError("Artifact repository/run/commit SHA differs from the verified source run.")
    artifact = export / manifest["file"]
    if hashlib.sha256(artifact.read_bytes()).hexdigest() != manifest["sha256"]:
        raise ReleaseError("Downloaded artifact checksum mismatch.")
    if artifact.suffix != (".ipa" if identity["platform"] == "IOS" else ".pkg"):
        raise ReleaseError("Incorrect App Store package format.")
    return artifact
