import Foundation
import SwiftUI
import AppKit
import KodizEngine
import KodizStore
import KodizSystem

@Observable
@MainActor
public final class DownloadManager: Sendable {
    public static let shared = DownloadManager()

    public var items: [AppDownloadItem] = []
    public var maxConcurrentDownloads: Int = 4
    public var defaultConnections: Int = 8

    public var totalSpeed: Double {
        items.filter { $0.status == .downloading }.reduce(0.0) { $0 + $1.speed }
    }

    public var activeCount: Int {
        items.filter { $0.status == .downloading }.count
    }

    private let db: KodizDatabase
    private var engines: [UUID: DownloadEngine] = [:]
    private var engineTasks: [UUID: Task<Void, Never>] = [:]

    public init(database: KodizDatabase? = nil) {
        if let customDB = database {
            self.db = customDB
        } else {
            do {
                self.db = try KodizDatabase()
            } catch {
                fatalError("Failed to initialize KodizDatabase: \(error)")
            }
        }

        loadFromDatabase()
        setupNetworkObserver()
    }

    // MARK: - Database Load

    public func loadFromDatabase() {
        do {
            let records = try db.fetchAllDownloads()
            var loadedItems: [AppDownloadItem] = []

            for rec in records {
                var status = rec.status
                // Unfinished downloads at app launch become paused
                if status == .downloading || status == .probing || status == .waitingNetwork || status == .merging {
                    status = .paused
                    try? db.updateDownloadStatus(id: rec.id, status: .paused)
                }

                let segs = (try? db.fetchEngineSegments(for: rec.id)) ?? []

                let item = AppDownloadItem(
                    id: rec.id,
                    fileName: rec.fileName,
                    url: rec.url,
                    totalBytes: rec.totalBytes,
                    downloadedBytes: rec.downloadedBytes,
                    speed: 0.0,
                    status: status,
                    category: rec.category,
                    activeConnections: 0,
                    maxConnections: rec.maxConnections,
                    segments: segs,
                    createdAt: rec.createdAt
                )
                loadedItems.append(item)
            }

            self.items = loadedItems
        } catch {
            print("Error loading downloads from database: \(error)")
        }
    }

    // MARK: - Network Observer

    private func setupNetworkObserver() {
        NetworkObserver.shared.setDelegate(self)
        NetworkObserver.shared.start()
    }

    // MARK: - Queue Drainage

    public func drainQueue() {
        let currentActive = items.filter { $0.status == .downloading || $0.status == .probing }.count
        guard currentActive < maxConcurrentDownloads else { return }

        let slotsAvailable = maxConcurrentDownloads - currentActive
        let queuedItems = items.filter { $0.status == .queued }

        for item in queuedItems.prefix(slotsAvailable) {
            Task {
                await startDownloading(item: item)
            }
        }

        updateSleepAssertion()
    }

    private func updateSleepAssertion() {
        let isDownloading = items.contains { $0.status == .downloading }
        if isDownloading {
            SleepBlocker.shared.retainSleepAssertion()
        } else {
            SleepBlocker.shared.releaseSleepAssertion()
        }
    }

    // MARK: - Actions

    public func addDownload(
        url: URL,
        connections: Int? = nil,
        destinationDirectory: URL? = nil,
        preferredFileName: String? = nil,
        cookies: [HTTPCookie]? = nil,
        options: DownloadRequestOptions? = nil
    ) async throws -> UUID {
        let id = UUID()
        let conns = connections ?? defaultConnections
        let dest = destinationDirectory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        // Save cookies in Keychain if present
        if let cookies = cookies, !cookies.isEmpty {
            KeychainCookieStore.saveCookies(cookies, for: id)
        }

        // 1. Initial probe
        let probe = DownloadProbe()
        let probeResult = try await probe.probe(url: url, options: options)

        let fileName = preferredFileName ?? probeResult.suggestedFileName
        let tempPath = dest.appendingPathComponent(fileName + ".kodizpart").path
        let category = categorizeFileName(fileName)

        // 2. Persist in database before returning
        let record = DownloadRecord(
            id: id,
            kind: .http,
            url: url.absoluteString,
            finalUrl: probeResult.finalURL.absoluteString,
            referer: options?.referer,
            userAgent: options?.userAgent,
            fileName: fileName,
            destDir: dest.path,
            tempPath: tempPath,
            totalBytes: probeResult.totalBytes,
            downloadedBytes: 0,
            status: .queued,
            category: category,
            queueId: "main",
            priority: 0,
            maxConnections: conns,
            etag: probeResult.etag,
            lastModified: probeResult.lastModified,
            acceptRanges: probeResult.supportsRange,
            mime: probeResult.contentType,
            createdAt: Date()
        )

        try db.saveDownload(record)

        // 3. Create UI item
        let item = AppDownloadItem(
            id: id,
            fileName: fileName,
            url: url.absoluteString,
            totalBytes: probeResult.totalBytes,
            downloadedBytes: 0,
            speed: 0.0,
            status: .queued,
            category: category,
            activeConnections: 0,
            maxConnections: conns,
            segments: [],
            createdAt: Date()
        )

        items.insert(item, at: 0)

        // 4. Trigger queue
        drainQueue()

        return id
    }

