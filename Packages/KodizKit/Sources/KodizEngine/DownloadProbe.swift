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
    public init() {}

    public func probe(
        url: URL,
        options: DownloadRequestOptions? = nil
    ) async throws -> ProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let opts = options ?? DownloadRequestOptions()

        if let ua = opts.userAgent {
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
        } else {
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        }

        if let ref = opts.referer {
            request.setValue(ref, forHTTPHeaderField: "Referer")
        }

        if let cookieHeader = opts.cookieHeader(for: url) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        for (key, val) in opts.extraHeaders {
            request.setValue(val, forHTTPHeaderField: key)
        }

        let probeDelegate = ProbeSessionDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0

        let session = URLSession(configuration: config, delegate: probeDelegate, delegateQueue: nil)

        let httpResponse = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPURLResponse, Error>) in
            probeDelegate.start(request: request, session: session, continuation: continuation)
        }

        session.invalidateAndCancel()

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
            // Server ignored Range header
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

// MARK: - ProbeSessionDelegate

private final class ProbeSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HTTPURLResponse, Error>?

    func start(request: URLRequest, session: URLSession, continuation: CheckedContinuation<HTTPURLResponse, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()

        let task = session.dataTask(with: request)
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            resumeWithError(URLError(.badServerResponse))
            completionHandler(.cancel)
            return
        }

        lock.lock()
        if let cont = continuation {
            continuation = nil
            lock.unlock()
            cont.resume(returning: httpResponse)
        } else {
            lock.unlock()
        }

        // Cancel probe immediately after headers received to avoid buffering entire response
        completionHandler(.cancel)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // If task was cancelled by completionHandler(.cancel), it's a normal completion for probe
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            resumeWithError(error)
        }
    }

    private func resumeWithError(_ error: Error) {
        lock.lock()
        if let cont = continuation {
            continuation = nil
            lock.unlock()
            cont.resume(throwing: error)
        } else {
            lock.unlock()
        }
    }
}
