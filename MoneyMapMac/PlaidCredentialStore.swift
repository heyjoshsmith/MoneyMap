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
    private let bundledCredentialsAccount = "credentials.v1"
    private let defaults = UserDefaults.standard
    private let savedCredentialsHintKey = "plaid.credentialsSaved"
    private let savedSecretEnvironmentsKey = "plaid.savedSecretEnvironments"

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

    var hasStoredCredentialsHint: Bool {
        defaults.bool(forKey: savedCredentialsHintKey)
    }

    var savedSecretEnvironments: Set<PlaidCredentialEnvironment> {
        let rawValues = defaults.stringArray(forKey: savedSecretEnvironmentsKey) ?? []
        return Set(rawValues.compactMap(PlaidCredentialEnvironment.init(rawValue:)))
    }

    func loadCredentials() throws -> PlaidStoredCredentials? {
        let environment = selectedEnvironment
        if let bundle = try loadBundledCredentials(),
           let secret = bundle.secrets[environment.rawValue],
           !bundle.clientID.isEmpty,
           !secret.isEmpty {
            markCredentialsSaved(for: environment)
            return PlaidStoredCredentials(clientID: bundle.clientID, secret: secret, environment: environment)
        }

        guard
            let clientID = try readString(account: "clientID"),
            let secret = try readString(account: secretAccount(for: environment))
        else {
            return nil
        }

        try updateBundledCredentials { bundle in
            bundle.clientID = clientID
            bundle.secrets[environment.rawValue] = secret
        }
        markCredentialsSaved(for: environment)
        return PlaidStoredCredentials(clientID: clientID, secret: secret, environment: environment)
    }

    func loadClientID() throws -> String? {
        if let clientID = try loadBundledCredentials()?.clientID, !clientID.isEmpty {
            return clientID
        }
        return try readString(account: "clientID")
    }

    func secret(for environment: PlaidCredentialEnvironment) throws -> String? {
        if let secret = try loadBundledCredentials()?.secrets[environment.rawValue], !secret.isEmpty {
            return secret
        }
        return try readString(account: secretAccount(for: environment))
    }

    func save(clientID: String, secret: String, environment: PlaidCredentialEnvironment) throws {
        try updateBundledCredentials { bundle in
            bundle.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            bundle.secrets[environment.rawValue] = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        defaults.set(environment.rawValue, forKey: "plaid.selectedEnvironment")
        markCredentialsSaved(for: environment)
    }

    func accessToken(for itemID: String) throws -> String? {
        if let accessToken = try loadBundledCredentials()?.accessTokens[itemID], !accessToken.isEmpty {
            return accessToken
        }

        guard let accessToken = try readString(account: "accessToken.\(itemID)") else {
            return nil
        }

        try updateBundledCredentials { bundle in
            bundle.accessTokens[itemID] = accessToken
        }
        return accessToken
    }

    func saveAccessToken(_ accessToken: String, itemID: String) throws {
        try updateBundledCredentials { bundle in
            bundle.accessTokens[itemID] = accessToken
        }
    }

    func deleteAccessToken(for itemID: String) throws {
        try delete(account: "accessToken.\(itemID)")
        guard var bundle = try loadBundledCredentials() else {
            return
        }

        bundle.accessTokens.removeValue(forKey: itemID)
        try saveBundledCredentials(bundle)
    }

    private func readString(account: String) throws -> String? {
        guard let data = try readData(account: account) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func readData(account: String) throws -> Data? {
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
        return data
    }

    private func writeData(_ data: Data, account: String) throws {
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

    private func loadBundledCredentials() throws -> PlaidStoredCredentialBundle? {
        if PlaidCredentialBundleCache.didLoad {
            return PlaidCredentialBundleCache.value
        }

        guard let data = try readData(account: bundledCredentialsAccount) else {
            PlaidCredentialBundleCache.didLoad = true
            PlaidCredentialBundleCache.value = nil
            return nil
        }

        let bundle = try JSONDecoder().decode(PlaidStoredCredentialBundle.self, from: data)
        PlaidCredentialBundleCache.didLoad = true
        PlaidCredentialBundleCache.value = bundle
        return bundle
    }

    private func updateBundledCredentials(_ update: (inout PlaidStoredCredentialBundle) -> Void) throws {
        var bundle = try loadBundledCredentials() ?? PlaidStoredCredentialBundle()
        update(&bundle)
        try saveBundledCredentials(bundle)
    }

    private func saveBundledCredentials(_ bundle: PlaidStoredCredentialBundle) throws {
        let data = try JSONEncoder().encode(bundle)
        try writeData(data, account: bundledCredentialsAccount)
        PlaidCredentialBundleCache.didLoad = true
        PlaidCredentialBundleCache.value = bundle
    }

    func markCredentialsSaved(for environment: PlaidCredentialEnvironment) {
        defaults.set(true, forKey: savedCredentialsHintKey)
        let rawValues = Set(defaults.stringArray(forKey: savedSecretEnvironmentsKey) ?? [])
            .union([environment.rawValue])
            .sorted()
        defaults.set(rawValues, forKey: savedSecretEnvironmentsKey)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct PlaidStoredCredentialBundle: Codable {
    var clientID = ""
    var secrets: [String: String] = [:]
    var accessTokens: [String: String] = [:]
}

private enum PlaidCredentialBundleCache {
    static var didLoad = false
    static var value: PlaidStoredCredentialBundle?
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
    }
}
