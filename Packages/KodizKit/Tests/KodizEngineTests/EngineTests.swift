import XCTest
@testable import KodizEngine

final class EngineTests: XCTestCase {
    // MARK: - FileNameParser Tests

    func testFileNameParserRFC5987() {
        let cd = "attachment; filename*=UTF-8''ubuntu-24.04%20desktop.iso"
        let name = FileNameParser.resolveFileName(
            contentDisposition: cd,
            url: URL(string: "https://example.com/download")!,
            mimeType: nil
        )
        XCTAssertEqual(name, "ubuntu-24.04 desktop.iso")
    }

    func testFileNameParserQuoted() {
        let cd = "attachment; filename=\"archive_2026.tar.gz\""
        let name = FileNameParser.resolveFileName(
            contentDisposition: cd,
            url: URL(string: "https://example.com/dl")!,
            mimeType: nil
        )
        XCTAssertEqual(name, "archive_2026.tar.gz")
    }

    func testFileNameSanitization() {
        let dangerous = "path/with/slashes:and:colons\0null.zip"
        let sanitized = FileNameParser.sanitize(dangerous)
        XCTAssertFalse(sanitized.contains("/"))
        XCTAssertFalse(sanitized.contains(":"))
        XCTAssertFalse(sanitized.contains("\0"))
    }

    // MARK: - SegmentPlanner Tests

    func testInitialSegmentPartition() {
        let total: Int64 = 80 * 1024 * 1024 // 80 MB
        let segments = SegmentPlanner.createInitialPlan(totalBytes: total, connections: 8)

        XCTAssertEqual(segments.count, 8)
        XCTAssertEqual(segments[0].start, 0)
        XCTAssertEqual(segments[7].end, total - 1)

        // Verify segments are contiguous
        for i in 0..<7 {
            XCTAssertEqual(segments[i].end + 1, segments[i + 1].start)
        }
    }

    func testWorkStealing() async {
        let total: Int64 = 20 * 1024 * 1024 // 20 MB
        let planner = SegmentPlanner(totalBytes: total, initialConnections: 1)

        let initialWork = await planner.allocateWork()
        XCTAssertNotNil(initialWork)
        XCTAssertEqual(initialWork?.start, 0)
        XCTAssertEqual(initialWork?.end, total - 1)

        // Steal work
        let stolenWork = await planner.stealWork()
        XCTAssertNotNil(stolenWork)

        let segments = await planner.segments
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].end + 1, segments[1].start)
        XCTAssertEqual(segments[1].end, total - 1)
        XCTAssertTrue(segments[1].start % SegmentPlanner.alignment == 0, "Split must align to 64 KiB")
    }

    // MARK: - AIMDController Tests

    func testAIMDController() async {
        let aimd = AIMDController(initialConnections: 4, minConnections: 1, maxConnections: 16)
        var conns = await aimd.currentConnections
        XCTAssertEqual(conns, 4)

        // Congestion: multiplicative decrease
        conns = await aimd.recordCongestion()
        XCTAssertEqual(conns, 2)

        conns = await aimd.recordCongestion()
        XCTAssertEqual(conns, 1) // Down to min
    }

    // MARK: - New SegmentPlanner Tests

    func testFailedSegmentReallocation() async {
        let planner = SegmentPlanner(totalBytes: 10 * 1024 * 1024, initialConnections: 2)
        let work = await planner.allocateWork()
        XCTAssertNotNil(work)
        let idx = work!.idx

        // Simulate transient error with 0 delay for instant reallocation test
        let action = await planner.markFailed(segmentIdx: idx, error: URLError(.timedOut), retryAfter: 0.001)
        if case .retry = action {
            // Expected
        } else {
            XCTFail("Transient error should trigger retry")
        }

        // Wait brief delay for nextAttemptAt
        try? await Task.sleep(nanoseconds: 10_000_000)

        // allocateWork should successfully reallocate the failed segment!
        let reallocated = await planner.allocateWork()
        XCTAssertNotNil(reallocated, "Failed segment must be reallocated once backoff passes")
        XCTAssertEqual(reallocated?.idx, idx)
        XCTAssertEqual(reallocated?.attempts, 1)
    }

    func testOpenEndedSegmentCompletion() async {
        let planner = SegmentPlanner(totalBytes: nil, initialConnections: 1)
        let segs = await planner.segments
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].end, -1)

        // E5 fix: Open-ended segment with received bytes is NOT completed until EOF
        await planner.updateProgress(segmentIdx: 0, additionalBytes: 1024 * 1024)
        var updated = await planner.segments[0]
        XCTAssertFalse(updated.isCompleted, "Open-ended segment must NOT be completed before EOF")

        // Once markCompleted is called at EOF:
        await planner.markCompleted(segmentIdx: 0)
        updated = await planner.segments[0]
        XCTAssertTrue(updated.isCompleted)
    }

    func testBoundaryTrimmingAndCheapQuery() async {
        let total: Int64 = 40 * 1024 * 1024 // 40 MB
        let planner = SegmentPlanner(totalBytes: total, initialConnections: 1)

        let initial = await planner.allocateWork()
        XCTAssertNotNil(initial)
        let initialEnd = await planner.getSegmentEnd(segmentIdx: 0)
        XCTAssertEqual(initialEnd, total - 1)

        // Stolen work shrinks the donor's end
        let stolen = await planner.stealWork()
        XCTAssertNotNil(stolen)

        let newEnd0 = await planner.getSegmentEnd(segmentIdx: 0)
        XCTAssertNotNil(newEnd0)
        XCTAssertTrue(newEnd0! < total - 1)
        XCTAssertEqual(newEnd0! + 1, stolen!.start)
    }

    func testMaxAttemptsExceeded() async {
        let planner = SegmentPlanner(totalBytes: 5 * 1024 * 1024, initialConnections: 1)
        _ = await planner.allocateWork()

        for i in 1...9 {
            let action = await planner.markFailed(segmentIdx: 0, error: URLError(.networkConnectionLost), retryAfter: 0.0)
            if case .retry = action {} else {
                XCTFail("Attempt \(i) should retry")
            }
        }

        // 10th attempt should exceed max attempts and become fatal
        let finalAction = await planner.markFailed(segmentIdx: 0, error: URLError(.networkConnectionLost), retryAfter: 0.0)
        if case .fatal(let err) = finalAction {
            if let dlErr = err as? DownloadError, case .maxAttemptsExceeded(let idx) = dlErr {
                XCTAssertEqual(idx, 0)
            } else {
                XCTFail("Expected maxAttemptsExceeded error")
            }
        } else {
            XCTFail("10th failure must be fatal")
        }
    }
}
