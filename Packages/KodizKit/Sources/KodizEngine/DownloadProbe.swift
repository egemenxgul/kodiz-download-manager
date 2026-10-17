import Foundation

public struct ProbeResult: Sendable {
    public let originalURL: URL
    public let finalURL: URL
    public let statusCode: Int
    public let supportsRange: Bool
    public let totalBytes: Int64?
    public let etag: String?
    public let lastModified: String?
    public let contentType: String?
    public let contentDisposition: String?
    public let suggestedFileName: String

    public init(
        originalURL: URL,
        finalURL: URL,
        statusCode: Int,
        supportsRange: Bool,
        totalBytes: Int64?,
        etag: String?,
        lastModified: String?,
        contentType: String?,
        contentDisposition: String?,
        suggestedFileName: String
    ) {
        self.originalURL = originalURL
        self.finalURL = finalURL
        self.statusCode = statusCode
        self.supportsRange = supportsRange
        self.totalBytes = totalBytes
        self.etag = etag
        self.lastModified = lastModified
        self.contentType = contentType
        self.contentDisposition = contentDisposition
        self.suggestedFileName = suggestedFileName
    }
}

public actor DownloadProbe {
    private let urlSession: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }

    public func probe(
        url: URL,
        userAgent: String? = nil,
        referer: String? = nil,
        cookies: [String: String]? = nil,
        extraHeaders: [String: String]? = nil
    ) async throws -> ProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        if let ua = userAgent {
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
        } else {
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        }

        if let ref = referer {
            request.setValue(ref, forHTTPHeaderField: "Referer")
        }

        if let cookies = cookies, !cookies.isEmpty {
            let cookieHeader = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        if let extra = extraHeaders {
            for (key, val) in extra {
                request.setValue(val, forHTTPHeaderField: key)
            }
        }

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let statusCode = httpResponse.statusCode
        let finalURL = httpResponse.url ?? url
        let allHeaders = httpResponse.allHeaderFields

        func headerVal(_ name: String) -> String? {
            for (k, v) in allHeaders {
                if String(describing: k).caseInsensitiveCompare(name) == .orderedSame {
                    return String(describing: v)
                }
            }
            return nil
        }

        let contentDisposition = headerVal("Content-Disposition")
        let contentType = headerVal("Content-Type")
        let etag = headerVal("ETag")
        let lastModified = headerVal("Last-Modified")
        let contentRange = headerVal("Content-Range")
        let acceptRanges = headerVal("Accept-Ranges")

        var supportsRange = false
        var totalBytes: Int64?

        if statusCode == 206 {
            supportsRange = true
            if let cr = contentRange {
                // Format: bytes 0-0/1234567 or bytes 0-0/*
                if let slashIndex = cr.lastIndex(of: "/") {
                    let totalStr = String(cr[cr.index(after: slashIndex)...]).trimmingCharacters(in: .whitespaces)
                    if let parsedTotal = Int64(totalStr) {
                        totalBytes = parsedTotal
                    }
                }
            }
        } else if statusCode == 200 {
            // Server ignored Range header or doesn't support ranges
            if let ar = acceptRanges, ar.caseInsensitiveCompare("bytes") == .orderedSame {
                supportsRange = true
            }
            if let cl = headerVal("Content-Length"), let parsedCL = Int64(cl) {
                totalBytes = parsedCL
            }
        }

        let suggestedFileName = FileNameParser.resolveFileName(
            contentDisposition: contentDisposition,
            url: finalURL,
            mimeType: contentType
        )

        return ProbeResult(
            originalURL: url,
            finalURL: finalURL,
            statusCode: statusCode,
            supportsRange: supportsRange,
            totalBytes: totalBytes,
            etag: etag,
            lastModified: lastModified,
            contentType: contentType,
            contentDisposition: contentDisposition,
            suggestedFileName: suggestedFileName
        )
    }
}
