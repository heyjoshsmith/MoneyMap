//
//  PlaidCredentialStore.swift
//  MoneyMapMac
//
//  Created by Codex on 7/6/26.
//

import Foundation
import Security

enum PlaidCredentialEnvironment: String, CaseIterable, Identifiable {
    case sandbox
    case production

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sandbox: "Sandbox"
        case .production: "Production"
        }
    }

    var baseURL: URL {
        URL(string: "https://\(rawValue).plaid.com")!
    }
}

struct PlaidStoredCredentials {
    var clientID: String
    var secret: String
    var environment: PlaidCredentialEnvironment
}

struct PlaidCredentialStore {
    private let service = "com.heyjoshsmith.MoneyMap.plaid"
    private let defaults = UserDefaults.standard

    var selectedEnvironment: PlaidCredentialEnvironment {
        get {
            let rawValue = defaults.string(forKey: "plaid.selectedEnvironment") ?? PlaidCredentialEnvironment.sandbox.rawValue
            if rawValue == "development" {
                return .production
            }
            return PlaidCredentialEnvironment(rawValue: rawValue) ?? .sandbox
        }
        set {
            defaults.set(newValue.rawValue, forKey: "plaid.selectedEnvironment")
        }
    }

    func loadCredentials() throws -> PlaidStoredCredentials? {
        let environment = selectedEnvironment
        guard
            let clientID = try loadClientID(),
            let secret = try secret(for: environment)
        else {
            return nil
        }

        return PlaidStoredCredentials(clientID: clientID, secret: secret, environment: environment)
    }

    func loadClientID() throws -> String? {
        try readString(account: "clientID")
    }

    func secret(for environment: PlaidCredentialEnvironment) throws -> String? {
        try readString(account: secretAccount(for: environment))
    }

    func save(clientID: String, secret: String, environment: PlaidCredentialEnvironment) throws {
        try writeString(clientID.trimmingCharacters(in: .whitespacesAndNewlines), account: "clientID")
        try writeString(secret.trimmingCharacters(in: .whitespacesAndNewlines), account: secretAccount(for: environment))
        defaults.set(environment.rawValue, forKey: "plaid.selectedEnvironment")
    }

    func accessToken(for itemID: String) throws -> String? {
        try readString(account: "accessToken.\(itemID)")
    }

    func saveAccessToken(_ accessToken: String, itemID: String) throws {
        try writeString(accessToken, account: "accessToken.\(itemID)")
    }

    func deleteAccessToken(for itemID: String) throws {
        try delete(account: "accessToken.\(itemID)")
    }

    private func readString(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func writeString(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError(status: status)
        }
    }

    private func secretAccount(for environment: PlaidCredentialEnvironment) -> String {
        "\(environment.rawValue).secret"
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
    }
}
