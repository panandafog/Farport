import FarportCore
import FarportSessions
import SwiftUI
import XCTest

@MainActor
final class MobileTerminalTests: XCTestCase {
    func testDisconnectRetainsNativeTerminalAndRejectsInput() async throws {
        let session = MobileTestSession()
        let workspace = workspace(session: session)
        let terminal = try XCTUnwrap(workspace.terminal)
        terminal.connect()
        try await waitUntil { terminal.state == .connected }
        let history = terminal.view.getTerminal().getBufferAsData()
        terminal.disconnect()
        XCTAssertEqual(terminal.state, .disconnected)
        terminal.send(Data("not-a-command".utf8))
        let received = await session.input
        XCTAssertTrue(received.isEmpty)
        XCTAssertEqual(terminal.view.getTerminal().getBufferAsData(), history)
        XCTAssertTrue(workspace.terminal === terminal)
    }

    func testBackgroundClosesStandardSSHWithoutAutomaticShellRestart() async throws {
        let session = MobileTestSession()
        let workspace = workspace(session: session)
        let terminal = try XCTUnwrap(workspace.terminal)
        terminal.connect()
        try await waitUntil { terminal.state == .connected }
        workspace.suspend(disconnectTransport: true)
        XCTAssertEqual(terminal.state, .disconnected)
        workspace.resume()
        XCTAssertEqual(terminal.state, .disconnected)
    }

    func testThemeChangeRetainsOutputAndTerminalIdentity() throws {
        let terminal = try XCTUnwrap(workspace().terminal)
        terminal.view.write(Data("\u{1b}[31mred\u{1b}[0m history".utf8))
        let screen = terminal.view.getTerminal().getBufferAsData()
        terminal.view.traitOverrides.userInterfaceStyle = .dark
        terminal.view.applySystemTheme()
        XCTAssertEqual(terminal.view.getTerminal().getBufferAsData(), screen)
        terminal.view.traitOverrides.userInterfaceStyle = .light
        terminal.view.applySystemTheme()
        XCTAssertEqual(terminal.view.getTerminal().getBufferAsData(), screen)
    }

    func testNativeScreensRenderAtPhoneAndTabletSizes() throws {
        for size in [CGSize(width: 375, height: 667), CGSize(width: 1024, height: 768)] {
            let workspace = workspace()
            let controller = UIHostingController(rootView: NavigationStack {
                MobileWorkspaceView(workspace: workspace, editHost: { _ in })
            })
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: size).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 3_000)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Terminal layout \(Int(size.width))"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    private func host() -> SavedHost {
        SavedHost(profile: HostProfile(name: "Development", hostname: "preview.invalid", username: "demo"))
    }

    private func workspace(session: MobileTestSession = MobileTestSession()) -> SessionWorkspace<MobileTerminalModel> {
        SessionWorkspace(host: host(), provider: MobileTestProvider(session: session),
                         makeTerminal: MobileTerminalModel.init)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}

private struct MobileTestProvider: ConnectionProvider {
    let session: MobileTestSession
    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession { session }
    func files(for host: SavedHost) async throws -> any RemoteFileSession { throw CancellationError() }
}

private actor MobileTestSession: TerminalSession {
    private let stream = AsyncThrowingStream<Data, Error>.makeStream()
    private(set) var input = Data()
    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        await onOutput(Data("retained-history".utf8))
        await onReady()
        for try await bytes in stream.stream { await onOutput(bytes) }
    }
    func send(_ data: Data) async throws { input.append(data) }
    func resize(_ size: TerminalSize) async throws {}
    func checkConnection(timeout: TimeInterval) async throws {}
    func close() async { stream.continuation.finish() }
}
