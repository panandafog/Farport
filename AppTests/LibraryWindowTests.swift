import AppKit
@testable import Harbor
import HarborCloud
import HarborCore
import SwiftUI
import XCTest

@MainActor
final class LibraryWindowTests: XCTestCase {
    func testAttachKeepsTheWholeWindowAfterTrustAndCloudUpdates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = SavedHost(profile: HostProfile(name: "Window test", hostname: "window.invalid",
                                                  username: "test", terminalResumeStrategy: .tmux))
        let repository = JSONHostRepository(url: root.appendingPathComponent("hosts.json"))
        try repository.save([host])
        let trust = ServerTrustModel(secrets: TestSecretStore())
        let updates = AsyncStream<HostSyncSnapshot>.makeStream()
        defer { updates.continuation.finish() }
        let cloud = CloudSyncModel(service: WindowSyncService(), updates: updates.stream)
        let provider = WindowConnectionProvider(verifier: trust.verifier)
        let library = LibraryModel(repository: repository, workspaceRepository: JSONWorkspaceRepository(
            url: root.appendingPathComponent("workspace.json")), provider: provider, trust: trust, cloud: cloud)
        defer { library.closeAll() }
        let terminal = try XCTUnwrap(library.selectedWorkspace?.terminal)
        let window = makeWindow(library)
        defer { window.close() }
        try await wait { terminal.view.window === window }
        try verifyLayout(terminal, in: window, name: "Before Attach")
        terminal.connect()
        try await wait { terminal.state == .waitingForAccess }
        try await Task.sleep(for: .milliseconds(150))
        try verifyLayout(terminal, in: window, name: "Waiting for Local Network")
        await provider.resolveAccess(false)
        try await wait { terminal.requirement?.title == "Local Network Access" }
        try await Task.sleep(for: .milliseconds(150))
        try verifyLayout(terminal, in: window, name: "Local Network requirement")
        terminal.reviewRequirement()
        try await wait { trust.challenge != nil && !window.sheets.isEmpty }
        trust.trust(try XCTUnwrap(trust.challenge), continueConnection: true)
        try await wait { terminal.state == .connected && window.sheets.isEmpty }
        updates.continuation.yield(HostSyncSnapshot(enabled: true, initialized: true,
                                                  profiles: [host.profile], baseline: [host.profile]))
        try await wait { cloud.snapshot.initialized }
        try verifyLayout(terminal, in: window, name: "Attached after trust")
        terminal.disconnect()
        terminal.connect()
        try await wait { terminal.state == .connected }
        window.setContentSize(NSSize(width: 860, height: 560))
        try await Task.sleep(for: .milliseconds(100))
        try verifyLayout(terminal, in: window, name: "Reattached compact window")
        let workspace = try XCTUnwrap(library.selectedWorkspace)
        workspace.mode = .files
        try await wait { terminal.view.window == nil }
        workspace.mode = .terminal
        try await wait { terminal.view.window === window }
        try verifyLayout(terminal, in: window, name: "Returned to terminal")
    }

    private func makeWindow(_ library: LibraryModel) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: LibraryView(model: library).frame(minWidth: 860, minHeight: 560))
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func verifyLayout(_ terminal: TerminalModel, in window: NSWindow, name: String) throws {
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        XCTAssertTrue(terminal.view.window === window, name)
        XCTAssertGreaterThan(terminal.view.visibleRect.width, 300, name)
        XCTAssertGreaterThan(terminal.view.visibleRect.height, 200, name)
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let attachment = XCTAttachment(image: NSImage(cgImage: image, size: content.bounds.size))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        var sidebarInk = 0
        for row in stride(from: 0, to: bitmap.pixelsHigh / 2, by: 3) {
            for column in stride(from: 0, to: bitmap.pixelsWide / 5, by: 3) {
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
                if max(color.redComponent, color.greenComponent, color.blueComponent) < 0.6 { sidebarInk += 1 }
            }
        }
        XCTAssertGreaterThan(sidebarInk, 30, "\(name): sidebar must still render, not just exist in accessibility")
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Window did not finish its transition")
    }
}

private actor WindowConnectionProvider: ConnectionProvider {
    let verifier: HostKeyVerifier
    private var attempts = 0
    private let access = AsyncStream<Bool>.makeStream()

    init(verifier: @escaping HostKeyVerifier) { self.verifier = verifier }

    func resolveAccess(_ available: Bool) { access.continuation.yield(available); access.continuation.finish() }
    func waitForAccess(for host: SavedHost) async -> Bool {
        for await available in access.stream { return available }
        return false
    }

    func terminal(for host: SavedHost, sessionID: UUID) throws -> any TerminalSession {
        attempts += 1
        if attempts == 1 { throw TerminalConnectionError.localNetworkPermission }
        do {
            try verifier(ServerEndpoint(host.profile), ServerHostKey(algorithm: "ssh-ed25519",
                                                                    wireData: Data("window-test-key".utf8)))
        } catch let challenge as HostKeyChallenge { throw TerminalConnectionError.serverTrust(challenge) }
        return WindowTerminal()
    }

    func files(for host: SavedHost) throws -> any RemoteFileSession { throw HarborError.message("Unused") }
}

private actor WindowTerminal: TerminalSession {
    private let output = AsyncStream<Data>.makeStream()

    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        await onReady()
        await onOutput(Data(("\u{1b}]0;" + String(repeating: "long-title-", count: 200) + "\u{7}" +
                             "\r\n\u{1b}[32mAttached tmux session\u{1b}[0m\r\n").utf8))
        for await data in output.stream { await onOutput(data) }
    }

    func send(_ data: Data) {}
    func resize(_ size: TerminalSize) {}
    func checkConnection(timeout: TimeInterval) {}
    func close() { output.continuation.finish() }
}

private actor WindowSyncService: HostSyncService {
    func resume(profiles: [HostProfile]) {}
    func enable(profiles: [HostProfile]) {}
    func disable() {}
    func refresh(profiles: [HostProfile]) {}
    func localChanged(profiles: [HostProfile]) {}
    func applied(profiles: [HostProfile]) {}
    func dismissConflict(_ id: String) {}
}
