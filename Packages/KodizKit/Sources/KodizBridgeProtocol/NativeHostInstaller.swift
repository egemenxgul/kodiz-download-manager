import Foundation
import AppKit

public struct BrowserTarget: Sendable {
    public let name: String
    public let bundleIdentifier: String
    public let manifestDirectoryRelPath: String
    public let isFirefox: Bool
    public let notes: String?

    public init(
        name: String,
        bundleIdentifier: String,
        manifestDirectoryRelPath: String,
        isFirefox: Bool = false,
        notes: String? = nil
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.manifestDirectoryRelPath = manifestDirectoryRelPath
        self.isFirefox = isFirefox
        self.notes = notes
    }
}

public enum NativeHostInstaller: Sendable {
    public static let hostName = "dev.kodiz.dm"
    public static let extensionId = "clcoapdgcnijgajpkdplenikocmfpdfg"
    public static let firefoxExtensionId = "kodiz@kodiz.dev"

    public static let supportedBrowsers: [BrowserTarget] = [
        BrowserTarget(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", manifestDirectoryRelPath: "Google/Chrome/NativeMessagingHosts"),
        BrowserTarget(name: "Google Chrome Canary", bundleIdentifier: "com.google.Chrome.canary", manifestDirectoryRelPath: "Google/Chrome Canary/NativeMessagingHosts"),
        BrowserTarget(name: "Chromium", bundleIdentifier: "org.chromium.Chromium", manifestDirectoryRelPath: "Chromium/NativeMessagingHosts"),
        BrowserTarget(name: "Brave Browser", bundleIdentifier: "com.brave.Browser", manifestDirectoryRelPath: "BraveSoftware/Brave-Browser/NativeMessagingHosts"),
        BrowserTarget(name: "Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac", manifestDirectoryRelPath: "Microsoft Edge/NativeMessagingHosts"),
        // Opera: Resmî dokümantasyon yok (DOĞRULANMADI). Hem Opera hem Chrome yoluna yazılıyor.
        BrowserTarget(name: "Opera", bundleIdentifier: "com.operasoftware.Opera", manifestDirectoryRelPath: "com.operasoftware.Opera/NativeMessagingHosts", notes: "DOĞRULANMADI - Opera Chrome yolunu da arayabilir"),
        // Vivaldi: DOĞRULANMADI. Hem Vivaldi hem Chrome yoluna yazılıyor.
        BrowserTarget(name: "Vivaldi", bundleIdentifier: "com.vivaldi.Vivaldi", manifestDirectoryRelPath: "Vivaldi/NativeMessagingHosts", notes: "DOĞRULANMADI - Vivaldi Chrome yolunu da arayabilir"),
        BrowserTarget(name: "Mozilla Firefox", bundleIdentifier: "org.mozilla.firefox", manifestDirectoryRelPath: "Mozilla/NativeMessagingHosts", isFirefox: true)
    ]

    /// Locates the NMH binary inside the main application bundle or returns a custom path.
    public static func resolveNMHPath() -> String {
        if let helperURL = Bundle.main.url(forAuxiliaryExecutable: "kodiz-nmh") {
            return helperURL.path
        }

        // Direct bundle structure fallback: <Bundle>/Contents/Helpers/kodiz-nmh
        let bundleHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/kodiz-nmh")
        if FileManager.default.fileExists(atPath: bundleHelper.path) {
            return bundleHelper.path
        }

        return "/Applications/Kodiz Download Manager.app/Contents/Helpers/kodiz-nmh"
    }

    /// Checks installed browsers and creates/updates Native Messaging Host manifests.
    @discardableResult
    public static func installManifests(nmhPath: String? = nil) -> [String: Bool] {
        let path = nmhPath ?? resolveNMHPath()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support")
        var results: [String: Bool] = [:]

        for browser in supportedBrowsers {
            // Check if browser is installed via bundle ID (or always write for Chrome/Firefox)
            let isInstalled = isBrowserInstalled(bundleIdentifier: browser.bundleIdentifier)

            let dirURL = appSupport.appendingPathComponent(browser.manifestDirectoryRelPath)
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                let manifestURL = dirURL.appendingPathComponent("\(hostName).json")

                let manifestContent = generateManifest(nmhPath: path, isFirefox: browser.isFirefox)
                try manifestContent.write(to: manifestURL, atomically: true, encoding: .utf8)
                results[browser.name] = true
            } catch {
                results[browser.name] = false
            }
        }

        return results
    }

    public static func isBrowserInstalled(bundleIdentifier: String) -> Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    public static func generateManifest(nmhPath: String, isFirefox: Bool) -> String {
        if isFirefox {
            return """
            {
              "name": "\(hostName)",
              "description": "Kodiz Download Manager Native Messaging Host",
              "path": "\(nmhPath)",
              "type": "stdio",
              "allowed_extensions": [
                "\(firefoxExtensionId)"
              ]
            }
            """
        } else {
            return """
            {
              "name": "\(hostName)",
              "description": "Kodiz Download Manager Native Messaging Host",
              "path": "\(nmhPath)",
              "type": "stdio",
              "allowed_origins": [
                "chrome-extension://\(extensionId)/"
              ]
            }
            """
        }
    }
}
