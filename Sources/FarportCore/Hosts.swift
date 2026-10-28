import FarportLocalization
import Foundation

public enum AuthenticationKind: String, Codable, CaseIterable, Sendable {
    case password, privateKey
}

public enum TerminalResumeStrategy: String, Codable, CaseIterable, Sendable {
    case none, tmux
}

public struct HostProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var authentication: AuthenticationKind
    public var terminalProvider: String
    public var fileProvider: String
    public var initialDirectory: String
    public var notes: String
    public var terminalResumeStrategy: TerminalResumeStrategy
    public var jumpHostIDs: [UUID]
    public var terminalTabs: SyncedTerminalTabs?

    // The host UUID is persisted, so reconnects and app restarts use the same remote session.
    public var tmuxSessionName: String { "harbor-" + id.uuidString.lowercased() }

    public init(id: UUID = UUID(), name: String = "", hostname: String = "", port: Int = 22,
                username: String = "", authentication: AuthenticationKind = .password,
                terminalProvider: String = "ssh", fileProvider: String = "sftp",
                initialDirectory: String = ".", notes: String = "",
                terminalResumeStrategy: TerminalResumeStrategy = .none, jumpHostIDs: [UUID] = [],
                terminalTabs: SyncedTerminalTabs? = nil) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authentication = authentication
        self.terminalProvider = terminalProvider
        self.fileProvider = fileProvider
        self.initialDirectory = initialDirectory
        self.notes = notes
        self.terminalResumeStrategy = terminalResumeStrategy
        self.jumpHostIDs = jumpHostIDs
        self.terminalTabs = terminalTabs
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, hostname, port, username, authentication, terminalProvider, fileProvider
        case initialDirectory, notes, terminalResumeStrategy, jumpHostIDs, terminalTabs
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        hostname = try values.decode(String.self, forKey: .hostname)
        port = try values.decode(Int.self, forKey: .port)
        username = try values.decode(String.self, forKey: .username)
        authentication = try values.decode(AuthenticationKind.self, forKey: .authentication)
        terminalProvider = try values.decode(String.self, forKey: .terminalProvider)
        fileProvider = try values.decode(String.self, forKey: .fileProvider)
        initialDirectory = try values.decode(String.self, forKey: .initialDirectory)
        notes = try values.decode(String.self, forKey: .notes)
        terminalResumeStrategy = try values.decodeIfPresent(
            TerminalResumeStrategy.self, forKey: .terminalResumeStrategy
        ) ?? .none
        jumpHostIDs = try values.decodeIfPresent([UUID].self, forKey: .jumpHostIDs) ?? []
        terminalTabs = try values.decodeIfPresent(SyncedTerminalTabs.self, forKey: .terminalTabs)
    }

    public func hasSameSettings(as other: Self) -> Bool {
        var left = self
        var right = other
        left.terminalTabs = nil
        right.terminalTabs = nil
        return left == right
    }

    public func mergingTerminalTabs(from other: Self) throws -> Self {
        var result = self
        if let incoming = other.terminalTabs {
            result.terminalTabs = try terminalTabs?.merging(incoming) ?? incoming
        }
        return result
    }

    public var displayName: String { name.isEmpty ? hostname : name }
    public var address: String { "\(username)@\(hostname):\(port)" }

    public func validate() throws {
        try terminalTabs?.validate()
        guard !hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !hostname.contains(where: { $0.isWhitespace }), !hostname.contains("://"),
              !hostname.contains("/"), !hostname.contains("\0") else {
            throw HarborError.message(L10n.text("Enter a hostname or IP address, without a URL scheme or path."))
        }
        guard (1...65535).contains(port) else {
            throw HarborError.message(L10n.text("Port must be between 1 and 65535."))
        }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !username.contains("\0") else { throw HarborError.message(L10n.text("Enter a username.")) }
    }
}

// Credentials stay in the device's Keychain; cloud synchronization accepts HostProfile only.
public struct HostCredentials: Codable, Equatable, Sendable {
    public var password: String
    public var privateKey: String
    public var passphrase: String

    public init(password: String = "", privateKey: String = "", passphrase: String = "") {
        self.password = password
        self.privateKey = privateKey
        self.passphrase = passphrase
    }
}

public struct SavedHost: Identifiable, Codable, Equatable, Sendable {
    public var profile: HostProfile
    public var credentials: HostCredentials
    public var credentialsConfigured: Bool
    public var id: UUID { profile.id }

    public init(profile: HostProfile = HostProfile(), credentials: HostCredentials = HostCredentials(),
                credentialsConfigured: Bool = true) {
        self.profile = profile
        self.credentials = credentials
        self.credentialsConfigured = credentialsConfigured
    }

    private enum CodingKeys: String, CodingKey { case profile, credentials, credentialsConfigured }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        profile = try values.decode(HostProfile.self, forKey: .profile)
        credentials = try values.decode(HostCredentials.self, forKey: .credentials)
        credentialsConfigured = try values.decodeIfPresent(Bool.self, forKey: .credentialsConfigured) ?? true
    }

    public func validate() throws {
        try profile.validate()
        guard credentialsConfigured else {
            throw HarborError.message(L10n.text("Set credentials for this host on this device before connecting."))
        }
        if profile.authentication == .privateKey && credentials.privateKey.isEmpty {
            throw HarborError.message(L10n.text("Import or paste an OpenSSH private key."))
        }
    }
}

public enum HarborError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
