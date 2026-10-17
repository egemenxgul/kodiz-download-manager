import Foundation
import SwiftUI
import KodizStore
import KodizEngine

@Observable
@MainActor
public final class AppDownloadItem: Identifiable {
    public let id: UUID
    public var fileName: String
    public var url: String
    public var totalBytes: Int64?
    public var downloadedBytes: Int64
    public var speed: Double
    public var status: DownloadStatus
    public var category: String
    public var activeConnections: Int
    public var maxConnections: Int
    public var segments: [Segment]
    public var createdAt: Date
    public var sourceSite: String

    public var percentage: Double {
        guard let total = totalBytes, total > 0 else { return 0.0 }
        return min(100.0, (Double(downloadedBytes) / Double(total)) * 100.0)
    }

    public var etaSeconds: Int? {
        guard speed > 0, let total = totalBytes, total > downloadedBytes else { return nil }
        let remaining = total - downloadedBytes
        return Int(Double(remaining) / speed)
    }

    public init(
        id: UUID = UUID(),
        fileName: String,
        url: String,
        totalBytes: Int64? = nil,
        downloadedBytes: Int64 = 0,
        speed: Double = 0.0,
        status: DownloadStatus = .downloading,
        category: String = "video",
        activeConnections: Int = 8,
        maxConnections: Int = 8,
        segments: [Segment] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.speed = speed
        self.status = status
        self.category = category
        self.activeConnections = activeConnections
        self.maxConnections = maxConnections
        self.segments = segments
        self.createdAt = createdAt
        self.sourceSite = URL(string: url)?.host ?? ""
    }
}
