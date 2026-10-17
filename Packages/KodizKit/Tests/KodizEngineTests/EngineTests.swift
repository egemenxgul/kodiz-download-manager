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
}
