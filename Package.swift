// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HarborKit",
    platforms: [.macOS("15.0"), .iOS(.v17)],
    products: [
        .library(name: "HarborCore", targets: ["HarborCore"]),
        .library(name: "HarborSSH", targets: ["HarborSSH"]),
        .library(name: "HarborSecurity", targets: ["HarborSecurity"]),
        .library(name: "HarborCloud", targets: ["HarborCloud"]),
        .library(name: "HarborFinder", targets: ["HarborFinder"])
    ],
    dependencies: [
        .package(path: "Vendor/Citadel"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4"..<"0.4.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3")
    ],
    targets: [
        .target(name: "HarborCore"),
        .target(name: "HarborCloud", dependencies: ["HarborCore"]),
        .target(name: "HarborSecurity", dependencies: ["HarborCore"]),
        .target(name: "HarborSSH", dependencies: [
            "HarborCore", .product(name: "Citadel", package: "Citadel"),
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .target(name: "HarborFinder", dependencies: ["HarborCore", "HarborSSH", "HarborSecurity"]),
        .testTarget(name: "HarborFinderTests", dependencies: ["HarborFinder", "HarborCore"]),
        .testTarget(name: "HarborCoreTests", dependencies: ["HarborCore"]),
        .testTarget(name: "HarborCloudTests", dependencies: ["HarborCloud", "HarborCore"]),
        .testTarget(name: "HarborSSHTests", dependencies: ["HarborSSH", "HarborCore"])
    ]
)
