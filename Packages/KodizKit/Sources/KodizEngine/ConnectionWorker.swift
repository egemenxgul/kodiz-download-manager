import Foundation

public protocol ConnectionWorkerDelegate: AnyObject, Sendable {
    func workerDidReceiveBytes(workerId: Int, segmentIdx: Int, count: Int64, speed: Double) async
    func workerDidCompleteSegment(workerId: Int, segmentIdx: Int) async
}

public actor ConnectionWorker {
    public let workerId: Int
    private var session: URLSession?
    private var activeDataTask: URLSessionDataTask?
    private weak var delegate: ConnectionWorkerDelegate?
    private var isCancelled: Bool = false

    // EWMA speed tracking
    private var ewmaSpeed: Double = 0.0
    private let alpha: Double = 0.2 // Weight for EWMA
    private var lastSpeedCalcTime: Date = Date()
    private var bytesSinceLastCalc: Int64 = 0

    public init(workerId: Int, delegate: ConnectionWorkerDelegate? = nil) {
        self.workerId = workerId
        self.delegate = delegate
    }

    private func createSession(delegate: URLSessionDataDelegate) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // E2 fix: 30s idle request timeout, very long resource timeout (7 days)
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 604800.0 // 7 days
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    public func downloadSegment(
        segment: Segment,
        url: URL,
        fileWriter: FileWriter,
        planner: SegmentPlanner,
        options: DownloadRequestOptions,
        etag: String?,
        lastModified: String?,
        rateLimiter: RateLimiter? = nil,
        isSingleStream: Bool = false
    ) async throws {
        self.isCancelled = false
        var currentOffset = segment.start + segment.received
        var targetEnd = segment.end

        // Segment already complete
        if targetEnd >= 0 && currentOffset > targetEnd {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // E8 & plan fix: Mandatory identity encoding to prevent URLSession auto-decompression
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        // Range header (only if not in pure single stream mode without range)
        if !isSingleStream {
            if targetEnd >= 0 {
                request.setValue("bytes=\(currentOffset)-\(targetEnd)", forHTTPHeaderField: "Range")
            } else if currentOffset > 0 {
                request.setValue("bytes=\(currentOffset)-", forHTTPHeaderField: "Range")
            }

            // If-Range header for resume validation
            if let etag = etag {
                request.setValue(etag, forHTTPHeaderField: "If-Range")
            } else if let lastMod = lastModified {
                request.setValue(lastMod, forHTTPHeaderField: "If-Range")
            }
        } else if currentOffset > segment.start {
            // Resumed single stream: ask for the remainder. A 200 reply means the server
            // ignored Range (or the file changed) and the stream must restart from byte 0.
            request.setValue("bytes=\(currentOffset)-", forHTTPHeaderField: "Range")
        }

        // Headers from options
        if let ua = options.userAgent {
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
        } else {
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        }

        if let ref = options.referer {
            request.setValue(ref, forHTTPHeaderField: "Referer")
        }

        if let cookieHeader = options.cookieHeader(for: url) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        for (k, v) in options.extraHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let sessionDelegate = WorkerDataDelegate()
        let session = createSession(delegate: sessionDelegate)
        self.session = session

        let (stream, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(AsyncThrowingStream<Data, Error>, HTTPURLResponse), Error>) in
            sessionDelegate.start(request: request, session: session, continuation: continuation)
        }

        self.activeDataTask = sessionDelegate.dataTask

        // E4 Response Validation
        let statusCode = response.statusCode

        if !isSingleStream {
            if statusCode == 200 {
                // If If-Range was provided and 200 received -> server file changed!
                if etag != nil || lastModified != nil {
                    session.invalidateAndCancel()
                    throw DownloadError.fileChanged
                } else {
                    // Range was requested but server returned 200 OK
                    // Do NOT write body into segment offset!
                    session.invalidateAndCancel()
                    throw DownloadError.serverDoesNotSupportRange
                }
            }

            guard statusCode == 206 else {
                session.invalidateAndCancel()
                throw mapHTTPError(response: response)
            }

            // Verify Content-Range header
            if let startOffset = Self.contentRangeStart(response), startOffset != currentOffset {
                session.invalidateAndCancel()
                throw DownloadError.badServerResponse("Content-Range start \(startOffset) does not match requested offset \(currentOffset)")
            }
        } else {
            // Single stream mode
            switch statusCode {
            case 206:
                guard Self.contentRangeStart(response) == currentOffset else {
                    session.invalidateAndCancel()
                    throw DownloadError.badServerResponse("Content-Range does not match resume offset \(currentOffset)")
                }
            case 200:
                if currentOffset > segment.start {
                    // Never append a full body at the resume offset: start over from byte 0
                    if let total = planner.totalBytes, response.expectedContentLength > 0,
                       response.expectedContentLength != total {
                        session.invalidateAndCancel()
                        throw DownloadError.fileChanged
                    }
                    await planner.resetProgress(segmentIdx: segment.idx)
                    currentOffset = segment.start
                }
            default:
                session.invalidateAndCancel()
                throw mapHTTPError(response: response)
            }
        }

        // Buffer: accumulate in 1 MiB chunks
        let bufferCapacity = 1024 * 1024 // 1 MiB
        var buffer = Data()
        buffer.reserveCapacity(bufferCapacity)

        lastSpeedCalcTime = Date()
        bytesSinceLastCalc = 0

        var reachedBoundary = false

        do {
            for try await chunk in stream {
                if isCancelled { break }

                // Check work-stealing boundary (cheap query, does not copy segment array)
                if let currentEnd = await planner.getSegmentEnd(segmentIdx: segment.idx) {
                    targetEnd = currentEnd
                }

                var chunkData = chunk

                // If segment has a defined end boundary, check if this chunk crosses it
                if targetEnd >= 0 {
                    let bytesRemainingInSegment = (targetEnd - currentOffset + 1)
                    if bytesRemainingInSegment <= 0 {
                        reachedBoundary = true
                        break
                    }

                    if Int64(chunkData.count) > bytesRemainingInSegment {
                        // Trim excess bytes stolen by another worker
                        chunkData = chunkData.prefix(Int(bytesRemainingInSegment))
                        reachedBoundary = true
                    }
                }

                buffer.append(chunkData)
                currentOffset += Int64(chunkData.count)
                bytesSinceLastCalc += Int64(chunkData.count)

                // Write when buffer is full (1 MiB)
                if buffer.count >= bufferCapacity {
                    // Backpressure check: suspend data task while writing if needed
                    sessionDelegate.dataTask?.suspend()

                    if let limiter = rateLimiter {
                        await limiter.acquire(bytes: Int64(buffer.count))
                    }

                    let writeOffset = currentOffset - Int64(buffer.count)
                    try await fileWriter.write(data: buffer, at: writeOffset)
                    await planner.updateProgress(segmentIdx: segment.idx, additionalBytes: Int64(buffer.count))

                    updateSpeed()
                    await delegate?.workerDidReceiveBytes(
                        workerId: workerId,
                        segmentIdx: segment.idx,
                        count: Int64(buffer.count),
                        speed: ewmaSpeed
                    )

                    buffer.removeAll(keepingCapacity: true)
                    sessionDelegate.dataTask?.resume()
                }

                if reachedBoundary {
                    sessionDelegate.dataTask?.cancel()
                    break
                }
            }

            // Flush remaining buffer
            if !buffer.isEmpty && !isCancelled {
                if let limiter = rateLimiter {
                    await limiter.acquire(bytes: Int64(buffer.count))
                }

                let writeOffset = currentOffset - Int64(buffer.count)
                try await fileWriter.write(data: buffer, at: writeOffset)
                await planner.updateProgress(segmentIdx: segment.idx, additionalBytes: Int64(buffer.count))

                updateSpeed()
                await delegate?.workerDidReceiveBytes(
                    workerId: workerId,
                    segmentIdx: segment.idx,
                    count: Int64(buffer.count),
                    speed: ewmaSpeed
                )
                buffer.removeAll(keepingCapacity: false)
            }

            session.finishTasksAndInvalidate()
            self.session = nil
            self.activeDataTask = nil

            if !isCancelled {
                await delegate?.workerDidCompleteSegment(workerId: workerId, segmentIdx: segment.idx)
            }
        } catch {
            session.invalidateAndCancel()
            self.session = nil
            self.activeDataTask = nil
            throw error
        }
    }

    private func mapHTTPError(response: HTTPURLResponse) -> DownloadError {
        switch response.statusCode {
        case 404: return .resourceNotFound
        case 410: return .gone
        case 401: return .unauthorized
        case 403: return .forbidden
        case 416: return .rangeNotSatisfiable
        case 429, 503:
            return .rateLimited(statusCode: response.statusCode, retryAfter: Self.retryAfterSeconds(response))
        default: return .serverError(statusCode: response.statusCode)
        }
    }

    /// Start offset of a `Content-Range: bytes <start>-<end>/<total>` header
    static func contentRangeStart(_ response: HTTPURLResponse) -> Int64? {
        guard let cr = response.value(forHTTPHeaderField: "Content-Range"),
              let rangeSpec = cr.split(separator: " ").last,
              let byteRange = rangeSpec.split(separator: "/").first,
              let startStr = byteRange.split(separator: "-").first else { return nil }
        return Int64(startStr)
    }

    /// `Retry-After` as delta-seconds or HTTP-date
    static func retryAfterSeconds(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        if let seconds = TimeInterval(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    private func updateSpeed() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpeedCalcTime)
        if elapsed >= 0.25 {
            let instantaneous = Double(bytesSinceLastCalc) / elapsed
            ewmaSpeed = (alpha * instantaneous) + ((1.0 - alpha) * ewmaSpeed)
            lastSpeedCalcTime = now
            bytesSinceLastCalc = 0
        }
    }

    public func cancel() {
        self.isCancelled = true
        activeDataTask?.cancel()
        session?.invalidateAndCancel()
        session = nil
        activeDataTask = nil
    }
}

