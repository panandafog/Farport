import FarportCore
import FarportSSH
import XCTest

final class SSHIntegrationTests: XCTestCase {
    private func fixtureHost() throws -> SavedHost {
        guard let text = ProcessInfo.processInfo.environment["HARBOR_TEST_PORT"], let port = Int(text) else {
            throw XCTSkip("Set HARBOR_TEST_PORT to run against the isolated local SSH fixture.")
        }
        return SavedHost(profile: HostProfile(hostname: "127.0.0.1", port: port, username: "harbor"),
                         credentials: HostCredentials(password: "harbor-test"))
    }

    func testInteractiveTerminalAndWindowResize() async throws {
        let session = try await FixtureTrust.provider().terminal(for: fixtureHost())
        let received = expectation(description: "PTY receives input and resized dimensions")
        let output = TerminalOutput()
        let task = Task {
            try await session.run(size: TerminalSize(), onReady: {
                try? await session.resize(TerminalSize(columns: 120, rows: 42))
                try? await session.send(Data("echo harbor-pty-ok\nstty size\n".utf8))
            }, onOutput: { data in
                if await output.append(data) { received.fulfill() }
            })
        }
        await fulfillment(of: [received], timeout: 10)
        await session.close()
        task.cancel()
        _ = await task.result
    }

    func testIncorrectPasswordIsRejected() async throws {
        var host = try fixtureHost()
        host.credentials.password = "incorrect"
        do {
            let session = try await FixtureTrust.provider().files(for: host)
            await session.close()
            XCTFail("Authentication should fail")
        } catch { }
    }

    func testTerminalReturnsWhenServerClosesShell() async throws {
        try await assertTerminalEnds(command: "exit")
    }

    func testTerminalReturnsWhenTransportDrops() async throws {
        try await assertTerminalEnds(command: "drop")
    }

    func testTerminalReturnsWhenServerSendsEOFWithoutClosingChannel() async throws {
        try await assertTerminalEnds(command: "eof")
    }

    private func assertTerminalEnds(command: String) async throws {
        let session = try await FixtureTrust.provider().terminal(for: fixtureHost())
        let ended = expectation(description: "Remote termination finishes terminal output")
        let task = Task {
            defer { ended.fulfill() }
            try? await session.run(size: TerminalSize(), onReady: {
                try? await session.send(Data("\(command)\n".utf8))
            }, onOutput: { _ in })
        }
        await fulfillment(of: [ended], timeout: 3)
        task.cancel()
        await session.close()
        await task.value
    }

    func testPrivateKeyAuthentication() async throws {
        guard let directory = ProcessInfo.processInfo.environment["HARBOR_TEST_KEYS"] else {
            throw XCTSkip("Set HARBOR_TEST_KEYS to the fixture directory.")
        }
        for name in ["ed25519", "rsa", "ed25519-encrypted"] {
            var host = try fixtureHost()
            host.profile.authentication = .privateKey
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            host.credentials.privateKey = try String(contentsOf: url, encoding: .utf8)
            host.credentials.passphrase = name == "ed25519-encrypted" ? "harbor-passphrase" : ""
            let session = try await FixtureTrust.provider().files(for: host)
            do {
                let entries = try await session.list("/")
                XCTAssertTrue(entries.contains { $0.name == "hello.txt" })
                await session.close()
            } catch { await session.close(); throw error }
        }
    }

    func testCancelledUploadLeavesNoDestinationOrStagingFile() async throws {
        let session = try await FixtureTrust.provider().files(for: fixtureHost())
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: local) }
        try Data(repeating: 7, count: 200_000).write(to: local)
        let name = "cancel-\(UUID().uuidString)"
        let task = Task {
            try await session.upload(local, to: "/" + name) { completed, _ in
                if completed > 0 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            try await task.value
            XCTFail("Upload should cancel")
        } catch is CancellationError {
            // Expected cooperative cancellation.
        } catch {
            await session.close()
            throw error
        }
        do {
            let entries = try await session.list("/")
            XCTAssertFalse(entries.contains { $0.name.hasPrefix(name) })
            await session.close()
        } catch { await session.close(); throw error }
    }

    func testFailedAndCancelledDownloadPreservesDestination() async throws {
        let session = try await FixtureTrust.provider().files(for: fixtureHost())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("existing.bin")
        let original = Data("keep existing content".utf8)
        try original.write(to: destination)
        do {
            do {
                try await session.download("/missing-\(UUID().uuidString)", to: destination) { _, _ in }
                XCTFail("A missing remote file must fail")
            } catch { }
            XCTAssertEqual(try Data(contentsOf: destination), original)
            let task = Task {
                try await session.download("/hello.txt", to: destination) { _, _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            do {
                try await task.value
                XCTFail("Download should cancel before replacing the destination")
            } catch is CancellationError {
                // The staged download must never replace the original after cancellation.
            }
            XCTAssertEqual(try Data(contentsOf: destination), original)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["existing.bin"])
            await session.close()
        } catch {
            await session.close()
            throw error
        }
    }

    func testSFTPRoundTripAndFileOperations() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let portText = env["HARBOR_TEST_PORT"], let port = Int(portText) else {
            throw XCTSkip("Set HARBOR_TEST_PORT to run against the isolated local SSH fixture.")
        }
        let host = SavedHost(profile: HostProfile(hostname: "127.0.0.1", port: port, username: "harbor"),
                             credentials: HostCredentials(password: "harbor-test"))
        let session = try await FixtureTrust.provider().files(for: host)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }
        do {
            let root = try await session.canonicalPath(".")
            let directory = try RemotePath.appending("test-\(UUID().uuidString)", to: root)
            try await session.createDirectory(directory)
            let payload = Data((0..<180_000).map { UInt8($0 % 251) })
            let source = local.appendingPathComponent("source.bin")
            try payload.write(to: source)
            let remote = try RemotePath.appending("space name.bin", to: directory)
            try await session.upload(source, to: remote) { _, _ in }
            let entries = try await session.list(directory)
            XCTAssertEqual(entries.map(\.name), ["space name.bin"])
            XCTAssertEqual(entries.first?.size, UInt64(payload.count))
            let destination = local.appendingPathComponent("download.bin")
            try await session.download(remote, to: destination) { _, _ in }
            XCTAssertEqual(try Data(contentsOf: destination), payload)
            try Data("old content".utf8).write(to: destination)
            try await session.download(remote, to: destination) { _, _ in }
            XCTAssertEqual(try Data(contentsOf: destination), payload)
            do {
                try await session.upload(source, to: remote) { _, _ in }
                XCTFail("Existing remote file must not be overwritten")
            } catch { }
            let afterCollision = try await session.list(directory)
            XCTAssertEqual(afterCollision.count, 1)
            let renamed = try RemotePath.appending("renamed.bin", to: directory)
            try await session.rename(remote, to: renamed)
            let renamedEntries = try await session.list(directory)
            XCTAssertEqual(renamedEntries.first?.name, "renamed.bin")
            try await session.remove(try XCTUnwrap(renamedEntries.first))
            try await session.remove(
                RemoteEntry(path: directory, name: "test", kind: .directory, size: nil, modified: nil)
            )
            await session.close()
        } catch {
            await session.close()
            throw error
        }
    }
}

private actor TerminalOutput {
    var data = Data()
    var fulfilled = false
    func append(_ chunk: Data) -> Bool {
        data.append(chunk)
        guard let text = String(data: data, encoding: .utf8) else { return false }
        guard !fulfilled, text.contains("harbor-pty-ok"), text.contains("42 120") else { return false }
        fulfilled = true
        return true
    }
}
