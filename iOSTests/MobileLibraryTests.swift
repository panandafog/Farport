import FarportCore
import FarportSessions
import SwiftUI
import XCTest

@MainActor
final class MobileLibraryTests: XCTestCase {
    func testEmptyLibraryRendersRootNavigation() async throws {
        try await checkLibrary(hosts: [])
    }

    func testRestoredLibraryRendersRootNavigation() async throws {
        try await checkLibrary(hosts: [SavedHost(profile: HostProfile(
            name: "Development", hostname: "preview.invalid", username: "demo"
        ))])
    }

    func testCloudPushBackgroundModeIsDeclared() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
                       ["remote-notification"])
    }

    private func checkLibrary(hosts: [SavedHost]) async throws {
        var loads = 0
        var loaded: HostLibraryModel<MobileTerminalModel>?
        let root = MobileAppRoot(loadLibrary: {
            loads += 1
            return HostLibraryModel<MobileTerminalModel>(
                repository: LibraryTestRepository(hosts: hosts), workspaceRepository: LibraryTestWorkspace(),
                cloud: CloudSyncModel(unavailableReason: "Isolated test"),
                makeProvider: { _ in LibraryTestProvider() }, makeTerminal: MobileTerminalModel.init
            )
        }, didLoad: { loaded = $0 })
        let controller = UIHostingController(rootView: root)
        XCTAssertEqual(loads, 0, "Creating the root must not initialize UIKit terminals")
        let size = CGSize(width: 393, height: 852)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(500))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: size).image { context in
            controller.view.layer.render(in: context.cgContext)
        }
        // A blank light launch screen has no dark foreground pixels.
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let foreground = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] < 100 && pixels[$0 + 1] < 100 && pixels[$0 + 2] < 100 && pixels[$0 + 3] > 200
        }.count
        XCTAssertGreaterThan(foreground, 1_000, "The library must not render as a blank launch screen")
        let attachment = XCTAttachment(image: image)
        attachment.name = hosts.isEmpty ? "Empty library startup" : "Restored library startup"
        attachment.lifetime = .keepAlways
        add(attachment)
        let model = try XCTUnwrap(loaded)
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(model.hosts.count, hosts.count)
        XCTAssertEqual(model.selectedWorkspace?.terminal?.state, hosts.isEmpty ? nil : .disconnected)
    }
}

private final class LibraryTestRepository: HostRepository {
    var hosts: [SavedHost]
    init(hosts: [SavedHost]) { self.hosts = hosts }
    func load() -> [SavedHost] { hosts }
    func save(_ hosts: [SavedHost]) { self.hosts = hosts }
}

private final class LibraryTestWorkspace: WorkspaceRepository {
    func load() -> WorkspaceSnapshot { WorkspaceSnapshot() }
    func save(_ snapshot: WorkspaceSnapshot) {}
}

private struct LibraryTestProvider: ConnectionProvider {
    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession {
        throw CancellationError()
    }
    func files(for host: SavedHost) async throws -> any RemoteFileSession { throw CancellationError() }
}
