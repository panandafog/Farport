import FarportCore
import FarportSessions
import XCTest

@MainActor
final class FilesModelTests: XCTestCase {
    func testTransportFailureDisconnectsButKeepsTheListing() async throws {
        let session = FilesTestSession()
        let model = FilesModel(host: SavedHost(), provider: FilesTestProvider(session: session))
        model.connect()
        try await wait { model.connected }
        let previous = model.entries
        await session.failListing(TerminalConnectionError.transport("test offline"))
        model.refresh()
        try await wait { !model.busy }
        XCTAssertFalse(model.connected)
        XCTAssertEqual(model.entries.map(\.path), previous.map(\.path))
        XCTAssertTrue(model.error?.contains("test offline") == true)
        try await wait { await session.closed }
    }

    func testPermissionFailureDoesNotDiscardAWorkingConnection() async throws {
        let session = FilesTestSession()
        let model = FilesModel(host: SavedHost(), provider: FilesTestProvider(session: session))
        defer { model.disconnect() }
        model.connect()
        try await wait { model.connected }
        await session.failListing(RemoteFileFailure.permissionDenied)
        model.navigate("/private")
        try await wait { !model.busy }
        XCTAssertTrue(model.connected)
        XCTAssertEqual(model.path, "/")
        XCTAssertNotNil(model.error)
    }

    func testLateProgressCannotUpdateTheNextTransfer() async throws {
        let session = FilesTestSession()
        let model = FilesModel(host: SavedHost(), provider: FilesTestProvider(session: session))
        defer { model.disconnect() }
        model.connect()
        try await wait { model.connected }
        let entry = try XCTUnwrap(model.entries.first)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        model.download(entry, to: destination)
        try await wait { !model.busy }
        await session.holdNextDownload()
        model.download(entry, to: destination)
        try await wait { await session.downloadCount == 2 }
        XCTAssertEqual(model.transferred, 0)
        await session.sendProgress(99, callback: 0)
        XCTAssertNil(model.progress)
        XCTAssertEqual(model.transferred, 0)
        await session.sendProgress(25, callback: 1)
        XCTAssertEqual(model.progress, 0.25)
        await session.finishDownload()
        try await wait { !model.busy }
        await session.sendProgress(90, callback: 1)
        XCTAssertNil(model.progress)
        XCTAssertEqual(model.transferred, 25)
    }

    func testLateListingCannotOverwriteAReconfiguredHost() async throws {
        let first = FilesTestSession()
        let model = FilesModel(host: SavedHost(), provider: FilesTestProvider(session: first))
        model.connect()
        try await wait { model.connected }
        await first.holdNextListing()
        model.navigate("/stale")
        try await wait { await first.listingIsHeld }
        let second = FilesTestSession()
        model.reconfigure(host: SavedHost(), provider: FilesTestProvider(session: second))
        defer { model.disconnect() }
        model.connect()
        try await wait { model.connected }
        await first.finishListing()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.path, "/")
        XCTAssertEqual(model.entries.first?.path, "/test")
    }

    private func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await condition()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let succeeded = await condition()
        XCTAssertTrue(succeeded, "Timed out waiting for file state")
    }
}

private struct FilesTestProvider: ConnectionProvider {
    let session: FilesTestSession
    func files(for host: SavedHost) async throws -> any RemoteFileSession { session }
    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession {
        throw HarborError.message("Unused test terminal")
    }
}

private actor FilesTestSession: RemoteFileSession {
    private var listingFailure: Error?
    private var callbacks: [TransferProgress] = []
    private var downloadGate: CheckedContinuation<Void, Never>?
    private var listingGate: CheckedContinuation<Void, Never>?
    private var holdDownload = false
    private var holdListing = false
    private(set) var closed = false
    var downloadCount: Int { callbacks.count }
    var listingIsHeld: Bool { listingGate != nil }

    func failListing(_ error: Error) { listingFailure = error }
    func holdNextDownload() { holdDownload = true }
    func holdNextListing() { holdListing = true }
    func finishDownload() { downloadGate?.resume(); downloadGate = nil }
    func finishListing() { listingGate?.resume(); listingGate = nil }
    func sendProgress(_ completed: UInt64, callback: Int) async { await callbacks[callback](completed, 100) }
    func canonicalPath(_ path: String) -> String { path == "." ? "/" : path }
    func list(_ path: String) async throws -> [RemoteEntry] {
        if let listingFailure { throw listingFailure }
        if holdListing { await withCheckedContinuation { listingGate = $0 } }
        return [RemoteEntry(path: try RemotePath.appending("test", to: path), name: "test", kind: .file,
                            size: nil, modified: nil)]
    }
    func download(_ path: String, to destination: URL, progress: @escaping TransferProgress) async throws {
        callbacks.append(progress)
        if holdDownload { await withCheckedContinuation { downloadGate = $0 } }
    }
    func upload(_ source: URL, to path: String, progress: @escaping TransferProgress) {}
    func createDirectory(_ path: String) {}
    func rename(_ path: String, to destination: String) {}
    func remove(_ entry: RemoteEntry) {}
    func close() { closed = true }
}
