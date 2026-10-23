import Foundation
import HarborCore

final class TestSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var writes = 0
    private var failureAt: Int?

    var snapshot: [String: Data] { lock.withLock { items } }
    func failInsert(at index: Int?) { lock.withLock { failureAt = index; writes = 0 } }
    func data(for account: String) -> Data? { lock.withLock { items[account] } }
    func remove(_ account: String) { _ = lock.withLock { items.removeValue(forKey: account) } }
    func remove(_ account: String, matching expected: Data) throws {
        try lock.withLock {
            guard items[account] == expected else { throw HarborError.message("Keychain item changed") }
            items.removeValue(forKey: account)
        }
    }
    func insert(_ data: Data, for account: String) throws {
        try lock.withLock {
            writes += 1
            if failureAt == writes { throw HarborError.message("Simulated Keychain unavailable") }
            guard items[account] == nil else { throw HarborError.message("Duplicate Keychain account") }
            items[account] = data
        }
    }
}
