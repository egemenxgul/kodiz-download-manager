import Foundation
import Darwin

public enum FileMetadata {
    /// Applies com.apple.quarantine attribute so Gatekeeper inspects downloaded executables
    public static func applyQuarantine(to fileURL: URL, agentName: String = "Kodiz Download Manager") {
        let timestamp = String(format: "%08x", Int(Date().timeIntervalSince1970))
        let uuid = UUID().uuidString
        // Format: 0081;<hex timestamp>;<agentName>;<uuid>
        let quarantineValue = "0081;\(timestamp);\(agentName);\(uuid)"
        setExtendedAttribute(name: "com.apple.quarantine", value: quarantineValue, fileURL: fileURL)
    }

    /// Applies com.apple.metadata:kMDItemWhereFroms plist attribute ([URL, Referer])
    public static func applyWhereFroms(to fileURL: URL, originalURL: String, referer: String?) {
        var sources: [String] = [originalURL]
        if let ref = referer, !ref.isEmpty {
            sources.append(ref)
        }

        if let plistData = try? PropertyListSerialization.data(fromPropertyList: sources, format: .binary, options: 0) {
            setExtendedAttributeData(name: "com.apple.metadata:kMDItemWhereFroms", data: plistData, fileURL: fileURL)
        }
    }

    /// Triggers Dock's Downloads stack bounce animation via distributed notification
    public static func notifyDockDownloadsBounce(fileURL: URL) {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.DownloadFileFinished"),
            object: fileURL.path,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private static func setExtendedAttribute(name: String, value: String, fileURL: URL) {
        guard let data = value.data(using: .utf8) else { return }
        setExtendedAttributeData(name: name, data: data, fileURL: fileURL)
    }

    private static func setExtendedAttributeData(name: String, data: Data, fileURL: URL) {
        let path = fileURL.path
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            _ = setxattr(path, name, baseAddress, data.count, 0, 0)
        }
    }
}
