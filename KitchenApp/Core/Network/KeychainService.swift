import Foundation
import Security

enum KeychainService {
    private static let accessTokenKey  = "com.kitchenrecipe.access_token"
    private static let refreshTokenKey = "com.kitchenrecipe.refresh_token"

    // MARK: - Typed accessors

    static var accessToken: String? {
        get { load(key: accessTokenKey) }
        set { newValue == nil ? delete(key: accessTokenKey) : save(newValue!, key: accessTokenKey) }
    }

    static var refreshToken: String? {
        get { load(key: refreshTokenKey) }
        set { newValue == nil ? delete(key: refreshTokenKey) : save(newValue!, key: refreshTokenKey) }
    }

    static func clearAll() {
        delete(key: accessTokenKey)
        delete(key: refreshTokenKey)
    }

    // MARK: - Primitives

    private static func save(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        // kSecAttrAccessibleWhenUnlockedThisDeviceOnly:
        //   - tokens are unreadable while the device is locked
        //   - prevents migration to other devices via iCloud Keychain or encrypted backups
        let query: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrAccount:    key,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData:      data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
