import Foundation

public struct Segment: Codable, Sendable, Identifiable {
    public var id: Int { idx }
    public let idx: Int
    public let start: Int64
    public var end: Int64
    public var received: Int64
    public var state: SegmentState

    public var remaining: Int64 {
        max(0, (end - start + 1) - received)
    }

    public var isCompleted: Bool {
        received >= (end - start + 1)
    }

    public init(idx: Int, start: Int64, end: Int64, received: Int64 = 0, state: SegmentState = .pending) {
        self.idx = idx
        self.start = start
        self.end = end
        self.received = received
        self.state = state
    }
}

public enum SegmentState: String, Codable, Sendable {
    case pending
    case downloading
    case completed
    case failed
}

public actor SegmentPlanner {
    public static let minSegmentSize: Int64 = 1024 * 1024 // 1 MiB
    public static let alignment: Int64 = 64 * 1024 // 64 KiB

    private(set) public var segments: [Segment] = []
    private let totalBytes: Int64?
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
            // Unknown size or non-range download: single open-ended segment
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

    /// Retrieves the next available pending segment, or attempts work-stealing if none pending
    public func allocateWork() -> Segment? {
        // First check for pending segments
        if let index = segments.firstIndex(where: { $0.state == .pending && !$0.isCompleted }) {
            segments[index].state = .downloading
            return segments[index]
        }

        // Otherwise, attempt work stealing
        return stealWork()
    }

    /// Work stealing: find the downloading segment with largest remaining bytes and split it
    public func stealWork() -> Segment? {
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
            state: .downloading
        )
        nextIdx += 1
        segments.append(newSegment)

        return newSegment
    }

    /// Updates received bytes for a segment
    public func updateProgress(segmentIdx: Int, additionalBytes: Int64) {
        guard let index = segments.firstIndex(where: { $0.idx == segmentIdx }) else { return }
        segments[index].received += additionalBytes
        if segments[index].end > 0 && segments[index].received >= (segments[index].end - segments[index].start + 1) {
            segments[index].state = .completed
        }
    }

    /// Marks a segment as completed
    public func markCompleted(segmentIdx: Int) {
        guard let index = segments.firstIndex(where: { $0.idx == segmentIdx }) else { return }
        segments[index].state = .completed
    }

    /// Marks a segment as failed so it can be retried
    public func markFailed(segmentIdx: Int) {
        guard let index = segments.firstIndex(where: { $0.idx == segmentIdx }) else { return }
        segments[index].state = .failed
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
}
