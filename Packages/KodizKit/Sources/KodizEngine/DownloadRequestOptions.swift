import Foundation

public struct DownloadRequestCookie: Codable, Sendable, Equatable {
    public let name: String
    public let value: String
    public let domain: String?
    public let path: String?
    public let secure: Bool
    public let httpOnly: Bool
    public let expirationDate: Date?

    public init(
        name: String,
        value: String,
        domain: String? = nil,
        path: String? = nil,
        secure: Bool = false,
        httpOnly: Bool = false,
        expirationDate: Date? = nil
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.secure = secure
        self.httpOnly = httpOnly
        self.expirationDate = expirationDate
    }

    public init(from cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.secure = cookie.isSecure
        self.httpOnly = cookie.isHTTPOnly
        self.expirationDate = cookie.expiresDate
    }

    public func matches(url: URL) -> Bool {
        if let domain = domain {
            let host = url.host?.lowercased() ?? ""
            let cleanDomain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if host != cleanDomain && !host.hasSuffix("." + cleanDomain) {
                return false
            }
        }
        if let path = path {
            let urlPath = url.path.isEmpty ? "/" : url.path
            if !urlPath.hasPrefix(path) {
                return false
            }
        }
        if secure && url.scheme?.lowercased() != "https" {
            return false
        }
        return true
    }
}

public struct DownloadRequestOptions: Sendable {
    public var userAgent: String?
    public var referer: String?
    public var cookies: [DownloadRequestCookie]
    public var extraHeaders: [String: String]
    public var speedLimit: Int64 // bytes/sec, 0 for unlimited

    public init(
        userAgent: String? = nil,
        referer: String? = nil,
        cookies: [DownloadRequestCookie] = [],
        extraHeaders: [String: String] = [:],
        speedLimit: Int64 = 0
    ) {
        self.userAgent = userAgent
        self.referer = referer
        self.cookies = cookies
        self.extraHeaders = extraHeaders
        self.speedLimit = speedLimit
    }

    public func cookieHeader(for url: URL) -> String? {
        let matching = cookies.filter { $0.matches(url: url) }
        guard !matching.isEmpty else { return nil }
        return matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}
