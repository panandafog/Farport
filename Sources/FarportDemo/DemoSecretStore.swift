#if DEBUG
import FarportCore
import Foundation

/// First-use trust works normally, but demo pins never touch the real Keychain.
public final class DemoSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    public init() {}
    public func data(for account: String) -> Data? { lock.withLock { items[account] } }
    public func insert(_ data: Data, for account: String) throws {
        try lock.withLock {
            guard items[account] == nil else { throw HarborError.message("Duplicate demo key") }
            items[account] = data
        }
    }
    public func remove(_ account: String) { _ = lock.withLock { items.removeValue(forKey: account) } }
    public func remove(_ account: String, matching expected: Data) throws {
        try lock.withLock {
            guard items[account] == expected else { throw HarborError.message("Demo key changed") }
            items.removeValue(forKey: account)
        }
    }
}
#endif
