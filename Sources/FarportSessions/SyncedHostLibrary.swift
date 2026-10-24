import FarportCore

@MainActor
public protocol SyncedHostLibrary: AnyObject {
    var hosts: [SavedHost] { get }
    func canApplySyncedProfiles(_ profiles: [HostProfile]) -> Bool
    func applySyncedProfiles(_ profiles: [HostProfile]) throws
}
