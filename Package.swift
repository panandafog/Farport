// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FarportKit",
    platforms: [.macOS("15.0"), .iOS(.v17)],
    products: [
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
        .target(name: "FarportCore"),
        .target(name: "FarportCloud", dependencies: ["FarportCore"]),
        .target(name: "FarportSecurity", dependencies: ["FarportCore"]),
        .target(name: "FarportSSH", dependencies: [
            "FarportCore", .product(name: "Citadel", package: "Citadel"),
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .target(name: "FarportFinder", dependencies: ["FarportCore", "FarportSSH", "FarportSecurity"]),
        .testTarget(name: "FarportFinderTests", dependencies: ["FarportFinder", "FarportCore"]),
        .testTarget(name: "FarportCoreTests", dependencies: ["FarportCore"]),
        .testTarget(name: "FarportCloudTests", dependencies: ["FarportCloud", "FarportCore"]),
        .testTarget(name: "FarportSSHTests", dependencies: ["FarportSSH", "FarportCore"])
    ]
)
