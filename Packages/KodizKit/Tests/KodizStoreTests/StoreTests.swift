import XCTest
@testable import KodizStore
import KodizEngine

final class StoreTests: XCTestCase {
    func testDatabaseInitializationAndMigrations() throws {
        let db = try KodizDatabase(inMemory: true)

        let initialDownloads = try db.fetchAllDownloads()
        XCTAssertEqual(initialDownloads.count, 0)

        // Verify default categories are seeded
        let categories = try db.dbQueue.read { db in
            try CategoryRecord.fetchAll(db)
        }
        XCTAssertGreaterThan(categories.count, 0)
        XCTAssertTrue(categories.contains(where: { $0.id == "video" }))
        XCTAssertTrue(categories.contains(where: { $0.id == "archive" }))
    }

    func testSaveAndFetchDownload() throws {
        let db = try KodizDatabase(inMemory: true)

        let download = DownloadRecord(
            url: "https://example.com/test.zip",
            fileName: "test.zip",
            destDir: "/tmp",
            tempPath: "/tmp/test.zip.kodizpart",
            totalBytes: 50000000,
            status: .downloading
        )

        try db.saveDownload(download)

        let fetched = try db.fetchDownload(id: download.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.fileName, "test.zip")
        XCTAssertEqual(fetched?.totalBytes, 50000000)
        XCTAssertEqual(fetched?.status, .downloading)

        // Update progress
        try db.updateDownloadProgress(id: download.id, downloadedBytes: 25000000, status: .downloading)
        let updated = try db.fetchDownload(id: download.id)
        XCTAssertEqual(updated?.downloadedBytes, 25000000)
    }

    func testCheckpointSinkAndSegmentFetching() async throws {
        let db = try KodizDatabase(inMemory: true)

        let download = DownloadRecord(
            url: "https://example.com/test.zip",
            fileName: "test.zip",
            destDir: "/tmp",
            tempPath: "/tmp/test.zip.kodizpart",
            totalBytes: 1000,
            status: .downloading
        )
        try db.saveDownload(download)

        let segments = [
            Segment(idx: 0, start: 0, end: 499, received: 250, state: .downloading),
            Segment(idx: 1, start: 500, end: 999, received: 500, state: .completed)
        ]

        try await db.checkpoint(id: download.id, segments: segments, downloadedBytes: 750)

        let fetched = try db.fetchDownload(id: download.id)
        XCTAssertEqual(fetched?.downloadedBytes, 750)

        let fetchedSegments = try db.fetchEngineSegments(for: download.id)
        XCTAssertEqual(fetchedSegments.count, 2)
        XCTAssertEqual(fetchedSegments[0].idx, 0)
        XCTAssertEqual(fetchedSegments[0].received, 250)
        XCTAssertEqual(fetchedSegments[0].state, .downloading)
        XCTAssertEqual(fetchedSegments[1].idx, 1)
        XCTAssertEqual(fetchedSegments[1].received, 500)
        XCTAssertEqual(fetchedSegments[1].state, .completed)

        // Delete download cascades to segments
        try db.deleteDownload(id: download.id)
        XCTAssertNil(try db.fetchDownload(id: download.id))
        XCTAssertEqual(try db.fetchSegments(for: download.id).count, 0)
    }
}
