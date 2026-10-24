import CoreFoundation
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

func require(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw NSError(domain: "SandboxValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func dictionary(_ data: Data) throws -> [String: Any] {
    guard let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return value
}

func requireBoolean(_ key: String, in entitlements: [String: Any]) throws {
    guard let value = entitlements[key] as? NSNumber else {
        try require(false, "Missing Boolean entitlement: \(key)")
        return
    }
    try require(CFGetTypeID(value) == CFBooleanGetTypeID() && value.boolValue, "Expected Boolean true: \(key)")
}

func validate(_ entitlements: [String: Any], mainApp: Bool) throws {
    try requireBoolean("com.apple.security.app-sandbox", in: entitlements)
    try requireBoolean("com.apple.security.network.client", in: entitlements)
    if mainApp { try requireBoolean("com.apple.security.files.user-selected.read-write", in: entitlements) }
    try require(entitlements["com.apple.security.network.server"] == nil, "Unexpected incoming-network permission")
    try require(!entitlements.keys.contains { $0.hasPrefix("com.apple.security.temporary-exception.") },
                "Test-only/temporary sandbox exceptions must not ship")
}

func migration(_ url: URL) throws {
    let manifest = try dictionary(Data(contentsOf: url))
    try require(Set(manifest.keys) == ["Move"] &&
                manifest["Move"] as? [String] == ["${ApplicationSupport}/Harbor"],
                "Migration must preserve the complete Harbor support folder without broad filesystem access")
}

let entitlementPaths = ["App/Farport.entitlements", "App/FarportLocal.entitlements",
                        "FinderExtension/FarportFinder.entitlements"]
do {
    for path in entitlementPaths {
        let entitlements = try dictionary(Data(contentsOf: root.appendingPathComponent(path)))
        try validate(entitlements, mainApp: path.hasPrefix("App/"))
    }
    try migration(root.appendingPathComponent("App/container-migration.plist"))

    // An optional app path checks the actual signature, not just the source entitlement files.
    if let path = CommandLine.arguments.dropFirst().first {
        let app = URL(fileURLWithPath: path)
        let plugins = app.appendingPathComponent("Contents/PlugIns")
        let contents = try FileManager.default.contentsOfDirectory(atPath: plugins.path)
        try require(Set(contents) == ["FarportFinderExtension.appex"],
                    "Unexpected embedded plugins: stale extensions or test bundles must not ship")
        for (url, mainApp) in [(app, true), (plugins.appendingPathComponent("FarportFinderExtension.appex"), false)] {
            let command = Process()
            let output = Pipe()
            command.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            command.arguments = ["-d", "--entitlements", "-", "--xml", url.path]
            command.standardOutput = output
            try command.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            command.waitUntilExit()
            try require(command.terminationStatus == 0, "Could not read signed entitlements: \(url.path)")
            try validate(dictionary(data), mainApp: mainApp)
        }
        try migration(app.appendingPathComponent("Contents/Resources/container-migration.plist"))
    }
    print("App Sandbox, outbound networking, selected-file access and migration checks passed.")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
