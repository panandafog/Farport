import XCTest

/// FramePilot's macOS capture adapter. Not part of the ordinary test scheme or CI.
@MainActor
final class StoreScreenshots: XCTestCase {
    func testLight01Hosts() throws { try capture("hosts", appearance: "light") }
    func testLight02Terminal() throws { try capture("terminal", appearance: "light") }
    func testLight03Logs() throws { try capture("logs", appearance: "light") }
    func testLight04HostSettings() throws { try capture("host-settings", appearance: "light") }
    func testLight05Files() throws { try capture("files", appearance: "light") }
    func testDark01Hosts() throws { try capture("hosts", appearance: "dark") }
    func testDark02Terminal() throws { try capture("terminal", appearance: "dark") }
    func testDark03Logs() throws { try capture("logs", appearance: "dark") }
    func testDark04HostSettings() throws { try capture("host-settings", appearance: "dark") }
    func testDark05Files() throws { try capture("files", appearance: "dark") }

    private func capture(_ scene: String, appearance: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-scene=" + scene, "--screenshot-appearance=" + appearance]
        app.launch()
        defer { app.terminate() }
        let window = app.windows.firstMatch
        let ready = app.descendants(matching: .any).matching(identifier: "screen." + scene).firstMatch
        guard window.waitForExistence(timeout: 20), ready.waitForExistence(timeout: 20) else {
            XCTFail("Screenshot scene did not become ready: " + scene)
            throw NSError(domain: "FramePilot.SceneNotReady", code: 1)
        }
        // Wait for the explicit window dimensions without resizing another user's windows.
        let sized = NSPredicate { _, _ in
            abs(window.frame.width - 1280) < 1 && abs(window.frame.height - 800) < 1
        }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: sized, object: nil)], timeout: 10) == .completed
        else { throw NSError(domain: "FramePilot.WindowSize", code: 1) }
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "framepilot-" + scene + "-" + appearance
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
