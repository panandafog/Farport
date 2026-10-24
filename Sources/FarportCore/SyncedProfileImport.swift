import FarportLocalization
import Foundation

public enum SyncedProfileImport {
    public static func apply(_ profiles: [HostProfile], to hosts: [SavedHost]) throws -> [SavedHost] {
        guard Set(profiles.map(\.id)).count == profiles.count else {
            throw HarborError.message(L10n.text("Duplicate cloud host IDs."))
        }
        return try profiles.map { profile in
            try profile.validate()
            guard var existing = hosts.first(where: { $0.id == profile.id }) else {
                return SavedHost(profile: profile, credentialsConfigured: false)
            }
            if identityChanged(existing.profile, profile) { existing.credentialsConfigured = false }
            existing.profile = profile
            return existing
        }
    }

    private static func identityChanged(_ lhs: HostProfile, _ rhs: HostProfile) -> Bool {
        lhs.hostname.lowercased() != rhs.hostname.lowercased() || lhs.port != rhs.port ||
            lhs.username != rhs.username ||
            lhs.authentication != rhs.authentication || lhs.jumpHostIDs != rhs.jumpHostIDs
    }
}
