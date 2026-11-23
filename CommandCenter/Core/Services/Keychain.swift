import Foundation
import Security

/// API keys and tokens live in the macOS Keychain, never in the database.
enum Keychain {
    private static let service = "dev.commandcenter.app"
    static var lastStatus: OSStatus = 0

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        lastStatus = SecItemAdd(add as CFDictionary, nil)
    }
}

enum KeychainKey {
    static let anthropic = "anthropic.apiKey"
    static let openai = "openai.apiKey"
    static let openrouter = "openrouter.apiKey"
    static let github = "github.token"
    static let gitlab = "gitlab.token"
}
