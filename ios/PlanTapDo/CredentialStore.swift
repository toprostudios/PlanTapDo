import Foundation
import Security

struct CredentialStore {
    static let shared = CredentialStore()

    private let service = "com.plantapdo.app.authentication"
    private let pendingLogoutService = "com.plantapdo.app.pending-logout"

    struct PendingLogout: Equatable {
        let accountID: UUID
        let tokens: APIClient.AuthTokens
    }

    func load(accountID: UUID) -> APIClient.AuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(APIClient.AuthTokens.self, from: data)
    }

    @discardableResult
    func save(_ tokens: APIClient.AuthTokens, accountID: UUID) -> Bool {
        save(tokens, accountID: accountID, service: service)
    }

    @discardableResult
    func savePendingLogout(_ tokens: APIClient.AuthTokens, accountID: UUID) -> Bool {
        save(tokens, accountID: accountID, service: pendingLogoutService)
    }

    private func save(
        _ tokens: APIClient.AuthTokens,
        accountID: UUID,
        service targetService: String
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: accountID.uuidString,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // The app has no background sync requirement. Keep bearer tokens
            // unavailable while the device is locked and never migrate them to
            // another device through a backup.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var newItem = query
        attributes.forEach { newItem[$0.key] = $0.value }
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }

    func delete(accountID: UUID) {
        delete(accountID: accountID, service: service)
    }

    func deletePendingLogout(accountID: UUID) {
        delete(accountID: accountID, service: pendingLogoutService)
    }

    private func delete(accountID: UUID, service targetService: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: accountID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func loadPendingLogouts() -> [PendingLogout] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: pendingLogoutService,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let rawAccount = item[kSecAttrAccount as String] as? String,
                  let accountID = UUID(uuidString: rawAccount),
                  let data = item[kSecValueData as String] as? Data,
                  let tokens = try? JSONDecoder().decode(APIClient.AuthTokens.self, from: data) else {
                return nil
            }
            return PendingLogout(accountID: accountID, tokens: tokens)
        }
    }
}
