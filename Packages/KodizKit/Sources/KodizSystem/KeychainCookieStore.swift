import Foundation
import Security

public enum KeychainCookieStore: Sendable {
    private static let serviceName = "dev.kodiz.DownloadManager.cookies"

    public static func saveCookies(_ cookies: [HTTPCookie], for downloadId: UUID) {
        guard !cookies.isEmpty else {
            deleteCookies(for: downloadId)
            return
        }

        let cookieDicts: [[String: String]] = cookies.compactMap { cookie in
            var dict: [String: String] = [:]
            dict["name"] = cookie.name
            dict["value"] = cookie.value
            dict["domain"] = cookie.domain
            dict["path"] = cookie.path
            if cookie.isSecure { dict["secure"] = "TRUE" }
            return dict
        }

        guard let data = try? JSONSerialization.data(withJSONObject: cookieDicts) else { return }

        // Remove existing item if any
        deleteCookies(for: downloadId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: downloadId.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    public static func loadCookies(for downloadId: UUID) -> [HTTPCookie] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: downloadId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return [] }

        guard let jsonArray = (try? JSONSerialization.jsonObject(with: data)) as? [[String: String]] else {
            return []
        }

        return jsonArray.compactMap { dict in
            guard let name = dict["name"], let value = dict["value"], let domain = dict["domain"] else { return nil }
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: dict["path"] ?? "/"
            ]
            if dict["secure"] == "TRUE" {
                props[.secure] = "TRUE"
            }
            return HTTPCookie(properties: props)
        }
    }

    public static func deleteCookies(for downloadId: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: downloadId.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
