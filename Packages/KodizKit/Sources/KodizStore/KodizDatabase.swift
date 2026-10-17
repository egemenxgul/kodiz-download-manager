import Foundation
import GRDB
import KodizEngine

public final class KodizDatabase: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(inMemory: Bool = false, path: String? = nil) throws {
        if inMemory {
            self.dbQueue = try DatabaseQueue()
        } else {
            let dbPath: String
            if let customPath = path {
                dbPath = customPath
            } else {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let dir = appSupport.appendingPathComponent("Kodiz Download Manager", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                dbPath = dir.appendingPathComponent("kodiz.sqlite").path
            }

            var config = Configuration()
            config.qos = .userInitiated
            // WAL mode
            config.defaultTransactionKind = .deferred

            self.dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
        }

        try migrator.migrate(dbQueue)
    }

    public var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: DownloadRecord.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("url", .text).notNull()
                t.column("finalUrl", .text)
                t.column("pageUrl", .text)
                t.column("referer", .text)
                t.column("userAgent", .text)
                t.column("extraHeaders", .text)
                t.column("fileName", .text).notNull()
                t.column("destDir", .text).notNull()
                t.column("tempPath", .text).notNull()
                t.column("totalBytes", .integer)
                t.column("downloadedBytes", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull().defaults(to: DownloadStatus.queued.rawValue)
                t.column("category", .text).notNull().defaults(to: "other")
                t.column("queueId", .text).defaults(to: "main")
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("maxConnections", .integer).notNull().defaults(to: 8)
                t.column("speedLimit", .integer)
                t.column("etag", .text)
                t.column("lastModified", .text)
                t.column("acceptRanges", .boolean).notNull().defaults(to: true)
                t.column("mime", .text)
                t.column("sha256", .text)
                t.column("errorCode", .integer)
                t.column("errorMessage", .text)
                t.column("mediaOptions", .text)
                t.column("parentId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("completedAt", .datetime)
            }

            try db.create(table: SegmentRecord.databaseTableName) { t in
                t.column("downloadId", .text).notNull().references(DownloadRecord.databaseTableName, onDelete: .cascade)
                t.column("idx", .integer).notNull()
                t.column("start", .integer).notNull()
                t.column("end", .integer).notNull()
                t.column("received", .integer).notNull().defaults(to: 0)
                t.column("state", .text).notNull().defaults(to: "pending")
                t.primaryKey(["downloadId", "idx"])
            }

            try db.create(table: QueueRecord.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("maxConcurrent", .integer).notNull().defaults(to: 4)
                t.column("schedule", .text)
                t.column("sort", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: HostProfileRecord.databaseTableName) { t in
                t.column("host", .text).primaryKey()
                t.column("learnedMaxConnections", .integer).notNull().defaults(to: 8)
                t.column("supportsRange", .boolean).notNull().defaults(to: true)
                t.column("lastSeen", .datetime).notNull()
            }

            try db.create(table: CategoryRecord.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("extensions", .text).notNull()
                t.column("mimePrefixes", .text).notNull()
                t.column("folder", .text)
                t.column("icon", .text).notNull()
                t.column("sort", .integer).notNull().defaults(to: 0)
                t.column("capture", .boolean).notNull().defaults(to: true)
            }

            // Seed default queues
            try db.execute(sql: """
                INSERT INTO queues (id, name, maxConcurrent, sort) VALUES
                ('main', 'Ana Kuyruk', 4, 0),
                ('night', 'Gece Kuyruğu', 2, 1);
            """)

            // Seed default categories according to PLAN.md §9
            try db.execute(sql: """
                INSERT INTO categories (id, name, extensions, mimePrefixes, icon, sort, capture) VALUES
                ('video', 'Video', '["mp4","mkv","mov","avi","webm","m4v","flv","wmv","mpg","mpeg","3gp","ts"]', '["video/"]', 'film', 0, 1),
                ('music', 'Müzik', '["mp3","m4a","aac","flac","wav","ogg","opus","wma","aiff","alac"]', '["audio/"]', 'music.note', 1, 1),
                ('archive', 'Arşiv', '["zip","rar","7z","tar","gz","bz2","xz","tgz","zst","iso"]', '["application/zip","application/x-tar","application/x-rar"]', 'archivebox', 2, 1),
                ('app', 'Uygulama', '["dmg","pkg","mpkg","ipa","exe","msi","apk","deb","rpm","appimage"]', '["application/x-apple-diskimage"]', 'shippingbox', 3, 1),
                ('image', 'Resim', '["jpg","jpeg","png","gif","webp","heic","heif","svg","bmp","tiff","avif","raw"]', '["image/"]', 'photo', 4, 0),
                ('document', 'Belge', '["pdf","doc","docx","xls","xlsx","ppt","pptx","pages","numbers","key","txt","rtf","epub","odt","csv"]', '["text/","application/pdf"]', 'doc.text', 5, 0),
                ('other', 'Diğer', '[]', '[]', 'ellipsis', 6, 0);
            """)
        }

        return migrator
    }

