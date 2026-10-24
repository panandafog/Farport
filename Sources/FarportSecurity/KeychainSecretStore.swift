import FarportCore
import FarportLocalization
import Foundation
import LocalAuthentication
import Security

public struct KeychainSecretStore: SecretStore {
    private let service: String
    private let accessGroup: String

    public init(accessGroup: String, service: String = "dev.harbor.secrets") {
        self.accessGroup = accessGroup; self.service = service
    }

    public static func shared(bundle: Bundle = .main) throws -> KeychainSecretStore {
        guard let group = bundle.object(forInfoDictionaryKey: "HarborKeychainGroup") as? String,
              !group.isEmpty, !group.contains("$(") else {
            throw HarborError.message(L10n.text(
                "Shared Keychain is not configured. Build the signed Farport application."
            ))
        }
        return KeychainSecretStore(accessGroup: group)
    }

    public func data(for account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw HarborError.message(L10n.text("Invalid Keychain item data.")) }
        return data
    }

    public func insert(_ data: Data, for account: String) throws {
        var attributes = query(account)
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        try check(SecItemAdd(attributes as CFDictionary, nil))
    }

    public func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    public func remove(_ account: String, matching expected: Data) throws {
        var request = query(account)
        request[kSecReturnData] = true
        request[kSecReturnPersistentRef] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext] = context
        var result: CFTypeRef?
        try check(SecItemCopyMatching(request as CFDictionary, &result))
        guard let item = result as? [CFString: Any], item[kSecValueData] as? Data == expected,
              let reference = item[kSecValuePersistentRef] as? Data else {
            throw HarborError.message(L10n.text("The Keychain item changed. Nothing was removed."))
        }
        // Delete this immutable item identity, not a newly inserted pin at the same account.
        let deletion: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: reference, kSecUseDataProtectionKeychain: true]
        try check(SecItemDelete(deletion as CFDictionary))
    }

    private func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
         kSecAttrAccessGroup: accessGroup, kSecUseDataProtectionKeychain: true, kSecAttrSynchronizable: false]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? L10n.text("Unknown error")
            throw HarborError.message(L10n.text(
                "Keychain is unavailable (%lld): %@. No plaintext fallback was used.", Int64(status), detail
            ))
        }
    }
}
