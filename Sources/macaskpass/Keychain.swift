import Foundation
import Security

/// 登录钥匙串（file-based keychain）读写。
///
/// 条目由本程序创建，钥匙串会把 ACL 绑定到本程序的代码签名上：
/// 其他程序想读取会弹出系统的「钥匙串访问」对话框并要求登录密码，
/// 而本程序读取前必须先通过 Touch ID（见 Biometrics.swift）。
struct Keychain {
    static let service = "macaskpass"

    let account: String

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keychain.service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 只查属性、不取数据，因此不会触发钥匙串 ACL 授权对话框。
    func exists() -> Bool {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    func modificationDate() -> Date? {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attrs = result as? [String: Any] else { return nil }
        return attrs[kSecAttrModificationDate as String] as? Date
    }

    func save(_ password: Data) throws {
        // 先删后加：重新写入会把 ACL 重置为「当前这个二进制」，
        // 这样重新编译/安装后再跑一次 --set-password 即可恢复免提示读取。
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = password
        query[kSecAttrLabel as String] = "macaskpass (sudo password for \(account))"
        query[kSecAttrDescription as String] = "sudo askpass password"
        query[kSecAttrComment as String] = "由 macaskpass 创建，仅在 Touch ID 验证通过后交给 sudo。"
        query[kSecAttrSynchronizable as String] = false

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw MacAskpassError.keychain(status) }
    }

    func load() throws -> Data {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw MacAskpassError.noStoredPassword }
        guard status == errSecSuccess, let data = result as? Data else {
            throw MacAskpassError.keychain(status)
        }
        return data
    }

    @discardableResult
    func delete() throws -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw MacAskpassError.keychain(status) }
        return true
    }
}
