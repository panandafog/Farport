import Citadel
import FarportCore
@testable import FarportSSH
import NIO
import NIOSSH
import XCTest

final class SSHDiagnosticTests: XCTestCase {
    func testProtocolFailuresExplainTheProblemAndKeepTechnicalCode() {
        let cases: [(NIOSSHError.ErrorType, String)] = [
            (.keyExchangeNegotiationFailure, "algorithms"), (.unsupportedVersion, "SSH 2"),
            (.channelSetupRejected, "session limit"), (.unknownPublicKey, "key or signature"),
            (.invalidMacSelected, "cryptographic configuration"),
            (.invalidEncryptedPacketLength, "failed validation"),
            (.remotePeerDoesNotSupportMessage, "requested feature"), (.protocolViolation, "server logs")
        ]
        for (type, hint) in cases {
            let error = SSHFailure.protocolFailure(type)
            XCTAssertTrue(error.localizedDescription.contains(hint), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains(type.description))
            XCTAssertFalse(error.allowsReconnect)
        }
    }

    func testSecurityFailuresStayBlockedAndTransportClosureRemainsRetryable() {
        let rejected = SSHFailure.protocolFailure(.invalidExchangeHashSignature)
        guard case .hostKeyRejected = rejected else { return XCTFail("Keep failed server verification blocked") }
        XCTAssertFalse(rejected.allowsReconnect)
        let closed = SSHFailure.protocolFailure(.tcpShutdown)
        XCTAssertTrue(closed.allowsReconnect)
        XCTAssertTrue(closed.localizedDescription.contains("closed the SSH connection"))
    }

    func testSessionRefusalIsActionableAndDoesNotLoopThroughReconnects() throws {
        let errors: [Error] = [CitadelError.channelFailure, SSHClientError.channelCreationFailed]
        for error in errors {
            let failure = try XCTUnwrap(SSHFailure.connection(error) as? TerminalConnectionError)
            XCTAssertTrue(failure.localizedDescription.contains("shell/SFTP permissions"))
            XCTAssertFalse(failure.allowsReconnect)
        }
    }

    func testTimeoutAndClosedChannelAreReadableTransportFailures() throws {
        let timeout = try XCTUnwrap(SSHFailure.connection(ChannelError.connectTimeout(.seconds(15)))
            as? TerminalConnectionError)
        XCTAssertTrue(timeout.localizedDescription.contains("timed out"))
        XCTAssertTrue(timeout.allowsReconnect)
        let closed = try XCTUnwrap(SSHFailure.connection(ChannelError.ioOnClosedChannel) as? TerminalConnectionError)
        XCTAssertTrue(closed.localizedDescription.contains("Connect again"))
        XCTAssertTrue(closed.allowsReconnect)
    }
}