    // Repository operations
    public func saveDownload(_ download: DownloadRecord) throws {
        try dbQueue.write { db in
            try download.save(db)
        }
    }

    public func fetchAllDownloads() throws -> [DownloadRecord] {
        try dbQueue.read { db in
            try DownloadRecord.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    public func fetchDownload(id: UUID) throws -> DownloadRecord? {
        try dbQueue.read { db in
            try DownloadRecord.fetchOne(db, key: id)
        }
    }

    public func updateDownloadProgress(id: UUID, downloadedBytes: Int64, status: DownloadStatus) throws {
        try dbQueue.write { db in
            if var record = try DownloadRecord.fetchOne(db, key: id) {
                record.downloadedBytes = downloadedBytes
                record.status = status
                try record.update(db)
            }
        }
    }

    public func updateDownloadStatus(id: UUID, status: DownloadStatus) throws {
        try dbQueue.write { db in
            if var record = try DownloadRecord.fetchOne(db, key: id) {
                record.status = status
                try record.update(db)
            }
        }
    }

    public func updateDownloadDetails(id: UUID, totalBytes: Int64?, fileName: String?, etag: String?, mime: String?) throws {
        try dbQueue.write { db in
            if var record = try DownloadRecord.fetchOne(db, key: id) {
                if let tb = totalBytes { record.totalBytes = tb }
                if let fn = fileName { record.fileName = fn }
                if let et = etag { record.etag = et }
                if let mi = mime { record.mime = mi }
                try record.update(db)
            }
        }
    }

    public func deleteDownload(id: UUID) throws {
        try dbQueue.write { db in
            _ = try SegmentRecord.filter(Column("downloadId") == id).deleteAll(db)
            _ = try DownloadRecord.deleteOne(db, key: id)
        }
    }

    public func saveSegments(_ segments: [SegmentRecord]) throws {
        try dbQueue.write { db in
            for seg in segments {
                try seg.save(db)
            }
        }
    }

    public func fetchSegments(for downloadId: UUID) throws -> [SegmentRecord] {
        try dbQueue.read { db in
            try SegmentRecord.filter(Column("downloadId") == downloadId).order(Column("idx").asc).fetchAll(db)
        }
    }

    public func fetchEngineSegments(for downloadId: UUID) throws -> [Segment] {
        let records = try fetchSegments(for: downloadId)
        return records.map { rec in
            let st: SegmentState
            switch rec.state {
            case "downloading": st = .downloading
            case "completed": st = .completed
            case "failed": st = .failed
            default: st = .pending
            }
            return Segment(idx: rec.idx, start: rec.start, end: rec.end, received: rec.received, state: st)
        }
    }
}

// MARK: - DownloadCheckpointSink Conformance

extension KodizDatabase: DownloadCheckpointSink {
    public func checkpoint(id: UUID, segments: [Segment], downloadedBytes: Int64) async throws {
        try await dbQueue.write { db in
            if var record = try DownloadRecord.fetchOne(db, key: id) {
                record.downloadedBytes = downloadedBytes
                try record.update(db)
            }
            for seg in segments {
                let rec = SegmentRecord(
                    downloadId: id,
                    idx: seg.idx,
                    start: seg.start,
                    end: seg.end,
                    received: seg.received,
                    state: seg.state.rawValue
                )
                try rec.save(db)
            }
        }
    }
}
