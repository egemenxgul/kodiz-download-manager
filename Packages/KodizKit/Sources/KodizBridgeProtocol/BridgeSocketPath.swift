import Foundation

public enum BridgeSocketPath: Sendable {
    /// App Group identifier constant.
    /// Note: docs/PLAN.md recommends <TEAMID>.dev.kodiz.DownloadManager prefix once Team ID is assigned by the owner.
    public static let groupIdentifier = "dev.kodiz.DownloadManager"

    /// Unified function to resolve the bridge socket path for main app, NMH, and Safari extension.
    /// Verifies POSIX sun_path 104-byte limit.
    public static func resolveSocketPath() throws -> String {
        let dirPath: String
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            dirPath = containerURL.path
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("Kodiz Download Manager", isDirectory: true)
            dirPath = dir.path
        }

        try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])

        let socketPath = (dirPath as NSString).appendingPathComponent("bridge.sock")

        // Check sun_path max length (104 bytes in Darwin)
        let addr = sockaddr_un()
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard socketPath.utf8.count < maxLen else {
            throw POSIXError(.ENAMETOOLONG)
        }

        return socketPath
    }
}
