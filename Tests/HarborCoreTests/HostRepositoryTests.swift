@testable import HarborCore
import XCTest

final class HostRepositoryTests: XCTestCase {
    func testSavedHostSurvivesRestartWithAllConnectionParameters() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("hosts.json")
        let original = SavedHost(profile: HostProfile(name: "Development", hostname: "::1", port: 2200,
                                                      username: "developer", authentication: .privateKey,
                                                      initialDirectory: "/srv/files", notes: "Test host"),
                                 credentials: HostCredentials(
                                    password: "test", privateKey: "key text", passphrase: "phrase"
                                 ))
        try JSONHostRepository(url: url).save([original])
        XCTAssertEqual(try JSONHostRepository(url: url).load(), [original])
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testCorruptLibraryIsNotSilentlyReplaced() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("broken json".utf8)
        try bytes.write(to: url)
        XCTAssertThrowsError(try JSONHostRepository(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testInvalidEndpointAndPortAreRejected() throws {
        XCTAssertThrowsError(try HostProfile(hostname: "sftp://host/path", username: "user").validate())
        XCTAssertThrowsError(try HostProfile(hostname: "host", port: 0, username: "user").validate())
        XCTAssertNoThrow(try HostProfile(hostname: "2001:db8::1", username: "user").validate())
    }

    func testRemoteNamesCannotEscapeDirectory() throws {
        XCTAssertThrowsError(try RemotePath.appending("../outside", to: "/home"))
        XCTAssertThrowsError(try RemotePath.appending("..", to: "/home"))
        XCTAssertEqual(try RemotePath.appending("a b.txt", to: "/"), "/a b.txt")
        XCTAssertEqual(RemotePath.parent(of: "/home/user"), "/home")
        XCTAssertEqual(RemotePath.parent(of: "/"), "/")
    }
}
