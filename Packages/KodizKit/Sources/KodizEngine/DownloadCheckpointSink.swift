import Foundation

/// Protocol for persistence sinks to record download progress.
/// Ensures Engine stays independent of GRDB or persistence layer.
/// In accordance with Plan §4.7: fsync(fd) is called BEFORE checkpoint.
public protocol DownloadCheckpointSink: AnyObject, Sendable {
    func checkpoint(id: UUID, segments: [Segment], downloadedBytes: Int64) async throws
}
