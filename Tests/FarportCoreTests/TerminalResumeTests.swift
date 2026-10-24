import FarportCore
import XCTest

final class TerminalResumeTests: XCTestCase {
    func testLegacyLibraryDefaultsToStandardSSHAndMigratesOnSave() throws {
        let host = SavedHost(profile: HostProfile(hostname: "localhost", username: "tester"))
        let encoded = try JSONEncoder().encode(host)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var profile = try XCTUnwrap(object["profile"] as? [String: Any])
        profile.removeValue(forKey: "terminalResumeStrategy")
        profile.removeValue(forKey: "jumpHostIDs")
        object["profile"] = profile
        let legacy: [String: Any] = ["schemaVersion": 1, "hosts": [object]]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("hosts.json")
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let repository = JSONHostRepository(url: url)
        var loaded = try XCTUnwrap(repository.load().first)
        XCTAssertEqual(loaded.profile.terminalResumeStrategy, .none)
        XCTAssertTrue(loaded.profile.jumpHostIDs.isEmpty)
        loaded.profile.terminalResumeStrategy = .tmux
        try repository.save([loaded])
        let restored = try XCTUnwrap(repository.load().first)
        XCTAssertEqual(restored.profile.terminalResumeStrategy, .tmux)
        XCTAssertEqual(restored.profile.tmuxSessionName, host.profile.tmuxSessionName)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(document["schemaVersion"] as? Int, 3)
    }

    func testSessionIdentityIgnoresDisplayNameAndSeparatesHosts() throws {
        let original = HostProfile(name: "One", hostname: "host", username: "user", terminalResumeStrategy: .tmux)
        var renamed = original
        renamed.name = "'; kill-session; #"
        XCTAssertEqual(renamed.tmuxSessionName, original.tmuxSessionName)
        XCTAssertNotEqual(HostProfile().tmuxSessionName, original.tmuxSessionName)
        XCTAssertNotNil(original.tmuxSessionName.range(of: "^harbor-[a-f0-9-]+$", options: .regularExpression))
    }
}
