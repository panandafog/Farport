import FarportCloud
import FarportCore
import SwiftUI

@MainActor
final class CloudSyncModel: ObservableObject {
    @Published private(set) var snapshot = HostSyncSnapshot()
    @Published private(set) var busy = false
    @Published private(set) var pendingChanges = false
    @Published var showingSettings = false
    @Published var error: String?
    private var service: (any HostSyncService)?
    private var updates: Task<Void, Never>?
    private weak var library: LibraryModel?
    private var requestedProfiles: [HostProfile] = []
    private var journalTask: Task<Void, Never>?
    private var registerForPush: () -> Void = {}
    var available: Bool { service != nil }

    init(url: URL, containerIdentifier: String) {
        guard containerIdentifier.hasPrefix("iCloud.") else {
            error = "iCloud is not enabled in this local development build."
            return
        }
        let (stream, continuation) = AsyncStream<HostSyncSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        do {
            service = try CloudHostSync(url: url, containerIdentifier: containerIdentifier) { continuation.yield($0) }
            registerForPush = { NSApplication.shared.registerForRemoteNotifications() }
            observe(stream)
        } catch { self.error = "Cannot load iCloud sync state. The file was kept. " + error.localizedDescription }
    }

    init(service: any HostSyncService, updates: AsyncStream<HostSyncSnapshot>) {
        self.service = service
        observe(updates)
    }

    private func observe(_ stream: AsyncStream<HostSyncSnapshot>) {
        updates = Task { [weak self] in
            for await value in stream {
                guard !Task.isCancelled else { break }
                self?.receive(value)
            }
        }
    }

    func attach(_ library: LibraryModel) {
        self.library = library
        guard let service else { return }
        let profiles = library.hosts.map(\.profile)
        requestedProfiles = profiles
        Task { await service.resume(profiles: profiles) }
    }

    private func receive(_ value: HostSyncSnapshot) {
        if value.enabled && !snapshot.enabled { registerForPush() }
        snapshot = value
        reconsiderChanges()
    }

    func reconsiderChanges() {
        guard snapshot.enabled, snapshot.initialized, let library else { pendingChanges = false; return }
        guard sameProfiles(snapshot.baseline, requestedProfiles) else { pendingChanges = false; return }
        pendingChanges = !sameProfiles(library.hosts.map(\.profile), snapshot.profiles)
        if pendingChanges, library.canApplySyncedProfiles(snapshot.profiles) { applyChanges() }
    }

    func applyChanges() {
        guard let library, let service, snapshot.enabled, snapshot.initialized else { return }
        guard sameProfiles(snapshot.baseline, requestedProfiles) else {
            error = "Finishing local profile changes. Try applying the update again."
            return
        }
        do {
            try library.applySyncedProfiles(snapshot.profiles)
            pendingChanges = false
            let profiles = library.hosts.map(\.profile)
            requestedProfiles = profiles
            journal { try await service.applied(profiles: profiles) }
        } catch { self.error = error.localizedDescription }
    }

    func localChanged() {
        guard let library, let service else { return }
        let profiles = library.hosts.map(\.profile)
        requestedProfiles = profiles
        journal { try await service.localChanged(profiles: profiles) }
    }

    func setEnabled(_ enabled: Bool) {
        guard let library, let service, !busy else { return }
        perform {
            if enabled { try await service.enable(profiles: library.hosts.map(\.profile)) } else {
                try await service.disable()
            }
        }
    }

    func refresh() {
        guard let library, let service, snapshot.enabled, !busy else { return }
        perform { try await service.refresh(profiles: library.hosts.map(\.profile)) }
    }

    func restore(_ conflict: CloudProfileConflict) {
        guard let library, var profile = conflict.profile else { return }
        do {
            profile.id = UUID()
            profile.name = profile.displayName + " (Recovered)"
            try library.applySyncedProfiles(library.hosts.map(\.profile) + [profile])
            localChanged()
            dismissConflict(conflict)
        } catch { self.error = error.localizedDescription }
    }

    func dismissConflict(_ conflict: CloudProfileConflict) {
        guard let service else { return }
        journal { try await service.dismissConflict(conflict.id) }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        busy = true; error = nil
        Task {
            do { try await action() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    private func journal(_ action: @escaping () async throws -> Void) {
        let previous = journalTask
        journalTask = Task {
            await previous?.value
            do { try await action() } catch { self.error = error.localizedDescription }
        }
    }

    private func sameProfiles(_ lhs: [HostProfile], _ rhs: [HostProfile]) -> Bool {
        lhs.count == rhs.count && Set(lhs.map(\.id)).count == lhs.count && Set(rhs.map(\.id)).count == rhs.count &&
            Dictionary(uniqueKeysWithValues: lhs.map { ($0.id, $0) }) ==
            Dictionary(uniqueKeysWithValues: rhs.map { ($0.id, $0) })
    }
}
