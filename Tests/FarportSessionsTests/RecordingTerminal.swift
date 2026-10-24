import FarportCore
import FarportSessions
import Foundation

@MainActor
final class RecordingOutput: TerminalOutput {
    private(set) var data = Data()
    private(set) var cursorVisible = false
    func write(_ data: Data) { self.data.append(data) }
    func setCursorVisible(_ visible: Bool) { cursorVisible = visible }
    func focus() {}
}

@MainActor
final class RecordingTerminal: TerminalSessionModel {
    let screen = RecordingOutput()

    init(host: SavedHost, provider: any ConnectionProvider, policy: ConnectionRecoveryPolicy = .init(),
         sessionID: UUID? = nil, trust: ServerTrustModel? = nil) {
        super.init(host: host, provider: provider, policy: policy, sessionID: sessionID, trust: trust, output: screen)
    }
}
