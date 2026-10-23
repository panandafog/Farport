import Foundation
import HarborCore
import XCTest

final class FinderWriteTests: XCTestCase {
    func testCreateReplaceAndMoveDirectoryPreserveAllIdentitiesAcrossRestart() async throws {
        let fixture = try FinderWriteFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader()
        let folder = try await fixture.create(reader, name: "Documents")
        let file = try await fixture.create(reader, name: "hello.txt", text: "Original", parent: folder.identifier)
        let source = try fixture.source("Updated")
        let updated = try await reader.modify(FinderModifyRequest(identifier: file.identifier,
            baseVersion: file.contentVersion, contents: source), progress: { _, _ in })
        XCTAssertFalse(updated.refetchContents)
        let saved = fixture.remote.appendingPathComponent("Documents/hello.txt")
        XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "Updated")
        let moved = try await reader.modify(FinderModifyRequest(identifier: folder.identifier,
            baseVersion: folder.contentVersion, name: "Renamed"), progress: { _, _ in })
        XCTAssertEqual(moved.item.identifier, folder.identifier)
        let restarted = try fixture.reader()
        let restored = try await restarted.item(file.identifier)
        XCTAssertEqual(restored.parentIdentifier, folder.identifier)
        XCTAssertEqual(restored.relativePath, "Renamed/hello.txt")
        XCTAssertEqual(restored.digest, updated.item.digest)
        let replacementFolder = try await fixture.create(restarted, name: "Documents")
        XCTAssertNotEqual(replacementFolder.identifier, folder.identifier)
    }

    func testConflictingEditWithSameSizeAndTimeKeepsBothVersionsAndRetryDoesNotDuplicate() async throws {
        let fixture = try FinderWriteFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader()
        let file = try await fixture.create(reader, name: "hello.txt", text: "aaaa")
        let remote = fixture.remote.appendingPathComponent("hello.txt")
        try Data("bbbb".utf8).write(to: remote)
        if let modified = file.modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: remote.path)
        }
        let request = FinderModifyRequest(identifier: file.identifier, baseVersion: file.contentVersion,
                                           contents: try fixture.source("cccc"))
        let result = try await reader.modify(request, progress: { _, _ in })
        XCTAssertTrue(result.refetchContents)
        XCTAssertEqual(try String(contentsOf: remote, encoding: .utf8), "bbbb")
        let entries = try await reader.list(FinderPath.rootIdentifier)
        let conflict = try XCTUnwrap(entries.first { $0.name.contains("Harbor conflict") })
        let conflictURL = fixture.remote.appendingPathComponent(conflict.relativePath)
        XCTAssertEqual(try String(contentsOf: conflictURL, encoding: .utf8), "cccc")
        _ = try await reader.modify(request, progress: { _, _ in })
        let repeated = try await reader.list(FinderPath.rootIdentifier)
        XCTAssertEqual(repeated.count, 2)
    }

    func testLostCreateAcknowledgementIsRecoveredWithoutUploadingTwice() async throws {
        let fixture = try FinderWriteFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader()
        let token = UUID().uuidString
        await fixture.files.failUploadReply()
        do {
            _ = try await fixture.create(reader, name: "retry.txt", text: "Saved before connection loss", token: token)
            XCTFail("Lost reply should be reported")
        } catch { }
        let restarted = try fixture.reader()
        let restored = try await fixture.create(restarted, name: "retry.txt", text: "Saved before connection loss",
                                                token: token)
        let count = await fixture.files.uploadCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(restored.name, "retry.txt")
    }

    func testLostRenameReplyPreservesDescendantIdentityAndDoesNotMoveAnythingTwice() async throws {
        let fixture = try FinderWriteFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader()
        let folder = try await fixture.create(reader, name: "folder")
        let file = try await fixture.create(reader, name: "child.txt", text: "Child", parent: folder.identifier)
        await fixture.files.failRenameReply()
        let request = FinderModifyRequest(identifier: folder.identifier,
                                           baseVersion: folder.contentVersion, name: "moved")
        do {
            _ = try await reader.modify(request, progress: { _, _ in })
            XCTFail("Lost reply should be reported")
        } catch { }
        let restarted = try fixture.reader()
        _ = try await restarted.modify(request, progress: { _, _ in })
        let child = try await restarted.item(file.identifier)
        XCTAssertEqual(child.relativePath, "moved/child.txt")
        XCTAssertEqual(child.parentIdentifier, folder.identifier)
    }

    func testDeletionIsVersionCheckedAndNonemptyFoldersArePreserved() async throws {
        let fixture = try FinderWriteFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader()
        let folder = try await fixture.create(reader, name: "folder")
        let file = try await fixture.create(reader, name: "child.txt", text: "Child", parent: folder.identifier)
        do {
            try await reader.delete(folder.identifier, baseVersion: folder.contentVersion)
            XCTFail("Nonempty folders must not be removed implicitly")
        } catch FinderWriteError.directoryNotEmpty { }
        do {
            try await reader.delete(file.identifier, baseVersion: Data("stale".utf8))
            XCTFail("Stale deletion must not succeed")
        } catch FinderWriteError.conflict { }
        try await reader.delete(file.identifier, baseVersion: file.contentVersion)
        try await reader.delete(file.identifier, baseVersion: file.contentVersion)
        try await reader.delete(folder.identifier, baseVersion: folder.contentVersion)
        let vanished = try await fixture.create(reader, name: "vanished.txt", text: "Removed elsewhere")
        try FileManager.default.removeItem(at: fixture.remote.appendingPathComponent(vanished.name))
        try await reader.delete(vanished.identifier, baseVersion: vanished.contentVersion)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.remote.path).isEmpty)
    }

    func testDefiniteServerRejectionDoesNotAdoptAnUnrelatedDirectoryOnRestart() async throws {
        let fixture = try FinderWriteFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader()
        let token = UUID().uuidString
        await fixture.files.denyNextCreation()
        do {
            _ = try await fixture.create(reader, name: "denied", token: token)
            XCTFail("Permission failure must be reported")
        } catch RemoteFileFailure.permissionDenied { }
        try FileManager.default.createDirectory(at: fixture.remote.appendingPathComponent("denied"),
                                                withIntermediateDirectories: false)
        let restarted = try fixture.reader()
        do {
            _ = try await fixture.create(restarted, name: "denied", token: token)
            XCTFail("An unrelated directory must remain a collision")
        } catch FinderWriteError.collision { }
    }

    func testLegacyConnectionCannotAcquireWriteAccessDuringMigration() throws {
        let host = SavedHost(profile: HostProfile(name: "Test", hostname: "localhost", username: "user"),
                             credentials: HostCredentials())
        let location = try FinderLocation(host: host, library: [host], rootPath: "/", access: .readWrite)
        let data = try JSONEncoder().encode(location)
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        document.removeValue(forKey: "accessMode")
        let legacyData = try JSONSerialization.data(withJSONObject: document)
        let legacy = try JSONDecoder().decode(FinderLocation.self, from: legacyData)
        XCTAssertEqual(legacy.access, .readOnly)
        XCTAssertEqual(try JSONDecoder().decode(FinderLocation.self, from: data).access, .readWrite)
    }

    func testReadOnlyAndInvalidNamesCannotMutateRemoteFiles() async throws {
        let fixture = try FinderWriteFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader(writable: false)
        do {
            _ = try await fixture.create(reader, name: "forbidden")
            XCTFail("Read-only mutation")
        } catch FinderWriteError.readOnly { }
        let writer = try fixture.reader()
        for name in ["..", "../escape", "a/b", ""] {
            do { _ = try await fixture.create(writer, name: name); XCTFail("Invalid name") } catch { }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.remote.path).isEmpty)
    }
}
