import SwiftUI
import AppKit
import KodizBridgeProtocol
import KodizSystem
import KodizStore

@main
struct KodizApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var activeDownloads: [AppDownloadItem] = [
        AppDownloadItem(
            fileName: "ubuntu-26.04-desktop-arm64.iso",
            url: "https://cdimage.ubuntu.com/releases/ubuntu-26.04-desktop-arm64.iso",
            totalBytes: 5_820_000_000,
            downloadedBytes: 3_410_000_000,
            speed: 48_200_000,
            status: .downloading
        ),
        AppDownloadItem(
            fileName: "Xcode_27.xip",
            url: "https://developer.apple.com/download/Xcode_27.xip",
            totalBytes: 11_800_000_000,
            downloadedBytes: 1_652_000_000,
            speed: 12_400_000,
            status: .downloading
        )
    ]

    var body: some Scene {
        // Menu Bar Popover
        MenuBarExtra("Kodiz", systemImage: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Kodiz Download Manager")
                        .font(.headline)
                    Spacer()
                    let activeCount = activeDownloads.filter { $0.status == .downloading }.count
                    Text("\(activeCount) aktif")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                if activeDownloads.isEmpty {
                    Text("Aktif indirme yok")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(activeDownloads.prefix(4)) { item in
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
                                Button(action: {}) {
                                    Image(systemName: "pause.fill")
                                        .font(.caption2)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 2)
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
            .frame(width: 280)
        }
        .menuBarExtraStyle(.window)

        // Main App Window
        Window("Kodiz Download Manager", id: "main") {
            MainWindowView()
        }
        .defaultSize(width: 950, height: 620)
    }

    private func formatSpeed(_ s: Double) -> String {
        let mb = s / (1024 * 1024)
        return String(format: "%.1f MB/s", mb)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, BridgeServerDelegate, @unchecked Sendable {
    private var bridgeServer: BridgeServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start Bridge Server for browser extensions IPC
        let socketPath = AppGroupPaths.bridgeSocketPath
        let server = BridgeServer(socketPath: socketPath, delegate: self)
        do {
            try server.start()
            self.bridgeServer = server
        } catch {
            print("Failed to start IPC BridgeServer: \(error)")
        }

        // Show main window on first launch
        showMainWindow()
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
            // Forward to download manager
            return BridgeResponse(id: message.id, ok: true, downloadId: UUID().uuidString)
        }
        return BridgeResponse(id: message.id, ok: true)
    }
}
