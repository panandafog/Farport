"""Read existing human-maintained metadata; never create a second text source."""
import json
import pathlib
import re
import struct

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
PLATFORMS = {"ios": "IOS", "macos": "MAC_OS"}
# Repository folders use regional identifiers; ASC uses its own locale shortcodes.
ASC_LOCALES = {"en-US": "en-US", "ru-RU": "ru"}
AGE_BOOLEAN_FIELDS = {
    "advertising", "ageAssurance", "gambling", "healthOrWellnessTopics", "lootBox",
    "messagingAndChat", "parentalControls", "socialMedia", "socialMediaAgeRestricted", "unrestrictedWebAccess", "userGeneratedContent"
}
AGE_FREQUENCY_FIELDS = {
    "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
    "horrorOrFearThemes", "matureOrSuggestiveThemes", "medicalOrTreatmentInformation",
    "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
    "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"
}


class ReleaseError(Exception):
    pass


class NeedsAction(ReleaseError):
    pass


class Waiting(ReleaseError):
    pass


def asc_locale(locale):
    """Translate only at the API boundary; keep asset/release-note paths intact."""
    try:
        return ASC_LOCALES[locale]
    except KeyError:
        raise ReleaseError(f"No App Store Connect locale mapping for {locale}.") from None


def complete_age_answers(configured, existing):
    """Supply the full initial declaration without guessing omitted answers."""
    fields = AGE_BOOLEAN_FIELDS | AGE_FREQUENCY_FIELDS
    result = {key: existing[key] for key in fields if existing.get(key) is not None}
    result.update({key: value for key, value in configured.items() if value is not None})
    missing = sorted(fields - result.keys())
    if missing:
        raise NeedsAction("Age-rating declaration needs explicit answers in AppStore/release.json or existing ASC data: " + ", ".join(missing))
    frequencies = {"NONE", "INFREQUENT_OR_MILD", "FREQUENT_OR_INTENSE", "INFREQUENT", "FREQUENT"}
    invalid = sorted(key for key in fields if
                     (key in AGE_BOOLEAN_FIELDS and type(result[key]) is not bool) or
                     (key in AGE_FREQUENCY_FIELDS and (not isinstance(result[key], str) or result[key] not in frequencies)))
    if invalid:
        raise NeedsAction("Invalid age-rating answer types/values: " + ", ".join(invalid))
    return result


def identity(platform, build_override="", root=ROOT):
    project = yaml.safe_load((root / "project.yml").read_text())
    targets = project["targets"]
    names = {"ios": ("FarportMobile", "Farport iOS"), "macos": ("Farport", "Farport")}
    target, scheme = names[platform]
    settings = project["settings"]["base"] | targets[target]["settings"]["base"]
    version = str(settings["MARKETING_VERSION"])
    project_build = str(settings["CURRENT_PROJECT_VERSION"])
    for name in ("Farport", "FarportMobile", "FarportFinderExtension"):
        other = targets[name]["settings"]["base"]
        if (str(other["MARKETING_VERSION"]), str(other["CURRENT_PROJECT_VERSION"])) != (version, project_build):
            raise ReleaseError("App and extension versions/builds must match in project.yml.")
    build = build_override or project_build
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", version) or not re.fullmatch(r"[1-9]\d{0,8}", build):
        raise ReleaseError("Invalid marketing version or build number (use a positive integer build).")
    result = dict(name="Farport", platform=PLATFORMS[platform], bundleId=settings["PRODUCT_BUNDLE_IDENTIFIER"],
                  teamId=settings["DEVELOPMENT_TEAM"], version=version, build=build, scheme=scheme)
    if platform == "macos":
        result["extensionBundleId"] = targets["FarportFinderExtension"]["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"]
    return result


def text_fields(body):
    return dict(re.findall(r"^### ([^\n]+)\n\n(?:[^`].*?\n\n)?```text\n(.*?)\n```", body, re.M | re.S))


