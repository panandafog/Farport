import FarportCore
import SwiftUI

enum ConnectionRequirement {
    case localNetwork
    case serverKey(HostKeyChallenge)

    init?(_ error: Error) {
        guard let failure = error as? TerminalConnectionError else { return nil }
        if failure.requiresLocalNetworkPermission { self = .localNetwork } else if let key = failure.hostKeyChallenge {
            self = .serverKey(key)
        } else { return nil }
    }

    var title: String {
        switch self {
        case .localNetwork: "Local Network Access"
        case .serverKey(let key): key.trusted == nil ? "Verify Server Identity" : "Server Key Changed"
        }
    }

    var isWarning: Bool {
        if case .serverKey(let key) = self { return key.trusted != nil }
        return false
    }
}

struct ConnectionRequirementView: View {
    let requirement: ConnectionRequirement
    let review: () -> Void
    var waiting = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: requirement.isWarning ? "exclamationmark.shield.fill" : "lock.shield")
                .font(.title3).foregroundStyle(requirement.isWarning ? Color.red : .accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(waiting ? "Waiting for Local Network" : requirement.title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
                HStack {
                    if case .localNetwork = requirement {
                        Button("Open Settings", systemImage: "gearshape") {
                            let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
                            if let url = URL(string: link) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    if !waiting {
                        Button(actionLabel, systemImage: "arrow.right", action: review)
                            .buttonStyle(.borderedProminent).tint(requirement.isWarning ? .red : .accentColor)
                    }
                }.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background((requirement.isWarning ? Color.red : .accentColor).opacity(0.06))
    }

    private var actionLabel: String {
        if case .localNetwork = requirement { return "Retry Connection" }
        return "Review Fingerprint"
    }

    private var message: String {
        switch requirement {
        case .localNetwork:
            waiting ? "Allow Farport in the macOS prompt or in Privacy & Security > Local Network. " +
                "The connection will continue when access becomes available. You can cancel this attempt." :
                "macOS blocked the last connection attempt. Allow Farport in Privacy & Security > Local Network, " +
                "then retry. If access is already enabled but retry is still blocked, quit and reopen Farport. " +
                "If you have multiple builds, reopen the same app copy."
        case .serverKey(let key): key.trusted == nil ?
            "The server's identity needs your confirmation before sign-in." :
            "The server's key differs from the trusted key. Verify the change independently before reconnecting."
        }
    }
}
