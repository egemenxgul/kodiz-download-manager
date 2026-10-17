import Foundation
import SafariServices
import AppKit
import os.log
import KodizBridgeProtocol

public final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling, @unchecked Sendable {
    private static let logger = Logger(subsystem: "dev.kodiz.DownloadManager.SafariExtension", category: "Handler")

    public func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo,
              let message = userInfo[SFExtensionMessageKey],
              let reqData = try? JSONSerialization.data(withJSONObject: message) else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        Self.logger.info("Received message from Safari web extension: \(String(describing: message))")

        final class ContextBox: @unchecked Sendable {
            let context: NSExtensionContext
            init(_ context: NSExtensionContext) { self.context = context }
        }
        let box = ContextBox(context)

        Task {
            do {
                let socketPath = try BridgeSocketPath.resolveSocketPath()

                // Check if socket exists; if not, attempt to launch main application
                if !FileManager.default.fileExists(atPath: socketPath) {
                    Self.launchAppInBackground()
                    // Poll for up to 5 seconds
                    for _ in 0..<50 {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        if FileManager.default.fileExists(atPath: socketPath) {
                            break
                        }
                    }
                }

                let client = UnixSocketClient(socketPath: socketPath)
                let resData = try await client.sendRequest(reqData)

                let resObj = (try? JSONSerialization.jsonObject(with: resData)) ?? ["ok": true]

                let response = NSExtensionItem()
                response.userInfo = [SFExtensionMessageKey: resObj]
                box.context.completeRequest(returningItems: [response], completionHandler: nil)
            } catch {
                Self.logger.error("Safari extension forwarding error: \(error.localizedDescription)")
                let response = NSExtensionItem()
                response.userInfo = [SFExtensionMessageKey: ["ok": false, "reason": error.localizedDescription]]
                box.context.completeRequest(returningItems: [response], completionHandler: nil)
            }
        }
    }

    private static func launchAppInBackground() {
        // Find Kodiz Download Manager.app from appex bundle path
        // SafariExtension is at: Kodiz Download Manager.app/Contents/PlugIns/KodizSafari.appex
        guard let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() as URL? else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.arguments = ["--background"]

        NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
    }
}
