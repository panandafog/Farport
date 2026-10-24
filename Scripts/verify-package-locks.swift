import Foundation

struct PackagePin: Decodable, Equatable {
    struct State: Decodable, Equatable {
        let revision: String
        let version: String?
        let branch: String?
    }
    let identity: String
    let kind: String
    let location: String
    let state: State
}

struct PackageLock: Decodable {
    let version: Int
    let pins: [PackagePin]
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

func require(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw NSError(domain: "PackageLockValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func pins(at path: String) throws -> [String: PackagePin] {
    let lock = try JSONDecoder().decode(PackageLock.self, from: Data(contentsOf: root.appendingPathComponent(path)))
    try require((2...3).contains(lock.version), "Unsupported lockfile version in \(path)")
    var pins: [String: PackagePin] = [:]
    for pin in lock.pins {
        try require(pins[pin.identity] == nil, "Duplicate package identity in \(path): \(pin.identity)")
        pins[pin.identity] = pin
    }
    return pins
}

do {
    let package = try pins(at: "Package.resolved")
    let app = try pins(at: "Farport.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    for (identity, pin) in package {
        try require(app[identity] == pin, "Shared dependency differs between lockfiles: \(identity)")
    }
    let data = try Data(contentsOf: root.appendingPathComponent("Farport.xcodeproj/project.pbxproj"))
    guard let project = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let objects = project["objects"] as? [String: [String: Any]] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    for object in objects.values where object["isa"] as? String == "XCRemoteSwiftPackageReference" {
        guard let location = object["repositoryURL"] as? String, let url = URL(string: location),
              let requirement = object["requirement"] as? [String: String] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let identity = url.deletingPathExtension().lastPathComponent.lowercased()
        try require(app[identity]?.location == location, "Xcode dependency is missing from its lockfile: \(identity)")
        if requirement["kind"] == "exactVersion" {
            try require(app[identity]?.state.version == requirement["version"],
                        "Xcode dependency version differs from the project: \(identity)")
        }
    }
    print("Both package lockfiles are consistent; Xcode-only dependencies are pinned.")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