    public func pauseDownload(id: UUID) async {
        guard let item = items.first(where: { $0.id == id }) else { return }

        if let engine = engines[id] {
            let pausedSegments = await engine.pause()
            item.segments = pausedSegments
            try? await db.checkpoint(id: id, segments: pausedSegments, downloadedBytes: item.downloadedBytes)
            engines.removeValue(forKey: id)
        }

        engineTasks[id]?.cancel()
        engineTasks.removeValue(forKey: id)

        item.status = .paused
        item.speed = 0.0
        item.activeConnections = 0
        try? db.updateDownloadStatus(id: id, status: .paused)

        drainQueue()
    }

    public func resumeDownload(id: UUID) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.status = .queued
        try? db.updateDownloadStatus(id: id, status: .queued)
        drainQueue()
    }

    public func deleteDownload(id: UUID, deleteFile: Bool = false) async {
        if let engine = engines[id] {
            await engine.cancel()
            engines.removeValue(forKey: id)
        }

        engineTasks[id]?.cancel()
        engineTasks.removeValue(forKey: id)

        if let item = items.first(where: { $0.id == id }) {
            if deleteFile {
                if let destDir = try? db.fetchDownload(id: id)?.destDir {
                    let fileURL = URL(fileURLWithPath: destDir).appendingPathComponent(item.fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                    let tempURL = URL(fileURLWithPath: destDir).appendingPathComponent(item.fileName + ".kodizpart")
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
        }

        KeychainCookieStore.deleteCookies(for: id)
        try? db.deleteDownload(id: id)
        items.removeAll(where: { $0.id == id })

        drainQueue()
    }

    public func pauseAll() async {
        let active = items.filter { $0.status == .downloading || $0.status == .queued }
        for item in active {
            await pauseDownload(id: item.id)
        }
    }

    public func resumeAll() async {
        let paused = items.filter { $0.status == .paused || $0.status == .waitingNetwork }
        for item in paused {
            await resumeDownload(id: item.id)
        }
    }

    public func revealInFinder(id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              let record = try? db.fetchDownload(id: id) else { return }

        let dest = URL(fileURLWithPath: record.destDir)
        let fileURL = dest.appendingPathComponent(item.fileName)
        let targetURL = FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : dest
        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
    }

    public func openFile(id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              let record = try? db.fetchDownload(id: id) else { return }

        let fileURL = URL(fileURLWithPath: record.destDir).appendingPathComponent(item.fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.open(fileURL)
        }
    }

    public func copyURL(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url, forType: .string)
    }

    // MARK: - Engine Execution

    private func startDownloading(item: AppDownloadItem) async {
        guard let url = URL(string: item.url),
              let record = try? db.fetchDownload(id: item.id) else {
            item.status = .failed
            return
        }

        item.status = .downloading
        try? db.updateDownloadStatus(id: item.id, status: .downloading)
        updateSleepAssertion()

        let cookies = KeychainCookieStore.loadCookies(for: item.id)
        let requestCookies = cookies.map { DownloadRequestCookie(from: $0) }
        let options = DownloadRequestOptions(
            userAgent: record.userAgent,
            referer: record.referer,
            cookies: requestCookies
        )

        let observer = DownloadItemEngineObserver(downloadId: item.id, manager: self)
        let destURL = URL(fileURLWithPath: record.destDir)

        let engine = DownloadEngine(
            url: url,
            destinationDirectory: destURL,
            preferredFileName: item.fileName,
            savedETag: record.etag,
            options: options,
            delegate: observer,
            checkpointSink: db
        )

        self.engines[item.id] = engine

        let savedSegments = (try? db.fetchEngineSegments(for: item.id)) ?? []

        let task = Task {
            do {
                try await engine.start(
                    connections: item.maxConnections,
                    existingSegments: savedSegments.isEmpty ? nil : savedSegments,
                    savedETag: record.etag
                )
            } catch {
                if !Task.isCancelled {
                    await self.handleEngineFailure(id: item.id, error: error)
                }
            }
        }

        self.engineTasks[item.id] = task
    }

    // MARK: - Engine Callbacks

    func handleEngineProgress(
        id: UUID,
        downloadedBytes: Int64,
        totalBytes: Int64?,
        speed: Double,
        segments: [Segment]
    ) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.downloadedBytes = downloadedBytes
        if let total = totalBytes {
            item.totalBytes = total
        }
        item.speed = speed
        item.segments = segments
        item.activeConnections = segments.filter { $0.state == .downloading }.count
    }

    func handleEngineCompletion(id: UUID, finalURL: URL) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.status = .completed
        item.speed = 0.0
        item.activeConnections = 0
        if let total = item.totalBytes {
            item.downloadedBytes = total
        }

        // Apply macOS file metadata
        FileMetadata.applyQuarantine(to: finalURL, agentName: "Kodiz Download Manager")
        let record = try? db.fetchDownload(id: id)
        FileMetadata.applyWhereFroms(to: finalURL, originalURL: item.url, referer: record?.referer)
        FileMetadata.notifyDockDownloadsBounce(fileURL: finalURL)

        // Clean up Keychain cookies
        KeychainCookieStore.deleteCookies(for: id)

        // Update database
        try? db.updateDownloadProgress(id: id, downloadedBytes: item.downloadedBytes, status: .completed)

        engines.removeValue(forKey: id)
        engineTasks.removeValue(forKey: id)

        drainQueue()
    }

    func handleEngineFailure(id: UUID, error: Error) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.status = .failed
        item.speed = 0.0
        item.activeConnections = 0

        try? db.updateDownloadStatus(id: id, status: .failed)

        engines.removeValue(forKey: id)
        engineTasks.removeValue(forKey: id)

        drainQueue()
    }

    private func categorizeFileName(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "mov", "avi", "webm", "m4v", "flv", "wmv", "mpg", "mpeg", "3gp", "ts":
            return "video"
        case "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "wma", "aiff", "alac":
            return "music"
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "zst", "iso":
            return "archive"
        case "dmg", "pkg", "mpkg", "ipa", "exe", "msi", "apk", "deb", "rpm", "appimage":
            return "app"
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "svg", "bmp", "tiff", "avif", "raw":
            return "image"
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "epub":
            return "document"
        default:
            return "other"
        }
    }
}

