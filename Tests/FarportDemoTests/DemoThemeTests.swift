#if DEBUG
import FarportCore
import FarportDemo
import XCTest

final class DemoThemeTests: XCTestCase {
    func testDisabledAccentKeepsTheSimulatedServersPromptColors() async throws {
        let session = try await DemoConnectionProvider().terminal(for: DemoCatalog.offlineHosts[0])
        let frames = DemoFrameRecorder()
        await session.setDecorationColors(.tinted(background: 0, accent: 0xFF8000, dark: true, useAppAccent: false))
        try await session.run(size: TerminalSize(), onReady: { await session.close() },
                              onOutput: { await frames.append($0) })
        let output = await frames.text
        XCTAssertTrue(output.contains("\u{1b}[32malex@api.farport.example"))
        XCTAssertTrue(output.contains("\u{1b}[34m/home/alex/app"))
        XCTAssertFalse(output.contains("\u{1b}[38;2;"))
    }
    func testPromptUsesResolvedAccentAcrossAppearancesWithoutRecoloringStatusesOrReplayingOutput() async throws {
        for dark in [false, true] {
            let host = DemoCatalog.offlineHosts[0]
            let session = try await DemoConnectionProvider().terminal(for: host)
            let frames = DemoFrameRecorder()
            await session.setDecorationColors(.tinted(background: dark ? 0x1E1E1E : 0xFFFFFF,
                                                       accent: 0xCC5500, dark: dark))
            let ready = expectation(description: "themed sample ready")
            let task = Task {
                try await session.run(size: TerminalSize(), onReady: { ready.fulfill() },
                                      onOutput: { await frames.append($0) })
            }
            await fulfillment(of: [ready], timeout: 3)
            let initial = await frames.text
            XCTAssertTrue(initial.contains("\u{1b}[38;2;204;85;0mFarport sample environment"))
            XCTAssertTrue(initial.contains("\u{1b}[38;2;204;85;0malex@api.farport.example"))
            XCTAssertTrue(initial.contains("\u{1b}[32mUp 12 days"), "Semantic statuses must stay green")
            XCTAssertFalse(initial.contains("\u{1b}[34m"))
            await session.setDecorationColors(.tinted(background: 0x1E1E1E, accent: 0xAABBCC, dark: true))
            let afterTheme = await frames.text
            XCTAssertEqual(afterTheme, initial, "Theme metadata must not replay or rewrite terminal output")
            try await session.send(Data("ls\r".utf8))
            await session.close()
            try await task.value
            let output = await frames.text
            XCTAssertTrue(output.contains("\u{1b}[38;2;170;187;204msrc/"))
            XCTAssertTrue(output.contains("\u{1b}[38;2;170;187;204malex@api.farport.example"))
            XCTAssertFalse(output.contains("\u{1b}[34m"))
        }
    }
}

private actor DemoFrameRecorder {
    var text = ""
    func append(_ data: Data) { text += String(data: data, encoding: .utf8) ?? "" }
}
#endif
