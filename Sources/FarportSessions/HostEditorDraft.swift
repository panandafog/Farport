import FarportCore
import FarportLocalization
import Foundation

/// Unsaved form values shared by macOS and iOS. Validation never writes credentials or opens a connection.
public struct HostEditorDraft: Equatable {
    public var host: SavedHost
    public var port: String
    public var emptyPasswordConfirmed: Bool

    public init(host: SavedHost, hosts: [SavedHost]) {
        self.host = host
        if !host.credentialsConfigured { self.host.credentials = HostCredentials() }
        port = String(host.profile.port)
        emptyPasswordConfirmed = hosts.contains { $0.id == host.id } && host.credentialsConfigured &&
            host.profile.authentication == .password && host.credentials.password.isEmpty
    }

    public func validatedHost(in hosts: [SavedHost]) throws -> SavedHost {
        let text = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text) else {
            throw HarborError.message(L10n.text("Enter a valid port number."))
        }
        var candidate = host
        candidate.profile.port = value
        candidate.profile.hostname = host.profile.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.profile.username = host.profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.profile.name = host.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        try candidate.profile.validate()
        try validateCredentials(candidate)
        candidate.credentialsConfigured = true
        try candidate.validate()
        try validateRoutes(candidate, in: hosts)
        return candidate
    }

    private func validateCredentials(_ candidate: SavedHost) throws {
        switch candidate.profile.authentication {
        case .password:
            guard !candidate.credentials.password.isEmpty || emptyPasswordConfirmed else {
                throw HarborError.message(L10n.text("Enter a password or enable Use an empty password."))
            }
        case .privateKey:
            guard !candidate.credentials.privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HarborError.message(L10n.text("Import or paste an OpenSSH private key."))
            }
            guard candidate.credentials.privateKey.utf8.count <= 1_048_576 else {
                throw HarborError.message(L10n.text("The private key file is too large."))
            }
        }
    }

    private func validateRoutes(_ candidate: SavedHost, in hosts: [SavedHost]) throws {
        let updated = hosts.filter { $0.id != candidate.id } + [candidate]
        for host in updated where host.id == candidate.id ||
            ConnectionRoute.depends(host, on: candidate.id, library: updated) {
            _ = try ConnectionRoute(to: host, library: updated)
        }
    }
}
