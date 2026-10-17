import Foundation

public struct BridgeMessage: Codable, Sendable {
    public let v: Int
    public let id: String
    public let type: String
    public let browser: String?
    public let payload: BridgePayload?

    public init(v: Int = 1, id: String = UUID().uuidString, type: String, browser: String? = nil, payload: BridgePayload? = nil) {
        self.v = v
        self.id = id
        self.type = type
        self.browser = browser
        self.payload = payload
    }
}

public struct BridgeCookie: Codable, Sendable {
    public let name: String
    public let value: String
    public let domain: String?
    public let path: String?
    public let secure: Bool?
    public let httpOnly: Bool?
    public let expirationDate: Double?

    public init(name: String, value: String, domain: String? = nil, path: String? = nil, secure: Bool? = nil, httpOnly: Bool? = nil, expirationDate: Double? = nil) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.secure = secure
        self.httpOnly = httpOnly
        self.expirationDate = expirationDate
    }
}

public struct BridgePayload: Codable, Sendable {
    public let url: String?
    public let referrer: String?
    public let pageUrl: String?
    public let fileNameHint: String?
    public let totalBytes: Int64?
    public let mime: String?
    public let userAgent: String?
    public let cookies: [BridgeCookie]?
    public let incognito: Bool?
    public let extraHeaders: [String: String]?

    public init(
        url: String? = nil,
        referrer: String? = nil,
        pageUrl: String? = nil,
        fileNameHint: String? = nil,
        totalBytes: Int64? = nil,
        mime: String? = nil,
        userAgent: String? = nil,
        cookies: [BridgeCookie]? = nil,
        incognito: Bool? = nil,
        extraHeaders: [String: String]? = nil
    ) {
        self.url = url
        self.referrer = referrer
        self.pageUrl = pageUrl
        self.fileNameHint = fileNameHint
        self.totalBytes = totalBytes
        self.mime = mime
        self.userAgent = userAgent
        self.cookies = cookies
        self.incognito = incognito
        self.extraHeaders = extraHeaders
    }
}

public struct BridgeConfigPayload: Codable, Sendable {
    public let enabled: Bool
    public let minSizeBytes: Int64
    public let interceptExtensions: [String]
    public let excludedExtensions: [String]
    public let excludedDomains: [String]
    public let interceptIncognito: Bool

    public init(
        enabled: Bool = true,
        minSizeBytes: Int64 = 1048576,
        interceptExtensions: [String] = ["zip", "dmg", "pkg", "iso", "tar", "gz", "tgz", "7z", "rar", "mp4", "mkv", "mov", "mp3", "wav", "exe", "bin"],
        excludedExtensions: [String] = ["pdf", "png", "jpg", "jpeg", "webp", "gif", "svg", "html", "css", "js"],
        excludedDomains: [String] = [],
        interceptIncognito: Bool = false
    ) {
        self.enabled = enabled
        self.minSizeBytes = minSizeBytes
        self.interceptExtensions = interceptExtensions
        self.excludedExtensions = excludedExtensions
        self.excludedDomains = excludedDomains
        self.interceptIncognito = interceptIncognito
    }
}

public struct BridgeResponse: Codable, Sendable {
    public let v: Int
    public let id: String
    public let ok: Bool
    public let downloadId: String?
    public let reason: String?
    public let config: BridgeConfigPayload?

    public init(v: Int = 1, id: String, ok: Bool, downloadId: String? = nil, reason: String? = nil, config: BridgeConfigPayload? = nil) {
        self.v = v
        self.id = id
        self.ok = ok
        self.downloadId = downloadId
        self.reason = reason
        self.config = config
    }
}

/// Helper for standard 4-byte little-endian message framing (NMH stdio protocol)
public enum MessageFraming {
    public static func encode(_ data: Data) -> Data {
        var length = UInt32(data.count).littleEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(data)
        return framed
    }

    public static func decodeHeader(from data: Data) -> UInt32? {
        guard data.count >= 4 else { return nil }
        return data.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    }
}
