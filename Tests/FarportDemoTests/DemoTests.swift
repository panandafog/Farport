#if DEBUG
import FarportCore
import FarportDemo
import XCTest

final class DemoTests: XCTestCase {
    func testCatalogAndRepositoriesAreStableAndIsolated() throws {
        XCTAssertTrue(DemoCatalog.isRequested(arguments: ["--demo"], environment: [:]))
        XCTAssertFalse(DemoCatalog.isRequested(arguments: ["--demo"], environment: ["HARBOR_ISOLATED_TESTS": "1"]))
        let first = DemoHostRepository(), second = DemoHostRepository()
        try DemoCatalog.hosts.forEach { try $0.validate() }
        try DemoCatalog.workspace.validate()
        XCTAssertEqual(DemoCatalog.hosts, DemoCatalog.hosts)
        XCTAssertEqual(DemoCatalog.workspace.hosts.first?.terminals.count, 3)
        first.save([])
        XCTAssertEqual(second.load().count, 8)
    }

    func testScreenshotArgumentsAreIsolatedEvenForUnknownScenes() {
        for scene in DemoScreenshotScene.allCases {
            let arguments = ["--screenshot-scene=" + scene.rawValue]
            XCTAssertEqual(DemoScreenshotScene.requested(in: arguments), scene)
            XCTAssertTrue(DemoCatalog.isRequested(arguments: arguments, environment: [:]))
            XCTAssertFalse(DemoCatalog.isRequested(arguments: arguments,
                                                  environment: ["HARBOR_ISOLATED_TESTS": "1"]))
        }
        let unknown = ["--screenshot-scene=unknown"]
        XCTAssertNil(DemoScreenshotScene.requested(in: unknown))
        XCTAssertTrue(DemoCatalog.isRequested(arguments: unknown, environment: [:]))
        XCTAssertFalse(DemoCatalog.isRequested(arguments: [], environment: [:]))
    }

    func testShellHandlesCRLFEditingAndInterruptWithoutExecutingInput() async throws {
        let session = try await DemoConnectionProvider().terminal(for: DemoCatalog.hosts[0])
        let recorder = Output()
        let ready = expectation(description: "sample shell ready")
        let task = Task {
            try await session.run(size: TerminalSize(), onReady: { ready.fulfill() },
                                  onOutput: { await recorder.append($0) })
        }
        await fulfillment(of: [ready], timeout: 3)
        let initialScreen = await recorder.text
        XCTAssertTrue(initialScreen.contains("\u{1b}[2 q"))
        XCTAssertTrue(initialScreen.contains("atlas-api"), "Ready must follow the complete initial screen")
        try await session.send(Data("pwd\r\ncd src\r\npwd\r\n".utf8))
        try await session.send(Data("echo should-not-execute\u{3}uname -a\r\nexit\r\n".utf8))
        try await task.value
        let text = await recorder.text
        XCTAssertTrue(text.contains("/home/alex/app/src\r\n"))
        XCTAssertTrue(text.contains("^C\r\n"))
        XCTAssertTrue(text.contains("Linux atlas"))
        XCTAssertFalse(text.contains("unsupported command"))
        do {
            try await session.send(Data("pwd\r".utf8))
            XCTFail("Closed sample session must reject input")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testFilesRoundTripAndHostIsolation() async throws {
        let provider = DemoConnectionProvider()
        let files = try await provider.files(for: DemoCatalog.hosts[0])
        let initial = try await files.canonicalPath(".")
        XCTAssertEqual(initial, "/home/alex/app")
        try await files.createDirectory("screenshots")
        try await files.rename("screenshots", to: "captures")
        let other = try await provider.files(for: DemoCatalog.hosts[1])
        let otherEntries = try await other.list(initial)
        XCTAssertFalse(otherEntries.contains { $0.name == "captures" })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("download")
        let bytes = Data([0, 1, 255, 128])
        try bytes.write(to: source)
        try await files.upload(source, to: "captures/image.bin", progress: { _, _ in })
        try await files.download("captures/image.bin", to: destination, progress: { _, _ in })
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        let entry = try await files.list("captures")[0]
        try await files.remove(entry)
        await files.close()
        let reopened = try await provider.files(for: DemoCatalog.hosts[0])
        let entries = try await reopened.list(initial)
        XCTAssertTrue(entries.contains { $0.name == "captures" })
    }
}

private actor Output {
    var text = ""
    func append(_ data: Data) { text += String(data: data, encoding: .utf8) ?? "" }
}
#endif
