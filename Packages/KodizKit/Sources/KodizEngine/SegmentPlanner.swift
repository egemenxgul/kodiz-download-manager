import Foundation

public struct Segment: Codable, Sendable, Identifiable {
    public var id: Int { idx }
    public let idx: Int
    public let start: Int64
    public var end: Int64 // -1 for open-ended / unknown length
    public var received: Int64
    public var state: SegmentState
    public var attempts: Int
    public var nextAttemptAt: Date?
    public var workerId: Int?

    public var remaining: Int64 {
        if end < 0 { return -1 }
        return max(0, (end - start + 1) - received)
    }

    public var isCompleted: Bool {
        if end < 0 {
            // E5 fix: Open-ended segment is completed ONLY when explicitly marked completed (at EOF)
            return state == .completed
        }
        return (received >= (end - start + 1)) || (state == .completed)
    }

    public init(
        idx: Int,
        start: Int64,
        end: Int64,
        received: Int64 = 0,
        state: SegmentState = .pending,
        attempts: Int = 0,
        nextAttemptAt: Date? = nil,
        workerId: Int? = nil
    ) {
        self.idx = idx
        self.start = start
        self.end = end
        self.received = received
        self.state = state
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
        self.workerId = workerId
    }
}

public enum SegmentState: String, Codable, Sendable {
    case pending
    case downloading
    case completed
    case failed
}

public enum SegmentFailureAction: Sendable {
    case retry(delay: TimeInterval)
    case fatal(Error)
}

