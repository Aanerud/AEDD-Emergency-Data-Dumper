import Foundation
import Security
import AppKit

class KeychainService {
    private let serviceName = "AEDD SMB Credentials"

    enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case invalidData
        case unexpectedError(OSStatus)

        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Credentials not found in keychain"
            case .duplicateItem:
                return "Credentials already exist in keychain"
            case .invalidData:
                return "Invalid credential data"
            case .unexpectedError(let status):
                return "Keychain error: \(status)"
            }
        }
    }

    func savePassword(_ password: String, for account: String, host: String) async throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let fullAccount = "\(account)@\(host)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: fullAccount,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            try await updatePassword(password, for: account, host: host, passwordData: passwordData)
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedError(status)
        }
    }

    private func updatePassword(_ password: String, for account: String, host: String, passwordData: Data) async throws {
        let fullAccount = "\(account)@\(host)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: fullAccount
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: passwordData
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status != errSecSuccess {
            throw KeychainError.unexpectedError(status)
        }
    }

    func retrievePassword(for account: String, host: String) throws -> String {
        let fullAccount = "\(account)@\(host)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: fullAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            } else {
                throw KeychainError.unexpectedError(status)
            }
        }

        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return password
    }

    func deleteCredentials(for account: String, host: String) throws {
        let fullAccount = "\(account)@\(host)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: fullAccount
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedError(status)
        }
    }

    func listStoredCredentials() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return []
            } else {
                throw KeychainError.unexpectedError(status)
            }
        }

        guard let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            item[kSecAttrAccount as String] as? String
        }
    }

    private func getPasswordFromUser() -> String? {
        let alert = NSAlert()
        alert.messageText = "Enter Password"
        alert.informativeText = "Please enter your SMB password:"
        alert.alertStyle = .informational

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        alert.accessoryView = passwordField

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == NSApplication.ModalResponse.alertFirstButtonReturn {
            return passwordField.stringValue
        }

        return nil
    }
}

extension KeychainService {
    func hasStoredCredentials(for account: String, host: String) -> Bool {
        do {
            _ = try retrievePassword(for: account, host: host)
            return true
        } catch {
            return false
        }
    }
}