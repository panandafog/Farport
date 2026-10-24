import FarportCore
import FarportLocalization
import Foundation

public enum ConnectionRequirement {
    case localNetwork
    case serverKey(HostKeyChallenge)

    public init?(_ error: Error) {
        guard let failure = error as? TerminalConnectionError else { return nil }
        if failure.requiresLocalNetworkPermission { self = .localNetwork } else if let key = failure.hostKeyChallenge {
            self = .serverKey(key)
        } else { return nil }
    }

    public var title: String {
        switch self {
        case .localNetwork: return L10n.text("Local Network Access")
        case .serverKey(let key):
            return key.trusted == nil ? L10n.text("Verify Server Identity") : L10n.text("Server Key Changed")
        }
    }

    public var isWarning: Bool {
        if case .serverKey(let key) = self { return key.trusted != nil }
        return false
    }
}
