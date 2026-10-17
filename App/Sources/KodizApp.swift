import SwiftUI
import AppKit
import KodizBridgeProtocol
import KodizSystem
import KodizStore
import KodizEngine

@main
struct KodizApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var downloadManager = DownloadManager.shared

    var body: some Scene {
        // Menu Bar Popover
        MenuBarExtra("Kodiz", systemImage: downloadManager.activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Kodiz Download Manager")
                        .font(.headline)
                    Spacer()
                    Text("\(downloadManager.activeCount) aktif")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                let activeItems = downloadManager.items.filter { $0.status == .downloading || $0.status == .queued }
                if activeItems.isEmpty {
                    Text("Aktif indirme yok")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(activeItems.prefix(5)) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.fileName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)

                            ProgressView(value: item.percentage, total: 100)

                            HStack {
                                Text("%\(String(format: "%.0f", item.percentage)) · \(formatSpeed(item.speed))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if item.status == .downloading {
                                    Button(action: {
                                        Task { await downloadManager.pauseDownload(id: item.id) }
                                    }) {
                                        Image(systemName: "pause.fill")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.borderless)
                                } else {
                                    Button(action: {
                                        Task { await downloadManager.resumeDownload(id: item.id) }
                                    }) {
                                        Image(systemName: "play.fill")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()

                HStack {
                    Text("↓ \(formatSpeed(downloadManager.totalSpeed))")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    if downloadManager.activeCount > 0 {
                        Button("Tümünü Duraklat") {
                            Task { await downloadManager.pauseAll() }
                        }
                        .font(.caption)
                    }
                }

                Divider()

                HStack {
                    Button("+ URL Ekle") {
                        appDelegate.showMainWindow()
                    }
                    Button("Ana Pencere") {
                        appDelegate.showMainWindow()
                    }
                    Spacer()
                    Button("Çıkış") {
                        NSApp.terminate(nil)
                    }
                }
            }
            .padding(12)
            .frame(width: 300)
        }
        .menuBarExtraStyle(.window)

        // Main App Window
        Window("Kodiz Download Manager", id: "main") {
            MainWindowView()
                .environment(downloadManager)
        }
        .defaultSize(width: 950, height: 620)
    }

    private func formatSpeed(_ s: Double) -> String {
        let mb = s / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f MB/s", mb)
        }
        let kb = s / 1024
        return String(format: "%.0f KB/s", kb)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, BridgeServerDelegate, @unchecked Sendable {
    private var bridgeServer: BridgeServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install or repair browser Native Messaging Host manifests
        NativeHostInstaller.installManifests()

        // Start Bridge Server for browser extensions IPC
        let socketPath = AppGroupPaths.bridgeSocketPath
        let server = BridgeServer(socketPath: socketPath, delegate: self)
        do {
            try server.start()
            self.bridgeServer = server
        } catch {
            print("Failed to start IPC BridgeServer: \(error)")
        }

        // Show window only on very first launch; subsequent launches stay in menu bar
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            showMainWindow()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSApp.setActivationPolicy(.accessory)
        return false // Keep running in menu bar!
    }

    // BridgeServerDelegate
    func handleBridgeMessage(_ message: BridgeMessage) async -> BridgeResponse {
        print("Received IPC message from browser: \(message.type)")
        if message.type == "download.add" {
            guard let urlString = message.payload?.url, let url = URL(string: urlString) else {
                return BridgeResponse(id: message.id, ok: false, reason: "Invalid or missing URL")
            }

            do {
                let cookies = message.payload?.cookies?.compactMap { c -> HTTPCookie? in
                    var props: [HTTPCookiePropertyKey: Any] = [
                        .name: c.name,
                        .value: c.value,
                        .domain: c.domain ?? "",
                        .path: c.path ?? "/"
                    ]
                    if c.secure == true { props[.secure] = "TRUE" }
                    return HTTPCookie(properties: props)
                }

                let requestCookies = cookies?.map { DownloadRequestCookie(from: $0) } ?? []
                let options = DownloadRequestOptions(
                    userAgent: message.payload?.userAgent,
                    referer: message.payload?.referrer,
                    cookies: requestCookies,
                    extraHeaders: message.payload?.extraHeaders ?? [:]
                )

                let downloadId = try await DownloadManager.shared.addDownload(
                    url: url,
                    preferredFileName: message.payload?.fileNameHint,
                    cookies: cookies,
                    options: options
                )

                return BridgeResponse(id: message.id, ok: true, downloadId: downloadId.uuidString)
            } catch {
                return BridgeResponse(id: message.id, ok: false, reason: error.localizedDescription)
            }
        }
        return BridgeResponse(id: message.id, ok: true)
    }
}
