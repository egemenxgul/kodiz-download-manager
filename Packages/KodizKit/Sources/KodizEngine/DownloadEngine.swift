import Foundation

public struct DownloadProgress: Sendable {
    public let downloadedBytes: Int64
    public let totalBytes: Int64?
    public let speed: Double
    public let workerSpeeds: [Int: Double]
    public let segments: [Segment]

    public var percentage: Double {
        guard let total = totalBytes, total > 0 else { return 0.0 }
        return min(100.0, (Double(downloadedBytes) / Double(total)) * 100.0)
    }

    public init(
        downloadedBytes: Int64,
        totalBytes: Int64?,
        speed: Double,
        workerSpeeds: [Int: Double] = [:],
        segments: [Segment] = []
    ) {
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.speed = speed
        self.workerSpeeds = workerSpeeds
        self.segments = segments
    }
}

public protocol DownloadEngineDelegate: AnyObject, Sendable {
    func downloadDidUpdateProgress(_ progress: DownloadProgress) async
    func downloadDidComplete(finalURL: URL) async
    func downloadDidFail(error: Error) async
}

public actor DownloadEngine: ConnectionWorkerDelegate {
    public let id: UUID
    public let originalURL: URL
    public let destinationDirectory: URL
    public private(set) var fileName: String
    public private(set) var totalBytes: Int64?
    public private(set) var isRunning: Bool = false
    public private(set) var isPaused: Bool = false
    public private(set) var finalURL: URL?

    private var options: DownloadRequestOptions
    public private(set) var savedETag: String?
    private var workers: [Int: ConnectionWorker] = [:]
    private var planner: SegmentPlanner?
    private var fileWriter: FileWriter?
    private var probeResult: ProbeResult?
    private var rateLimiter: RateLimiter?
    private var aimd: AIMDController?
    private weak var delegate: DownloadEngineDelegate?
    private weak var checkpointSink: DownloadCheckpointSink?

    // Checkpoint & Progress tracking
    private var lastCheckpointTime: Date = Date()
    private var bytesSinceCheckpoint: Int64 = 0
    private var lastProgressNotifyTime: Date = Date.distantPast
    private var workerSpeeds: [Int: Double] = [:]
    private var fatalError: Error?
    private var isSingleStream: Bool = false

    public init(
        id: UUID = UUID(),
        url: URL,
        destinationDirectory: URL,
        preferredFileName: String? = nil,
        savedETag: String? = nil,
        options: DownloadRequestOptions = DownloadRequestOptions(),
        delegate: DownloadEngineDelegate? = nil,
        checkpointSink: DownloadCheckpointSink? = nil
    ) {
        self.id = id
        self.originalURL = url
        self.destinationDirectory = destinationDirectory
        self.fileName = preferredFileName ?? "download"
        self.savedETag = savedETag
        self.options = options
        self.delegate = delegate
        self.checkpointSink = checkpointSink

        if options.speedLimit > 0 {
            self.rateLimiter = RateLimiter(bytesPerSecond: options.speedLimit)
        }
    }

    public func setSpeedLimit(_ bytesPerSecond: Int64) async {
        options.speedLimit = bytesPerSecond
        if bytesPerSecond > 0 {
            if let limiter = rateLimiter {
                await limiter.setLimit(bytesPerSecond)
            } else {
                rateLimiter = RateLimiter(bytesPerSecond: bytesPerSecond)
            }
        } else {
            await rateLimiter?.setLimit(0)
        }
    }

    public func start(connections: Int = 8, existingSegments: [Segment]? = nil, savedETag: String? = nil) async throws {
        guard !isRunning else { return }
        self.isRunning = true
        self.isPaused = false
        self.fatalError = nil
        if let sETag = savedETag {
            self.savedETag = sETag
        }

        // 1. Probe (if not already probed)
        let probe: ProbeResult
        if let existingProbe = self.probeResult {
            probe = existingProbe
        } else {
            let p = DownloadProbe()
            probe = try await p.probe(url: originalURL, options: options)
            self.probeResult = probe
        }

        // If savedETag was provided and probe returned a different ETag -> file changed!
        if let originalETag = self.savedETag, let newETag = probe.etag, originalETag != newETag {
            self.isRunning = false
            await delegate?.downloadDidFail(error: DownloadError.fileChanged)
            throw DownloadError.fileChanged
        }

        if self.savedETag == nil {
            self.savedETag = probe.etag
        }

        self.totalBytes = probe.totalBytes

        if self.fileName == "download" || self.fileName.isEmpty {
            self.fileName = FileNameParser.uniqueFileName(destDir: destinationDirectory, preferredName: probe.suggestedFileName)
        }

        // 2. Determine download mode: Multi-segment vs Single-stream
        if probe.supportsRange && probe.totalBytes != nil && probe.totalBytes! > 0 {
            self.isSingleStream = false
        } else {
            // Norange, unknown length, or server without range support: single stream mode
            self.isSingleStream = true
        }

        // 3. File Writer
        let writer = FileWriter(
            destinationDirectory: destinationDirectory,
            fileName: fileName,
            totalBytes: probe.totalBytes
        )
        try await writer.open()
        self.fileWriter = writer

        // 4. Segment Planner
        let segmentPlanner: SegmentPlanner
        if let existing = existingSegments, !existing.isEmpty {
            segmentPlanner = SegmentPlanner(existingSegments: existing, totalBytes: probe.totalBytes)
            await segmentPlanner.resetDownloadingToPending()
        } else {
            let connCount = isSingleStream ? 1 : connections
            segmentPlanner = SegmentPlanner(totalBytes: probe.totalBytes, initialConnections: connCount)
        }
        self.planner = segmentPlanner

        // 5. AIMD Controller
        self.aimd = AIMDController(initialConnections: isSingleStream ? 1 : connections, minConnections: 1, maxConnections: 16)

        // 6. Launch structured worker task group (Fixes E6)
        let effectiveConnections = isSingleStream ? 1 : connections

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<effectiveConnections {
                group.addTask {
                    await self.runWorkerLoop(workerId: i)
                }
            }
            await group.waitForAll()
        }

        // 7. Check final outcome after task group finishes
        await handleDownloadFinish()
    }

    private func runWorkerLoop(workerId: Int) async {
        guard let planner = self.planner,
              let writer = self.fileWriter,
              let probe = self.probeResult else { return }

        let worker = ConnectionWorker(workerId: workerId, delegate: self)
        workers[workerId] = worker

        while isRunning && !isPaused {
            // Check if any fatal error stopped the download
            if fatalError != nil { break }

            guard let segment = await planner.allocateWork(workerId: workerId) else {
                // If all segments completed, exit worker loop
                if await planner.isAllCompleted {
                    break
                }

                // If some segments are in backoff retry delay, sleep until retry time
                if let waitTime = await planner.timeUntilNextAttempt() {
                    let sleepNs = UInt64(min(1.0, waitTime) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: max(10_000_000, sleepNs))
                    continue
                } else {
                    // No pending work and no future retry -> work finished for this worker
                    break
                }
            }

            do {
                try await worker.downloadSegment(
                    segment: segment,
                    url: probe.finalURL,
                    fileWriter: writer,
                    planner: planner,
                    options: options,
                    etag: self.savedETag ?? probe.etag,
                    lastModified: probe.lastModified,
                    rateLimiter: rateLimiter,
                    isSingleStream: isSingleStream
                )
                await planner.markCompleted(segmentIdx: segment.idx)
            } catch {
                if isPaused || !isRunning { break }

                // Check for server error retry-after or congestion
                var retryAfter: TimeInterval? = nil
                if case let DownloadError.serverError(code) = error {
                    if code == 429 || code == 503 {
                        retryAfter = 1.0
                        _ = await aimd?.recordCongestion(retryAfterSeconds: 1.0)
                    }
                }

                let action = await planner.markFailed(segmentIdx: segment.idx, error: error, retryAfter: retryAfter)
                switch action {
                case .fatal(let err):
                    self.fatalError = err
                    self.isRunning = false
                    return
                case .retry:
                    break
                }
            }
        }
    }

    private func handleDownloadFinish() async {
        if isPaused {
            return
        }

        if let error = fatalError {
            isRunning = false
            await delegate?.downloadDidFail(error: error)
            return
        }

        guard let planner = self.planner, let writer = self.fileWriter else { return }

        if await planner.isAllCompleted {
            isRunning = false
            do {
                // Step 1: fsync to disk
                try await writer.sync()

                // Step 2: Final checkpoint
                let finalDownloaded = await planner.totalDownloaded
                let finalSegments = await planner.segments
                try? await checkpointSink?.checkpoint(id: id, segments: finalSegments, downloadedBytes: finalDownloaded)

                // Step 3: Atomic rename from .kodizpart to target file
                let finalPath = try await writer.finalize()
                self.finalURL = finalPath

                // Step 4: Final progress update
                let progress = DownloadProgress(
                    downloadedBytes: finalDownloaded,
                    totalBytes: totalBytes ?? finalDownloaded,
                    speed: 0.0,
                    workerSpeeds: [:],
                    segments: finalSegments
                )
                await delegate?.downloadDidUpdateProgress(progress)
                await delegate?.downloadDidComplete(finalURL: finalPath)
            } catch {
                await delegate?.downloadDidFail(error: error)
            }
        } else if !isRunning {
            // Cancelled or stopped
        }
    }

    public func workerDidReceiveBytes(workerId: Int, segmentIdx: Int, count: Int64, speed: Double) async {
        workerSpeeds[workerId] = speed
        bytesSinceCheckpoint += count

        let now = Date()

        // 1. Checkpoint condition: every 2.0s or 16 MiB
        if now.timeIntervalSince(lastCheckpointTime) >= 2.0 || bytesSinceCheckpoint >= 16 * 1024 * 1024 {
            try? await fileWriter?.sync()
            if let planner = self.planner {
                let segs = await planner.segments
                let downloaded = await planner.totalDownloaded
                try? await checkpointSink?.checkpoint(id: id, segments: segs, downloadedBytes: downloaded)
            }
            lastCheckpointTime = now
            bytesSinceCheckpoint = 0
        }

        // 2. Progress reporting: max 4 Hz (every 250 ms)
        if now.timeIntervalSince(lastProgressNotifyTime) >= 0.25 {
            guard let planner = self.planner else { return }
            let totalDownloaded = await planner.totalDownloaded
            let totalSpeed = workerSpeeds.values.reduce(0.0, +)
            let segments = await planner.segments

            let progress = DownloadProgress(
                downloadedBytes: totalDownloaded,
                totalBytes: totalBytes,
                speed: totalSpeed,
                workerSpeeds: workerSpeeds,
                segments: segments
            )
            lastProgressNotifyTime = now
            await delegate?.downloadDidUpdateProgress(progress)
        }
    }

    public func workerDidCompleteSegment(workerId: Int, segmentIdx: Int) async {
        workerSpeeds[workerId] = 0.0
    }

    public func pause() async -> [Segment] {
        isPaused = true
        isRunning = false

        for (_, worker) in workers {
            await worker.cancel()
        }
        workers.removeAll()

        // Sync to disk
        try? await fileWriter?.sync()

        // Checkpoint sink
        var savedSegments: [Segment] = []
        if let planner = self.planner {
            await planner.resetDownloadingToPending()
            savedSegments = await planner.segments
            let downloaded = await planner.totalDownloaded
            try? await checkpointSink?.checkpoint(id: id, segments: savedSegments, downloadedBytes: downloaded)
        }

        await fileWriter?.closeWithoutFinalizing()
        return savedSegments
    }

    public func cancel() async {
        isRunning = false
        isPaused = false

        for (_, worker) in workers {
            await worker.cancel()
        }
        workers.removeAll()

        // Remove .kodizpart
        await fileWriter?.deleteTempFile()
        fileWriter = nil
    }

    public func getSegments() async -> [Segment] {
        guard let planner = self.planner else { return [] }
        return await planner.segments
    }
}
