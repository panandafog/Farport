import FarportCore
import FarportSessions
import XCTest

final class HostEditorDraftTests: XCTestCase {
    func testRequiredFieldsAndInvalidPortsBlockSavingUntilCorrected() throws {
        var draft = HostEditorDraft(host: SavedHost(), hosts: [])
        XCTAssertThrowsError(try draft.validatedHost(in: []))
        draft.host.profile.hostname = "server.example"
        XCTAssertThrowsError(try draft.validatedHost(in: []))
        draft.host.profile.username = "developer"
        draft.host.credentials.password = "secret"
        for invalid in ["", "ssh", "22.5", "0", "65536", "-1", "999999999999999999999"] {
            draft.port = invalid
            XCTAssertThrowsError(try draft.validatedHost(in: []), invalid)
        }
        draft.port = "22"
        XCTAssertNoThrow(try draft.validatedHost(in: []))
        for invalid in ["ssh://server", "server/path", "server name", "\0"] {
            draft.host.profile.hostname = invalid
            XCTAssertThrowsError(try draft.validatedHost(in: []), invalid)
        }
        draft.host.profile.hostname = "server.example"
        XCTAssertNoThrow(try draft.validatedHost(in: []))
    }

    func testValidationNormalizesProfileWithoutMutatingDraftOrSecrets() throws {
        let host = SavedHost(profile: HostProfile(name: "  Work \n", hostname: " server \n", username: " user "),
                             credentials: HostCredentials(password: " password "))
        var draft = HostEditorDraft(host: host, hosts: [])
        draft.port = " 2222 "
        let candidate = try draft.validatedHost(in: [])
        XCTAssertEqual(candidate.profile.name, "Work")
        XCTAssertEqual(candidate.profile.hostname, "server")
        XCTAssertEqual(candidate.profile.username, "user")
        XCTAssertEqual(candidate.profile.port, 2222)
        XCTAssertEqual(candidate.credentials.password, " password ")
        XCTAssertEqual(draft.host, host)
    }

    func testEmptyPasswordRequiresExplicitConsentAndExistingConsentIsPreserved() throws {
        let host = SavedHost(profile: HostProfile(hostname: "server", username: "user"))
        var fresh = HostEditorDraft(host: host, hosts: [])
        XCTAssertThrowsError(try fresh.validatedHost(in: []))
        fresh.emptyPasswordConfirmed = true
        XCTAssertTrue(try fresh.validatedHost(in: []).credentialsConfigured)
        let existing = HostEditorDraft(host: host, hosts: [host])
        XCTAssertNoThrow(try existing.validatedHost(in: [host]))
    }

    func testImportedHostDoesNotAccidentallyConfirmEmptyOrStaleCredentials() throws {
        let host = SavedHost(profile: HostProfile(hostname: "server", username: "user"),
                             credentials: HostCredentials(password: "stale"), credentialsConfigured: false)
        var draft = HostEditorDraft(host: host, hosts: [host])
        XCTAssertEqual(draft.host.credentials, HostCredentials())
        XCTAssertFalse(draft.emptyPasswordConfirmed)
        XCTAssertThrowsError(try draft.validatedHost(in: [host]))
        draft.host.credentials.password = "local-password"
        XCTAssertTrue(try draft.validatedHost(in: [host]).credentialsConfigured)
        XCTAssertFalse(host.credentialsConfigured)
    }

    func testMissingJumpHostAndCycleBlockSaving() throws {
        let host = SavedHost(profile: HostProfile(hostname: "server", username: "user"),
                             credentials: HostCredentials(password: "secret"))
        var draft = HostEditorDraft(host: host, hosts: [host])
        draft.host.profile.jumpHostIDs = [UUID()]
        XCTAssertThrowsError(try draft.validatedHost(in: [host]))
        let gateway = SavedHost(profile: HostProfile(hostname: "jump", username: "user", jumpHostIDs: [host.id]))
        draft.host.profile.jumpHostIDs = [gateway.id]
        XCTAssertThrowsError(try draft.validatedHost(in: [host, gateway]))
        draft.host.profile.jumpHostIDs = []
        XCTAssertNoThrow(try draft.validatedHost(in: [host, gateway]))
    }

    func testEditingGatewayAlsoValidatesDependentRouteDepth() throws {
        var chain: [SavedHost] = []
        for index in 0..<8 {
            let host = SavedHost(profile: HostProfile(hostname: "host-\(index)", username: "user",
                                                     jumpHostIDs: chain.last.map { [$0.id] } ?? []))
            chain.append(host)
        }
        let extra = SavedHost(profile: HostProfile(hostname: "extra", username: "user"))
        var draft = HostEditorDraft(host: try XCTUnwrap(chain.first), hosts: chain)
        draft.host.profile.jumpHostIDs = [extra.id]
        XCTAssertThrowsError(try draft.validatedHost(in: chain + [extra]))
        draft.host.profile.jumpHostIDs = []
        XCTAssertNoThrow(try draft.validatedHost(in: chain))
    }

    func testEmptyOrOversizedPrivateKeyIsInvalid() throws {
        var draft = HostEditorDraft(host: SavedHost(profile: HostProfile(
            hostname: "server", username: "user", authentication: .privateKey
        )), hosts: [])
        for key in ["", " \n ", String(repeating: "a", count: 1_048_577)] {
            draft.host.credentials.privateKey = key
            XCTAssertThrowsError(try draft.validatedHost(in: []))
        }
    }
}
