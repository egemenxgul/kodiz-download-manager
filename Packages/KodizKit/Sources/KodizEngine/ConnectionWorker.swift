import Foundation

public protocol ConnectionWorkerDelegate: AnyObject, Sendable {
    func workerDidReceiveBytes(workerId: Int, segmentIdx: Int, count: Int64, speed: Double) async
    func workerDidCompleteSegment(workerId: Int, segmentIdx: Int) async
    func workerDidFail(workerId: Int, segmentIdx: Int, error: Error) async
}

public actor ConnectionWorker {
    public let workerId: Int
    private let session: URLSession
    private weak var delegate: ConnectionWorkerDelegate?
    private var isCancelled: Bool = false
    private var activeTask: Task<Void, Never>?

    // EWMA speed tracking
    private var ewmaSpeed: Double = 0.0
    private let alpha: Double = 0.2 // Weight for EWMA
    private var lastSpeedCalcTime: Date = Date()
    private var bytesSinceLastCalc: Int64 = 0

    public init(workerId: Int, delegate: ConnectionWorkerDelegate? = nil) {
        self.workerId = workerId
        self.delegate = delegate

        // Ephemeral URLSession isolated per worker to ensure independent TCP connections
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }

    public func downloadSegment(
        segment: Segment,
        url: URL,
        fileWriter: FileWriter,
        planner: SegmentPlanner,
        userAgent: String?,
        referer: String?,
        cookies: [String: String]?,
        extraHeaders: [String: String]?,
        etag: String?,
        lastModified: String?
    ) async {
        self.isCancelled = false
        var currentOffset = segment.start + segment.received
        let targetEnd = segment.end

        // If segment is already complete
        if targetEnd > 0 && currentOffset > targetEnd {
            await delegate?.workerDidCompleteSegment(workerId: workerId, segmentIdx: segment.idx)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        // Range header
        if targetEnd > 0 {
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

        if let ua = userAgent {
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
        }

        if let ref = referer {
            request.setValue(ref, forHTTPHeaderField: "Referer")
        }

        if let cookies = cookies, !cookies.isEmpty {
            let cookieStr = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieStr, forHTTPHeaderField: "Cookie")
        }

        if let extra = extraHeaders {
            for (k, v) in extra {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }

        do {
            let (asyncBytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
                throw URLError(URLError.Code(rawValue: httpResponse.statusCode))
            }

            var buffer = Data()
            buffer.reserveCapacity(64 * 1024)

            lastSpeedCalcTime = Date()
            bytesSinceLastCalc = 0

            for try await byte in asyncBytes {
                if isCancelled { break }

                buffer.append(byte)
                currentOffset += 1
                bytesSinceLastCalc += 1

                if buffer.count >= 64 * 1024 {
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
                }

                // Check if segment end was dynamically shrunk by work-stealing
                let activeSegments = await planner.segments
                if let updatedSeg = activeSegments.first(where: { $0.idx == segment.idx }) {
                    if updatedSeg.end > 0 && currentOffset > updatedSeg.end {
                        break
                    }
                }
            }

            // Flush remaining buffer
            if !buffer.isEmpty {
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
            }

            if !isCancelled {
                await planner.markCompleted(segmentIdx: segment.idx)
                await delegate?.workerDidCompleteSegment(workerId: workerId, segmentIdx: segment.idx)
            }
        } catch {
            if !isCancelled {
                await planner.markFailed(segmentIdx: segment.idx)
                await delegate?.workerDidFail(workerId: workerId, segmentIdx: segment.idx, error: error)
            }
        }
    }

    private func updateSpeed() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpeedCalcTime)
        if elapsed >= 0.5 {
            let instantaneous = Double(bytesSinceLastCalc) / elapsed
            ewmaSpeed = (alpha * instantaneous) + ((1.0 - alpha) * ewmaSpeed)
            lastSpeedCalcTime = now
            bytesSinceLastCalc = 0
        }
    }

    public func cancel() {
        self.isCancelled = true
        session.invalidateAndCancel()
    }
}
