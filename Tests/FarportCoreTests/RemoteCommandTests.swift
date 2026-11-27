import FarportCore
import Foundation
import XCTest

final class RemoteCommandTests: XCTestCase {
    func testRequestsRejectInvalidShellStringsAndUnboundedResources() throws {
        for command in ["", " \n", "pwd\0", String(repeating: "x", count: 65_537)] {
            XCTAssertThrowsError(try RemoteCommandRequest(command: command).validate())
        }
        for directory in ["/tmp\0", String(repeating: "я", count: 2_049)] {
            XCTAssertThrowsError(try RemoteCommandRequest(command: "pwd", directory: directory).validate())
        }
        for timeout in [0.0, -1, 301, .infinity, .nan] {
            XCTAssertThrowsError(try RemoteCommandRequest(command: "pwd", timeout: timeout).validate())
        }
        XCTAssertThrowsError(try RemoteCommandRequest(
            command: "cat", input: String(repeating: "x", count: 1_048_577)
        ).validate())
        try RemoteCommandRequest(command: "printf 'Привет'\nexit 7", directory: "/tmp/it's here",
                                 input: "hello\0world", timeout: 300).validate()
    }

    func testFailureResultRemainsStructuredAndJSONRoundTripsUnicodeAndNewlines() throws {
        let result = RemoteCommandResult(stdout: "Привет\nsecond line", stderr: "permission denied\n",
                                         exitCode: 17, duration: 0.25)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(try JSONDecoder().decode(RemoteCommandResult.self, from: result.jsonData()), result)
        XCTAssertTrue(result.reportText.contains("17"))
        XCTAssertTrue(result.reportText.contains(result.stdout))
        XCTAssertTrue(result.reportText.contains(result.stderr))
        XCTAssertTrue(RemoteCommandResult(stdout: "", stderr: "warning", exitCode: 0, duration: 1).succeeded)
    }
}
