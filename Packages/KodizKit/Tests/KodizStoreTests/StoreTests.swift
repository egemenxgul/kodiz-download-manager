import XCTest
@testable import KodizStore

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
}
