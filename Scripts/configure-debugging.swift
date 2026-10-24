import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let project = root.appendingPathComponent("Farport.xcodeproj")
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
