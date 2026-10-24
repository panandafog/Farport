import FarportCore
import FarportLocalization
import SwiftUI

struct ConnectionRequirementView: View {
    let requirement: ConnectionRequirement
    let review: () -> Void
    var waiting = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: requirement.isWarning ? "exclamationmark.shield.fill" : "lock.shield")
                .font(.title3).foregroundStyle(requirement.isWarning ? Color.red : .accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(waiting ? L10n.text("Waiting for Local Network") : requirement.title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
                HStack {
                    if case .localNetwork = requirement {
                        Button(L10n.text("Open Settings"), systemImage: "gearshape") {
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
        if case .localNetwork = requirement { return L10n.text("Retry Connection") }
        return L10n.text("Review Fingerprint")
    }

    private var message: String {
        switch requirement {
        case .localNetwork:
            return waiting ? L10n.text(
                "Allow Farport in the macOS prompt or in Privacy & Security > Local Network. The " +
                "connection will continue when access becomes available. You can cancel this attempt."
            ) :
                L10n.text(
                    "macOS blocked the last connection attempt. Allow Farport in Privacy & Security > " +
                    "Local Network, then retry. If access is already enabled but retry is still blocked, " +
                    "quit and reopen Farport. If you have multiple builds, reopen the same app copy."
                )
        case .serverKey(let key): return key.trusted == nil ?
            L10n.text("The server's identity needs your confirmation before sign-in.") :
            L10n.text(
                "The server's key differs from the trusted key. Verify the change independently before " +
                "reconnecting."
            )
        }
    }
}
