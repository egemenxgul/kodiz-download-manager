import Foundation

public struct DownloadProgress: Sendable {
    public let downloadedBytes: Int64
    public let totalBytes: Int64?
    public let speed: Double
    public let segments: [Segment]

    public var percentage: Double {
        guard let total = totalBytes, total > 0 else { return 0.0 }
        return min(100.0, (Double(downloadedBytes) / Double(total)) * 100.0)
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

    private var workers: [ConnectionWorker] = []
    private var planner: SegmentPlanner?
    private var fileWriter: FileWriter?
    private var probeResult: ProbeResult?
    private weak var delegate: DownloadEngineDelegate?

    private var lastCheckpointTime: Date = Date()
    private var bytesSinceCheckpoint: Int64 = 0
    private var workerSpeeds: [Int: Double] = [:]

    public init(
        id: UUID = UUID(),
        url: URL,
        destinationDirectory: URL,
        preferredFileName: String? = nil,
        delegate: DownloadEngineDelegate? = nil
    ) {
        self.id = id
        self.originalURL = url
        self.destinationDirectory = destinationDirectory
        self.fileName = preferredFileName ?? "download"
        self.delegate = delegate
    }

    public func start(connections: Int = 8) async throws {
        self.isRunning = true
        self.isPaused = false

        // 1. Probe
        let probe = DownloadProbe()
        let result = try await probe.probe(url: originalURL)
        self.probeResult = result
        self.totalBytes = result.totalBytes

        if self.fileName == "download" {
            self.fileName = FileNameParser.uniqueFileName(destDir: destinationDirectory, preferredName: result.suggestedFileName)
        }

        // 2. File Writer
        let writer = FileWriter(
            destinationDirectory: destinationDirectory,
            fileName: fileName,
            totalBytes: result.totalBytes
        )
        try await writer.open()
        self.fileWriter = writer

        // 3. Segment Planner
        let segmentPlanner = SegmentPlanner(totalBytes: result.totalBytes, initialConnections: connections)
        self.planner = segmentPlanner

        // 4. Spawn Workers
        workers.removeAll()
        let actualConnections = await segmentPlanner.segments.count

        for i in 0..<actualConnections {
            let worker = ConnectionWorker(workerId: i, delegate: self)
            workers.append(worker)
            spawnWorkerTask(worker: worker)
        }
    }

    private func spawnWorkerTask(worker: ConnectionWorker) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.runWorker(worker)
        }
    }

    private func runWorker(_ worker: ConnectionWorker) async {
        guard let planner = self.planner, let writer = self.fileWriter, let probe = self.probeResult else {
            return
        }

        while isRunning && !isPaused {
            guard let segment = await planner.allocateWork() else {
                break
            }

            await worker.downloadSegment(
                segment: segment,
                url: probe.finalURL,
                fileWriter: writer,
                planner: planner,
                userAgent: nil,
                referer: nil,
                cookies: nil,
                extraHeaders: nil,
                etag: probe.etag,
                lastModified: probe.lastModified
            )
        }

        await checkOverallCompletion()
    }

    public func workerDidReceiveBytes(workerId: Int, segmentIdx: Int, count: Int64, speed: Double) async {
        workerSpeeds[workerId] = speed
        bytesSinceCheckpoint += count

        let now = Date()
        if now.timeIntervalSince(lastCheckpointTime) >= 2.0 || bytesSinceCheckpoint >= 16 * 1024 * 1024 {
            try? await fileWriter?.sync()
            lastCheckpointTime = now
            bytesSinceCheckpoint = 0
        }

        guard let planner = self.planner else { return }
        let totalDownloaded = await planner.totalDownloaded
        let totalSpeed = workerSpeeds.values.reduce(0.0, +)
        let segments = await planner.segments

        let progress = DownloadProgress(
            downloadedBytes: totalDownloaded,
            totalBytes: totalBytes,
            speed: totalSpeed,
            segments: segments
        )
        await delegate?.downloadDidUpdateProgress(progress)
    }

    public func workerDidCompleteSegment(workerId: Int, segmentIdx: Int) async {
        guard let worker = workers.first(where: { $0.workerId == workerId }) else { return }
        // Worker attempts to take next segment or steal work
        spawnWorkerTask(worker: worker)
    }

    public func workerDidFail(workerId: Int, segmentIdx: Int, error: Error) async {
        // If not paused or cancelled, wait a bit and retry
        if isRunning && !isPaused {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let worker = workers.first(where: { $0.workerId == workerId }) else { return }
            spawnWorkerTask(worker: worker)
        }
    }

    private func checkOverallCompletion() async {
        guard let planner = self.planner, let writer = self.fileWriter else { return }
        let completed = await planner.isAllCompleted

        if completed && isRunning {
            isRunning = false
            do {
                let finalURL = try await writer.finalize()
                await delegate?.downloadDidComplete(finalURL: finalURL)
            } catch {
                await delegate?.downloadDidFail(error: error)
            }
        }
    }

    public func pause() async {
        isPaused = true
        for worker in workers {
            await worker.cancel()
        }
        try? await fileWriter?.sync()
    }

    public func cancel() async {
        isRunning = false
        for worker in workers {
            await worker.cancel()
        }
        await fileWriter?.closeWithoutFinalizing()
    }
}
