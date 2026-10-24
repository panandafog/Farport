import CloudKit
import FarportCore
import Foundation

public actor CloudHostSync: HostSyncService {
    let file: CloudSyncFile
    let containerIdentifier: String
    let changed: @Sendable (HostSyncSnapshot) -> Void
    var document: CloudSyncDocument
    var engine: CKSyncEngine?
    var sendingAllowed = false
    var latestProfiles: [HostProfile] = []
    var generation = UUID()
    var connecting = false
    var status = "Off"
    var issue: String?

    public init(url: URL, containerIdentifier: String,
                changed: @escaping @Sendable (HostSyncSnapshot) -> Void) throws {
        file = CloudSyncFile(url: url)
        let saved = try file.load()
        document = saved
        self.containerIdentifier = containerIdentifier
        self.changed = changed
        status = saved.pauseReason ?? (saved.enabled ? "Waiting for iCloud" : "Off")
    }

    public func resume(profiles: [HostProfile]) async {
        latestProfiles = profiles
        guard document.enabled else { publish(); return }
        do { try await refresh(profiles: profiles) } catch { report(error) }
    }

    public func enable(profiles: [HostProfile]) async throws {
        guard !connecting else { throw HarborError.message("iCloud is already connecting.") }
        latestProfiles = profiles
        let token = generation
        let container = CKContainer(identifier: containerIdentifier)
        let user = try await account(in: container)
        guard token == generation else { throw CancellationError() }
        if document.resetRequired || document.accountID.map({ $0 != user }) == true {
            stopEngine()
            document = CloudSyncDocument()
        }
        document.accountID = user
        document.enabled = true
        document.pauseReason = nil
        if document.initialized { try register(latestProfiles) } else { try checkpoint() }
        try await connect(container: container)
    }

    public func disable() async throws {
        document.enabled = false
        document.pauseReason = nil
        stopEngine()
        status = "Off - local hosts and iCloud data kept"
        try checkpoint()
    }

    public func refresh(profiles: [HostProfile]) async throws {
        latestProfiles = profiles
        guard document.enabled, !connecting else { return }
        if document.initialized { try register(profiles) }
        let token = generation
        let container = CKContainer(identifier: containerIdentifier)
        do {
            let user = try await account(in: container)
            guard token == generation else { throw CancellationError() }
            guard document.accountID == user else {
                try pause("iCloud account changed. Enable sync again to merge with this account.", reset: true)
                return
            }
            try await connect(container: container)
        } catch { report(error); throw error }
    }

    public func localChanged(profiles: [HostProfile]) throws {
        latestProfiles = profiles
        guard document.enabled, document.initialized else { return }
        try register(profiles)
        enqueue()
    }

    public func applied(profiles: [HostProfile]) throws {
        var ledger = document.ledger
        try ledger.applied(profiles)
        document.ledger = ledger
        latestProfiles = profiles
        try checkpoint()
    }

    public func dismissConflict(_ id: String) throws {
        document.ledger.dismissConflict(id)
        try checkpoint()
    }

    func connect(container: CKContainer) async throws {
        connecting = true
        defer { connecting = false }
        status = "Connecting to iCloud"
        issue = nil
        publish()
        let active: CKSyncEngine
        if let engine { active = engine } else {
            let configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                stateSerialization: document.engineState, delegate: self)
            active = CKSyncEngine(configuration)
            engine = active
        }
        do {
            // Fetch before initial publication, so an old unversioned local copy cannot overwrite cloud profiles.
            try await active.fetchChanges()
            guard engine === active, document.enabled else { throw CancellationError() }
            if !document.initialized {
                var ledger = document.ledger
                try ledger.bootstrap(latestProfiles)
                document.ledger = ledger
                document.initialized = true
            }
            document.lastContact = Date()
            sendingAllowed = true
            try checkpoint()
            active.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudHostCodec.zoneID))])
            enqueue()
            try await active.sendChanges()
            guard engine === active else { return }
            if issue == nil { status = document.ledger.pending.isEmpty ? "Up to date" : "Changes queued" }
            publish()
        } catch { report(error); throw error }
    }

    private func account(in container: CKContainer) async throws -> String {
        guard try await container.accountStatus() == .available else {
            throw HarborError.message("iCloud is unavailable. Check your Apple Account and iCloud settings.")
        }
        return try await container.userRecordID().recordName
    }

    private func register(_ profiles: [HostProfile]) throws {
        var ledger = document.ledger
        try ledger.localChanged(profiles)
        document.ledger = ledger
        try checkpoint()
    }

    func checkpoint() throws {
        do { try file.save(document); publish() } catch {
            stopEngine()
            document.enabled = false
            report(error)
            throw error
        }
    }

    func publish() {
        changed(HostSyncSnapshot(enabled: document.enabled, initialized: document.initialized,
            profiles: document.ledger.profiles, pendingCount: document.ledger.pending.count,
            conflicts: document.ledger.conflicts, status: status, lastContact: document.lastContact,
            baseline: Array(document.ledger.baseline.values)))
    }

    func report(_ error: Error) {
        if !(error is CancellationError) {
            issue = error.localizedDescription
            status = "Sync needs attention: " + error.localizedDescription
            publish()
        }
    }

    func pause(_ message: String, reset: Bool = false) throws {
        document.enabled = false
        document.pauseReason = message
        document.resetRequired = document.resetRequired || reset
        stopEngine()
        status = message
        try checkpoint()
    }

    func stopEngine() {
        let previous = engine
        engine = nil
        sendingAllowed = false
        generation = UUID()
        if let previous { Task { await previous.cancelOperations() } }
    }

    func enqueue() {
        guard let engine, sendingAllowed, document.enabled else { return }
        let pending = document.ledger.pending.map {
            CKSyncEngine.PendingRecordZoneChange.saveRecord(CloudHostCodec.id($0))
        }
        engine.state.remove(pendingRecordZoneChanges: engine.state.pendingRecordZoneChanges)
        engine.state.add(pendingRecordZoneChanges: pending)
    }
}
