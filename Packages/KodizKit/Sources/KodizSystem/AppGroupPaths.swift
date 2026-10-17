import Foundation
import KodizBridgeProtocol

public enum AppGroupPaths {
    public static let groupIdentifier = "dev.kodiz.DownloadManager"

    /// Returns the App Group container URL if available, otherwise falls back to Application Support
    public static var sharedContainerURL: URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            return container
        }

        // Fallback for development without provisioning profile
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Kodiz Download Manager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Socket path for Native Messaging Host & Extension IPC
    public static var bridgeSocketPath: String {
        return (try? BridgeSocketPath.resolveSocketPath()) ?? sharedContainerURL.appendingPathComponent("bridge.sock").path
    }

    /// Tools directory for yt-dlp, ffmpeg, qjs
    public static var toolsDirectoryURL: URL {
        let dir = sharedContainerURL.appendingPathComponent("Tools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
