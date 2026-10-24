import Foundation

func normalizePackageNavigator(in project: URL) throws {
    let url = project.appendingPathComponent("project.pbxproj")
    let data = try Data(contentsOf: url)
    guard let document = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let objects = document["objects"] as? [String: [String: Any]] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let references = objects.filter {
        $0.value["isa"] as? String == "PBXFileReference" &&
        $0.value["sourceTree"] as? String == "SOURCE_ROOT" &&
        $0.value["path"] as? String == "." && $0.value["lastKnownFileType"] as? String == "folder"
    }
    // XcodeGen 2.44.1 derives this cosmetic entry's name and GUID from the checkout folder.
    let stableID = "BF49EA2F8CA0319C7774C4A0"
    let expectedKeys: Set<String> = ["isa", "sourceTree", "path", "lastKnownFileType", "name"]
    guard references.count == 1, let reference = references.first, Set(reference.value.keys) == expectedKeys,
          reference.key == stableID || objects[stableID] == nil,
          var contents = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
    let entry = try NSRegularExpression(
        pattern: "(?m)^[\\t ]*\(reference.key) /\\* [^\\r\\n]*? \\*/ = \\{[^\\r\\n]*\\};$"
    )
    let range = NSRange(contents.startIndex..., in: contents)
    guard entry.numberOfMatches(in: contents, range: range) == 1 else { throw CocoaError(.fileReadCorruptFile) }
    let replacement = "\t\t\(reference.key) /* Farport */ = {isa = PBXFileReference; " +
        "lastKnownFileType = folder; name = Farport; path = .; sourceTree = SOURCE_ROOT; };"
    contents = entry.stringByReplacingMatches(in: contents, range: range, withTemplate: replacement)
    let comments = try NSRegularExpression(pattern: "\\b\(reference.key) /\\* [^\\r\\n]*? \\*/")
    contents = comments.stringByReplacingMatches(in: contents, range: NSRange(contents.startIndex..., in: contents),
                                                 withTemplate: "\(reference.key) /* Farport */")
    contents = contents.replacingOccurrences(of: reference.key, with: stableID)
    let canonicalEntry = replacement.replacingOccurrences(of: reference.key, with: stableID)
    var lines = contents.components(separatedBy: "\n")
    guard let index = lines.firstIndex(of: canonicalEntry) else { throw CocoaError(.fileReadCorruptFile) }
    lines.remove(at: index)
    guard let start = lines.firstIndex(of: "/* Begin PBXFileReference section */"),
          let end = lines.firstIndex(of: "/* End PBXFileReference section */"), start < end else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let insertion = ((start + 1)..<end).first {
        String(lines[$0].dropFirst(2).prefix(24)) > stableID
    } ?? end
    lines.insert(canonicalEntry, at: insertion)
    contents = lines.joined(separator: "\n")
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let project = root.appendingPathComponent("Farport.xcodeproj")
try normalizePackageNavigator(in: project)
let shared = project.appendingPathComponent("project.xcworkspace/xcshareddata")
let user = project.appendingPathComponent("project.xcworkspace/xcuserdata/\(NSUserName()).xcuserdatad")
for directory in [shared, user] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let settingsURL = directory.appendingPathComponent("WorkspaceSettings.xcsettings")
    var settings: [String: Any] = [:]
    if FileManager.default.fileExists(atPath: settingsURL.path) {
        let data = try Data(contentsOf: settingsURL)
        guard let existing = try PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        settings = existing
    }
    settings["BuildLocationStyle"] = "UseAppPreferences"
    settings["DerivedDataCustomLocation"] = "Build"
    settings["DerivedDataLocationStyle"] = "WorkspaceRelativePath"
    let data = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
    try data.write(to: settingsURL, options: .atomic)
}

// XcodeGen has no wait-for-launch setting; patch the generated scheme structurally after generation.
let schemeURL = project.appendingPathComponent("xcshareddata/xcschemes/Farport Attach.xcscheme")
let scheme = try XMLDocument(contentsOf: schemeURL, options: .nodePreserveAll)
guard let launch = try scheme.nodes(forXPath: "/Scheme/LaunchAction").first as? XMLElement,
      let style = launch.attribute(forName: "launchStyle") else { throw CocoaError(.fileReadCorruptFile) }
style.stringValue = "1"
try scheme.xmlData.write(to: schemeURL, options: .atomic)
