import Foundation
import KodizBridgeProtocol

// Native Messaging Host CLI: stdio JSON framing -> Unix domain socket in App Group container
let host = NativeMessagingHost()
await host.run()