def metadata(platform="ios", root=ROOT):
    config = json.loads((root / "AppStore/release.json").read_text())
    text = (root / config["metadataSource"]).read_text()
    common = dict(re.findall(r"^\| ([^|]+?) \| ([^|]*?) \|$", text.split("## English", 1)[0], re.M))
    localizations, sections = {}, {}
    suffix = "iOS / iPadOS" if platform == "ios" else "macOS"
    for heading, body in re.findall(r"^## ([^\n]+)\n(.*?)(?=^## |\Z)", text, re.M | re.S):
        locale = "en-US" if heading.endswith("— en-US") else "ru-RU" if heading.endswith("— ru") else None
        if not locale:
            continue
        fields = text_fields(body)
        sections[locale] = fields
        required = {"Name": "name", "Subtitle": "subtitle",
                    f"Description — {suffix}": "description", f"Keywords — {suffix}": "keywords",
                    f"Promotional Text — {suffix}": "promotionalText"}
        mapped = {name: fields.get(heading, "") for heading, name in required.items()}
        for heading, name in [("Support URL", "supportUrl"), ("Privacy Policy URL", "privacyPolicyUrl"),
                              ("Marketing URL", "marketingUrl")]:
            value = common.get(heading, "")
            if value.startswith("https://"):
                mapped[name] = value
        limits = {"name": 30, "subtitle": 30, "description": 4000, "keywords": 100, "promotionalText": 170}
        for name, limit in limits.items():
            value = mapped[name]
            size = len(value.encode()) if name == "keywords" else len(value)
            if not value or size > limit or "**Заполнить" in value:
                raise ReleaseError(f"Metadata {locale}/{suffix}/{name} missing or exceeds {limit}.")
        for required_url in ("supportUrl", "privacyPolicyUrl"):
            if not mapped.get(required_url):
                raise NeedsAction(f"Publish and fill {required_url} in the common metadata table.")
        localizations[locale] = mapped
    if set(localizations) != {"en-US", "ru-RU"}:
        raise ReleaseError("Expected English — en-US and Русский — ru metadata sections.")
    notes = sections[config["reviewLocale"]].get(f"App Review Notes — {suffix}", "")
    if not notes or len(notes.encode()) > 4000:
        raise ReleaseError("Missing/oversized platform-specific App Review Notes.")
    review = {name: common.get(heading, "") for heading, name in {
        "Contact First Name": "contactFirstName", "Contact Last Name": "contactLastName",
        "Contact Email": "contactEmail", "Username": "demoAccountName", "Password": "demoAccountPassword"}.items()}
    for key, value in review.items():
        if not value or "Заполнить" in value:
            raise NeedsAction(f"Fill {key} in App Review Information metadata.")
        review[key] = value.strip("`")
    review.update(demoAccountRequired=True, notes=notes)
    copyright = common.get("Copyright", "")
    if not copyright or "<" in copyright or "Заполнить" in copyright:
        raise NeedsAction("Fill Copyright in metadata.")
    return config, localizations, review, copyright


def release_notes(version, locale, root=ROOT):
    path = root / "AppStore/release-notes" / version / (locale + ".txt")
    if not path.exists():
        return None
    value = path.read_text().strip()
    if not value or len(value) > 4000:
        raise ReleaseError(f"Empty or oversized release notes for {locale}.")
    return value


def screenshot_files(group, locale, root=ROOT):
    folder = root / "AppStore/screenshots" / group["folder"] / locale
    files = [file for theme in ("light", "dark") for file in sorted((folder / theme).glob("*.png"))]
    if len(files) != group["count"] or not 1 <= len(files) <= 10:
        raise ReleaseError(f"Expected {group['count']} screenshots (1–10 per slot): {group['folder']}/{locale}.")
    for theme in ("light", "dark"):
        expected = [f"{i:02d}-{scene}.png" for i, scene in enumerate(group["scenes"], 1)]
        if [p.name for p in sorted((folder / theme).glob("*.png"))] != expected:
            raise ReleaseError(f"Unexpected/missing scene names: {group['folder']}/{locale}/{theme}.")
    for file in files:
        data = file.read_bytes()
        if (data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 33 or
                list(struct.unpack(">II", data[16:24])) != group["size"] or data[25] not in (0, 2)):
            raise ReleaseError(f"Invalid screenshot dimensions/opacity: {file.relative_to(root)}.")
        if b"tRNS" in png_chunk_names(data):
            raise ReleaseError(f"Screenshot has transparency: {file.name}.")
    return files


def png_chunk_names(data):
    offset, names = 8, []
    while offset + 12 <= len(data):
        size = struct.unpack(">I", data[offset:offset + 4])[0]
        names.append(data[offset + 4:offset + 8])
        offset += size + 12
    if offset != len(data) or not names or names[-1] != b"IEND":
        raise ReleaseError("Malformed PNG chunks.")
    return names
