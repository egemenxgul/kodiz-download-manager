import Foundation
import SafariServices
import os.log
import KodizBridgeProtocol

public final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let logger = Logger(subsystem: "dev.kodiz.DownloadManager.SafariExtension", category: "Handler")

    public func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo,
              let message = userInfo[SFExtensionMessageKey] else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        logger.info("Received message from Safari web extension: \(String(describing: message))")

        // Bridge request will forward to unix socket in App Group container
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["status": "ok", "source": "KodizSafari"]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
