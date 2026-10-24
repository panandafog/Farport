import CloudKit
import FarportCore
import FarportLocalization
import Foundation

extension CloudHostSync: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine, document.enabled else { return }
        do {
            try process(event)
        } catch {
            // Never persist a newer change token after failing to decode or durably store a received record.
            stopEngine()
            document.enabled = false
            status = L10n.text("Sync stopped: %@", error.localizedDescription)
            document.pauseReason = status
            try? file.save(document)
            publish()
        }
    }

    private func process(_ event: CKSyncEngine.Event) throws {
        switch event {
        case .stateUpdate(let value): document.engineState = value.stateSerialization; try checkpoint()
        case .accountChange(let value): try accountChanged(value)
        case .fetchedDatabaseChanges(let value):
            if value.deletions.contains(where: { $0.zoneID == CloudHostCodec.zoneID }) {
                try pause(L10n.text(
                    "The iCloud host library was reset. Enable sync again to merge local hosts."
                ), reset: true)
            }
        case .fetchedRecordZoneChanges(let value): try received(value)
        case .sentRecordZoneChanges(let value): try sent(value)
        case .sentDatabaseChanges(let value):
            if let failure = value.failedZoneSaves.first { try pauseForFailure(failure.error) }
        default: progress(event)
        }
    }

    private func accountChanged(_ value: CKSyncEngine.Event.AccountChange) throws {
        switch value.changeType {
        case .signIn(let user) where user.recordName == document.accountID: break
        default: try pause(L10n.text(
            "iCloud account changed. Local hosts kept; enable sync again to continue."
        ), reset: true)
        }
    }

    private func received(_ value: CKSyncEngine.Event.FetchedRecordZoneChanges) throws {
        for update in value.modifications where update.record.recordID.zoneID == CloudHostCodec.zoneID {
            try merge(update.record)
        }
        for deletion in value.deletions where deletion.recordID.zoneID == CloudHostCodec.zoneID {
            guard let id = UUID(uuidString: deletion.recordID.recordName) else {
                throw HarborError.message(L10n.text("Unsupported iCloud host identifier."))
            }
            document.serverFields.removeValue(forKey: id.uuidString)
            try document.ledger.serverDeleted(id)
        }
        try checkpoint()
        enqueue()
    }

    private func sent(_ value: CKSyncEngine.Event.SentRecordZoneChanges) throws {
        for record in value.savedRecords {
            document.ledger.acknowledge(try CloudHostCodec.decode(record))
            remember(record)
        }
        for failure in value.failedRecordSaves { try failedSave(failure) }
        document.lastContact = Date()
        try checkpoint()
        enqueue()
    }

    private func progress(_ event: CKSyncEngine.Event) {
        switch event {
        case .willFetchChanges: status = L10n.text("Fetching changes"); publish()
        case .willSendChanges: status = L10n.text("Sending changes"); publish()
        case .didSendChanges:
            if issue == nil {
                status = document.ledger.pending.isEmpty ? L10n.text("Up to date") : L10n.text("Changes queued")
            }
            publish()
        case .didFetchRecordZoneChanges(let value):
            if let error = value.error { report(error) }
        default: break
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                          syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine, document.enabled, sendingAllowed else { return nil }
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            await self.record(for: id)
        }
    }

    func record(for id: CKRecord.ID) -> CKRecord? {
        guard document.enabled, sendingAllowed, id.zoneID == CloudHostCodec.zoneID,
              let uuid = UUID(uuidString: id.recordName), let value = document.ledger.records[uuid] else { return nil }
        do { return try CloudHostCodec.encode(value, fields: document.serverFields[id.recordName]) } catch {
            stopEngine(); document.enabled = false; report(error)
            try? file.save(document)
            return nil
        }
    }

    func merge(_ record: CKRecord) throws {
        try document.ledger.merge(CloudHostCodec.decode(record))
        remember(record)
    }

    func remember(_ record: CKRecord) {
        // A late acknowledgment must not overwrite newer server system fields/change tags.
        if let old = document.serverFields[record.recordID.recordName],
           let decoder = try? NSKeyedUnarchiver(forReadingFrom: old) {
            decoder.requiresSecureCoding = true
            let previous = CKRecord(coder: decoder)
            decoder.finishDecoding()
            if let date = previous?.modificationDate, date > record.modificationDate ?? .distantPast { return }
        }
        document.serverFields[record.recordID.recordName] = CloudHostCodec.systemFields(record)
    }

    private func failedSave(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) throws {
        let id = failure.record.recordID
        switch failure.error.code {
        case .serverRecordChanged:
            guard let server = failure.error.serverRecord else { throw failure.error }
            try merge(server)
        case .zoneNotFound:
            document.serverFields.removeValue(forKey: id.recordName)
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudHostCodec.zoneID))])
        case .unknownItem:
            document.serverFields.removeValue(forKey: id.recordName)
            if let uuid = UUID(uuidString: id.recordName) { try document.ledger.serverDeleted(uuid) }
        default: try pauseForFailure(failure.error)
        }
    }

    private func pauseForFailure(_ error: CKError) throws {
        switch error.code {
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy,
             .operationCancelled, .batchRequestFailed:
            report(error)
            return
        default: break
        }
        // Retain the durable queue, but do not repeatedly submit a rejected record or zone.
        try pause(L10n.text("iCloud upload paused: %@ Enable sync again to retry.", error.localizedDescription))
    }
}
