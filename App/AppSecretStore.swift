import FarportCore
import FarportSecurity
import Foundation

struct AppSecretStore: SecretStore {
    func data(for account: String) throws -> Data? { try KeychainSecretStore.shared().data(for: account) }
    func insert(_ data: Data, for account: String) throws {
        try KeychainSecretStore.shared().insert(data, for: account)
    }
    func remove(_ account: String) throws { try KeychainSecretStore.shared().remove(account) }
    func remove(_ account: String, matching expected: Data) throws {
        try KeychainSecretStore.shared().remove(account, matching: expected)
    }
}
