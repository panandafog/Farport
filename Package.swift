// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FarportKit",
    defaultLocalization: "en",
    platforms: [.macOS("15.0"), .iOS(.v17)],
    products: [
        .library(name: "FarportDemo", targets: ["FarportDemo"]),
        .library(name: "FarportLocalization", targets: ["FarportLocalization"]),
        .library(name: "FarportSessions", targets: ["FarportSessions"]),
        .library(name: "FarportCore", targets: ["FarportCore"]),
        .library(name: "FarportSSH", targets: ["FarportSSH"]),
        .library(name: "FarportSecurity", targets: ["FarportSecurity"]),
        .library(name: "FarportCloud", targets: ["FarportCloud"]),
        .library(name: "FarportFinder", targets: ["FarportFinder"])
    ],
    dependencies: [
        .package(path: "Vendor/Citadel"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4"..<"0.4.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3")
    ],
    targets: [
        .target(name: "FarportDemo", dependencies: ["FarportCore", "FarportLocalization"]),
        .testTarget(name: "FarportDemoTests", dependencies: ["FarportDemo", "FarportCore"]),
        .target(name: "FarportLocalization", resources: [.process("Resources")]),
        .target(name: "FarportSessions", dependencies: ["FarportCore", "FarportCloud", "FarportLocalization"]),
        .target(name: "FarportCore", dependencies: ["FarportLocalization"]),
        .target(name: "FarportCloud", dependencies: ["FarportCore", "FarportLocalization"]),
        .target(name: "FarportSecurity", dependencies: ["FarportCore", "FarportLocalization"]),
        .target(name: "FarportSSH", dependencies: [
            "FarportCore", "FarportLocalization", .product(name: "Citadel", package: "Citadel"),
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "Crypto", package: "swift-crypto")
        ], resources: [.process("Resources")]),
        .target(name: "FarportFinder", dependencies: [
            "FarportCore", "FarportSSH", "FarportSecurity", "FarportLocalization"
        ]),
        .testTarget(name: "FarportSessionsTests", dependencies: ["FarportSessions", "FarportCore"]),
        .testTarget(name: "FarportLocalizationTests", dependencies: ["FarportLocalization"]),
        .testTarget(name: "FarportFinderTests", dependencies: ["FarportFinder", "FarportCore"]),
        .testTarget(name: "FarportCoreTests", dependencies: ["FarportCore"]),
        .testTarget(name: "FarportCloudTests", dependencies: ["FarportCloud", "FarportCore"]),
        .testTarget(name: "FarportSSHTests", dependencies: ["FarportSSH", "FarportCore"])
    ]
)
