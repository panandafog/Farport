import CloudKit
import FarportCore
import FarportLocalization
import Foundation

enum CloudHostCodec {
    static let zoneID = CKRecordZone.ID(zoneName: "HarborHosts")
    static let recordType = "HarborHost"

    static func id(_ uuid: UUID) -> CKRecord.ID { CKRecord.ID(recordName: uuid.uuidString, zoneID: zoneID) }

    static func decode(_ record: CKRecord) throws -> CloudHostRecord {
        guard record.recordID.zoneID == zoneID, record.recordType == recordType,
              let data = record.encryptedValues["profile"] as? Data else {
            throw HarborError.message(L10n.text("Unsupported encrypted iCloud record. Update Farport before syncing."))
        }
        let value = try JSONDecoder().decode(CloudHostRecord.self, from: data)
        guard UUID(uuidString: record.recordID.recordName) == value.id else {
            throw HarborError.message(L10n.text("An iCloud record has an inconsistent host ID."))
        }
        try value.validate()
        return value
    }

    static func encode(_ value: CloudHostRecord, fields: Data?) throws -> CKRecord {
        try value.validate()
        let record: CKRecord
        if let fields {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: fields)
            decoder.requiresSecureCoding = true
            defer { decoder.finishDecoding() }
            guard let saved = CKRecord(coder: decoder), saved.recordID == id(value.id),
                  saved.recordType == recordType else {
                      throw HarborError.message(L10n.text("Invalid CloudKit record cache."))
                  }
            record = saved
        } else { record = CKRecord(recordType: recordType, recordID: id(value.id)) }
        record.encryptedValues["profile"] = try JSONEncoder().encode(value)
        return record
    }

    static func systemFields(_ record: CKRecord) -> Data {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder)
        encoder.finishEncoding()
        return encoder.encodedData
    }
}