// MARK: - WorkerDataDelegate

private final class WorkerDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var responseContinuation: CheckedContinuation<(AsyncThrowingStream<Data, Error>, HTTPURLResponse), Error>?
    private var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    public var dataTask: URLSessionDataTask?

    func start(
        request: URLRequest,
        session: URLSession,
        continuation: CheckedContinuation<(AsyncThrowingStream<Data, Error>, HTTPURLResponse), Error>
    ) {
        lock.lock()
        self.responseContinuation = continuation
        lock.unlock()

        let task = session.dataTask(with: request)
        self.dataTask = task
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            resumeResponseWithError(URLError(.badServerResponse))
            completionHandler(.cancel)
            return
        }

        lock.lock()
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            self.streamContinuation = continuation
        }

        if let cont = responseContinuation {
            responseContinuation = nil
            lock.unlock()
            cont.resume(returning: (stream, httpResponse))
        } else {
            lock.unlock()
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let cont = streamContinuation
        lock.unlock()
        cont?.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let respCont = responseContinuation
        responseContinuation = nil
        let streamCont = streamContinuation
        streamContinuation = nil
        lock.unlock()

        if let error = error {
            if let respCont = respCont {
                respCont.resume(throwing: error)
            } else {
                streamCont?.finish(throwing: error)
            }
        } else {
            streamCont?.finish()
        }
    }

    private func resumeResponseWithError(_ error: Error) {
        lock.lock()
        let cont = responseContinuation
        responseContinuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}
