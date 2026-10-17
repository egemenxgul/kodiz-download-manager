import Foundation
import GRDB

public enum DownloadKind: String, Codable, Sendable, DatabaseValueConvertible {
    case http
    case media
}

public enum DownloadStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case queued
    case probing
    case downloading
    case paused
    case waitingNetwork
    case merging
    case completed
    case failed
    case canceled
}

public struct DownloadRecord: Codable, Sendable, FetchableRecord, PersistableRecord, TableRecord, Identifiable {
    public static let databaseTableName = "downloads"

    public var id: UUID
    public var kind: DownloadKind
    public var url: String
    public var finalUrl: String?
    public var pageUrl: String?
    public var referer: String?
    public var userAgent: String?
    public var extraHeaders: String? // JSON string
    public var fileName: String
    public var destDir: String
    public var tempPath: String
    public var totalBytes: Int64?
    public var downloadedBytes: Int64
    public var status: DownloadStatus
    public var category: String
    public var queueId: String?
    public var priority: Int
    public var maxConnections: Int
    public var speedLimit: Int64?
    public var etag: String?
    public var lastModified: String?
    public var acceptRanges: Bool
    public var mime: String?
    public var sha256: String?
    public var errorCode: Int?
    public var errorMessage: String?
    public var mediaOptions: String? // JSON string
    public var parentId: UUID?
    public var createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: DownloadKind = .http,
        url: String,
        finalUrl: String? = nil,
        pageUrl: String? = nil,
        referer: String? = nil,
        userAgent: String? = nil,
        extraHeaders: String? = nil,
        fileName: String,
        destDir: String,
        tempPath: String,
        totalBytes: Int64? = nil,
        downloadedBytes: Int64 = 0,
        status: DownloadStatus = .queued,
        category: String = "other",
        queueId: String? = "main",
        priority: Int = 0,
        maxConnections: Int = 8,
        speedLimit: Int64? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        acceptRanges: Bool = true,
        mime: String? = nil,
        sha256: String? = nil,
        errorCode: Int? = nil,
        errorMessage: String? = nil,
        mediaOptions: String? = nil,
        parentId: UUID? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.finalUrl = finalUrl
        self.pageUrl = pageUrl
        self.referer = referer
        self.userAgent = userAgent
        self.extraHeaders = extraHeaders
        self.fileName = fileName
        self.destDir = destDir
        self.tempPath = tempPath
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.status = status
        self.category = category
        self.queueId = queueId
        self.priority = priority
        self.maxConnections = maxConnections
        self.speedLimit = speedLimit
        self.etag = etag
        self.lastModified = lastModified
        self.acceptRanges = acceptRanges
        self.mime = mime
        self.sha256 = sha256
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.mediaOptions = mediaOptions
        self.parentId = parentId
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public struct SegmentRecord: Codable, Sendable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "segments"

    public var downloadId: UUID
    public var idx: Int
    public var start: Int64
    public var end: Int64
    public var received: Int64
    public var state: String

    public init(downloadId: UUID, idx: Int, start: Int64, end: Int64, received: Int64, state: String) {
        self.downloadId = downloadId
        self.idx = idx
        self.start = start
        self.end = end
        self.received = received
        self.state = state
    }
}

public struct QueueRecord: Codable, Sendable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "queues"

    public var id: String
    public var name: String
    public var maxConcurrent: Int
    public var schedule: String?
    public var sort: Int

    public init(id: String, name: String, maxConcurrent: Int = 4, schedule: String? = nil, sort: Int = 0) {
        self.id = id
        self.name = name
        self.maxConcurrent = maxConcurrent
        self.schedule = schedule
        self.sort = sort
    }
}

public struct HostProfileRecord: Codable, Sendable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "host_profiles"

    public var host: String
    public var learnedMaxConnections: Int
    public var supportsRange: Bool
    public var lastSeen: Date

    public init(host: String, learnedMaxConnections: Int = 8, supportsRange: Bool = true, lastSeen: Date = Date()) {
        self.host = host
        self.learnedMaxConnections = learnedMaxConnections
        self.supportsRange = supportsRange
        self.lastSeen = lastSeen
    }
}

public struct CategoryRecord: Codable, Sendable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "categories"

    public var id: String
    public var name: String
    public var extensions: String // JSON array of extensions
    public var mimePrefixes: String // JSON array of mime prefixes
    public var folder: String?
    public var icon: String
    public var sort: Int
    public var capture: Bool

    public init(id: String, name: String, extensions: String, mimePrefixes: String, folder: String? = nil, icon: String, sort: Int, capture: Bool) {
        self.id = id
        self.name = name
        self.extensions = extensions
        self.mimePrefixes = mimePrefixes
        self.folder = folder
        self.icon = icon
        self.sort = sort
        self.capture = capture
    }
}