public actor SegmentPlanner {
    public static let minSegmentSize: Int64 = 1024 * 1024 // 1 MiB
    public static let alignment: Int64 = 64 * 1024 // 64 KiB
    public static let maxAttemptsPerSegment: Int = 10

    public private(set) var segments: [Segment] = []
    public let totalBytes: Int64?
    private var nextIdx: Int = 0

    public init(totalBytes: Int64?, initialConnections: Int = 8) {
        self.totalBytes = totalBytes
        self.segments = Self.createInitialPlan(totalBytes: totalBytes, connections: initialConnections)
        self.nextIdx = self.segments.count
    }

    public init(existingSegments: [Segment], totalBytes: Int64?) {
        self.totalBytes = totalBytes
        self.segments = existingSegments
        self.nextIdx = (existingSegments.map(\.idx).max() ?? -1) + 1
    }

    /// Creates initial equal-sized segment distribution
    public static func createInitialPlan(totalBytes: Int64?, connections: Int) -> [Segment] {
        guard let total = totalBytes, total > 0 else {
            // Unknown size or non-range download: single open-ended segment (end = -1)
            return [Segment(idx: 0, start: 0, end: -1, received: 0, state: .pending)]
        }

        let maxCount = max(1, Int(ceil(Double(total) / Double(minSegmentSize))))
        let actualCount = min(connections, maxCount)

        var plan: [Segment] = []
        let chunkSize = total / Int64(actualCount)

        for i in 0..<actualCount {
            let start = Int64(i) * chunkSize
            let end = (i == actualCount - 1) ? (total - 1) : (start + chunkSize - 1)
            plan.append(Segment(idx: i, start: start, end: end, received: 0, state: .pending))
        }

        return plan
    }

    /// Retrieves next available pending segment (respecting backoff), or attempts work-stealing
    public func allocateWork(workerId: Int? = nil) -> Segment? {
        let now = Date()

        // 1. Check for ready pending segments
        if let index = segments.firstIndex(where: { seg in
            seg.state == .pending &&
            !seg.isCompleted &&
            (seg.nextAttemptAt == nil || seg.nextAttemptAt! <= now) &&
            seg.attempts < Self.maxAttemptsPerSegment
        }) {
            segments[index].state = .downloading
            segments[index].workerId = workerId
            return segments[index]
        }

        // 2. Otherwise attempt work-stealing from another downloading segment
        return stealWork(workerId: workerId)
    }

    /// Time until the earliest pending segment becomes eligible for retry
    public func timeUntilNextAttempt() -> TimeInterval? {
        let now = Date()
        let pendingDelays = segments
            .filter { $0.state == .pending && !$0.isCompleted }
            .compactMap { $0.nextAttemptAt }
            .map { $0.timeIntervalSince(now) }

        guard !pendingDelays.isEmpty else { return nil }
        let minDelay = pendingDelays.min() ?? 0
        return max(0, minDelay)
    }

    /// Work stealing: find the downloading segment with largest remaining bytes and split it
    public func stealWork(workerId: Int? = nil) -> Segment? {
        // Find segment with greatest remaining bytes
        guard let candidateIndex = segments.indices
            .filter({ segments[$0].state == .downloading && segments[$0].end > 0 })
            .max(by: { segments[$0].remaining < segments[$1].remaining }) else {
            return nil
        }

        let donor = segments[candidateIndex]
        let remaining = donor.remaining

        // Only split if remaining bytes is at least 2x min segment size
        guard remaining >= 2 * Self.minSegmentSize else {
            return nil
        }

        let currentPos = donor.start + donor.received
        let halfRemaining = remaining / 2
        var splitPoint = currentPos + halfRemaining

        // Align splitPoint to 64 KiB
        splitPoint = (splitPoint / Self.alignment) * Self.alignment
        guard splitPoint > currentPos && splitPoint < donor.end else {
            return nil
        }

        let oldEnd = donor.end
        // Truncate donor end
        segments[candidateIndex].end = splitPoint - 1

        // Create new segment for stolen half
        let newSegment = Segment(
            idx: nextIdx,
            start: splitPoint,
            end: oldEnd,
            received: 0,
            state: .downloading,
            workerId: workerId
        )
        nextIdx += 1
        segments.append(newSegment)

        return newSegment
    }

    /// Cheap atomic lookup of current end for boundary checks during work stealing (Fixes E1)
    public func getSegmentEnd(segmentIdx: Int) -> Int64? {
        segments.first(where: { $0.idx == segmentIdx })?.end
    }

    /// Updates received bytes for a segment (called once per buffer)
    public func updateProgress(segmentIdx: Int, additionalBytes: Int64) {
        guard let index = segments.firstIndex(where: { $0.idx == segmentIdx }) else { return }
        segments[index].received += additionalBytes
        if segments[index].end > 0 && segments[index].received >= (segments[index].end - segments[index].start + 1) {
            segments[index].state = .completed
        }
    }

    /// Explicitly marks a segment as completed (called at EOF or when segment range finishes)
    public func markCompleted(segmentIdx: Int) {
        guard let index = segments.firstIndex(where: { $0.idx == segmentIdx }) else { return }
        segments[index].state = .completed
        segments[index].workerId = nil
    }

    /// Marks a segment as failed with retry or fatal decision (Fixes E3)
    public func markFailed(segmentIdx: Int, error: Error, retryAfter: TimeInterval? = nil) -> SegmentFailureAction {
        guard let index = segments.firstIndex(where: { $0.idx == segmentIdx }) else {
            return .fatal(DownloadError.unknown("Segment index \(segmentIdx) not found"))
        }

        segments[index].workerId = nil

        // 1. Check for permanent error
        if let dlError = error as? DownloadError, dlError.isPermanent {
            segments[index].state = .failed
            return .fatal(dlError)
        }

        // 2. Increment attempts
        segments[index].attempts += 1
        let attempts = segments[index].attempts

        if attempts >= Self.maxAttemptsPerSegment {
            segments[index].state = .failed
            let fatalErr = DownloadError.maxAttemptsExceeded(segmentIdx: segmentIdx)
            return .fatal(fatalErr)
        }

        // 3. Transient error: calculate backoff
        let delay: TimeInterval
        if let retryAfter = retryAfter, retryAfter > 0 {
            delay = retryAfter
        } else {
            // Jittered exponential backoff: 1, 2, 4, 8, 16, 32, max 60s
            let base = pow(2.0, Double(min(attempts - 1, 6)))
            let jitter = Double.random(in: 0.0...0.5)
            delay = min(60.0, base + jitter)
        }

        segments[index].state = .pending
        segments[index].nextAttemptAt = Date().addingTimeInterval(delay)
        return .retry(delay: delay)
    }

    /// Total downloaded bytes across all segments
    public var totalDownloaded: Int64 {
        segments.reduce(0) { $0 + $1.received }
    }

    /// Checks if all segments are completed
    public var isAllCompleted: Bool {
        guard !segments.isEmpty else { return false }
        return segments.allSatisfy { $0.isCompleted }
    }

    /// Resets downloading segments back to pending (e.g. for pause/resume)
    public func resetDownloadingToPending() {
        for i in segments.indices {
            if segments[i].state == .downloading {
                segments[i].state = .pending
                segments[i].workerId = nil
            }
        }
    }
}
