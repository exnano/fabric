import Foundation
import Security

public protocol MeilisearchMasterKeyStoring: Sendable {
    func masterKey(serviceID: UUID) throws -> String?
    func setMasterKey(_ masterKey: String?, serviceID: UUID) throws
}

public struct KeychainMeilisearchMasterKeyStore: MeilisearchMasterKeyStoring, Sendable {
    private let serviceName = "com.exnano.fabric.meilisearch.master-key"

    public init() {}

    public func masterKey(serviceID: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: serviceID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw FabricError.credentialStore(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func setMasterKey(_ masterKey: String?, serviceID: UUID) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: serviceID.uuidString,
        ]

        guard let masterKey, !masterKey.isEmpty else {
            let status = SecItemDelete(lookup as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw FabricError.credentialStore(status)
            }
            return
        }

        guard masterKey.lengthOfBytes(using: .utf8) >= 16 else {
            throw FabricError.invalidMeilisearchMasterKey
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(masterKey.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw FabricError.credentialStore(updateStatus)
        }

        var item = lookup
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw FabricError.credentialStore(addStatus)
        }
    }
}