// MARK: - NetworkObserverDelegate Conformance

extension DownloadManager: NetworkObserverDelegate {
    public nonisolated func networkStatusDidChange(to status: NetworkStatus) async {
        await MainActor.run {
            switch status {
            case .disconnected:
                for item in self.items where item.status == .downloading {
                    Task {
                        await self.pauseDownload(id: item.id)
                        item.status = .waitingNetwork
                        try? self.db.updateDownloadStatus(id: item.id, status: .waitingNetwork)
                    }
                }
            case .connected:
                for item in self.items where item.status == .waitingNetwork {
                    Task {
                        await self.resumeDownload(id: item.id)
                    }
                }
            }
        }
    }
}

// MARK: - DownloadEngineDelegate Observer Bridge

private final class DownloadItemEngineObserver: DownloadEngineDelegate, @unchecked Sendable {
    private let downloadId: UUID
    private weak var manager: DownloadManager?

    init(downloadId: UUID, manager: DownloadManager) {
        self.downloadId = downloadId
        self.manager = manager
    }

    func downloadDidUpdateProgress(_ progress: DownloadProgress) async {
        await MainActor.run {
            manager?.handleEngineProgress(
                id: downloadId,
                downloadedBytes: progress.downloadedBytes,
                totalBytes: progress.totalBytes,
                speed: progress.speed,
                segments: progress.segments
            )
        }
    }

    func downloadDidComplete(finalURL: URL) async {
        await MainActor.run {
            manager?.handleEngineCompletion(id: downloadId, finalURL: finalURL)
        }
    }

    func downloadDidFail(error: Error) async {
        await MainActor.run {
            manager?.handleEngineFailure(id: downloadId, error: error)
        }
    }
}
