import SwiftUI
import AppKit
import KodizStore
import KodizEngine

public struct MainWindowView: View {
    @Environment(DownloadManager.self) private var downloadManager

    @State private var selectedFilter: String = "all"
    @State private var selectedItemId: UUID?
    @State private var searchText: String = ""
    @State private var isAddUrlPresented: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var activeDetailItem: AppDownloadItem?

    public init() {}

    private var items: [AppDownloadItem] {
        downloadManager.items
    }

    public var filteredItems: [AppDownloadItem] {
        items.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.fileName.localizedCaseInsensitiveContains(searchText) ||
                item.url.localizedCaseInsensitiveContains(searchText)

            if !matchesSearch { return false }

            switch selectedFilter {
            case "downloading": return item.status == .downloading
            case "completed": return item.status == .completed
            case "paused": return item.status == .paused
            case "failed": return item.status == .failed
            case "video": return item.category == "video"
            case "music": return item.category == "music"
            case "archive": return item.category == "archive"
            case "app": return item.category == "app"
            default: return true
            }
        }
    }

    public var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedFilter) {
                Section("İndirmeler") {
                    Label("Tümü", systemImage: "tray.full")
                        .badge(items.count)
                        .tag("all")
                    Label("İndiriliyor", systemImage: "arrow.down.circle")
                        .badge(items.filter { $0.status == .downloading }.count)
                        .tag("downloading")
                    Label("Duraklatıldı", systemImage: "pause.circle")
                        .badge(items.filter { $0.status == .paused }.count)
                        .tag("paused")
                    Label("Tamamlandı", systemImage: "checkmark.circle")
                        .badge(items.filter { $0.status == .completed }.count)
                        .tag("completed")
                    Label("Başarısız", systemImage: "exclamationmark.triangle")
                        .badge(items.filter { $0.status == .failed }.count)
                        .tag("failed")
                }

                Section("Kategoriler") {
                    Label("Video", systemImage: "film")
                        .badge(items.filter { $0.category == "video" }.count)
                        .tag("video")
                    Label("Müzik", systemImage: "music.note")
                        .badge(items.filter { $0.category == "music" }.count)
                        .tag("music")
                    Label("Arşiv", systemImage: "archivebox")
                        .badge(items.filter { $0.category == "archive" }.count)
                        .tag("archive")
                    Label("Uygulama", systemImage: "shippingbox")
                        .badge(items.filter { $0.category == "app" }.count)
                        .tag("app")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            VStack(spacing: 0) {
                // Table
                Table(filteredItems, selection: $selectedItemId) {
                    TableColumn("Dosya Adı") { item in
                        HStack(spacing: 8) {
                            Image(systemName: iconForCategory(item.category))
                                .foregroundColor(.accentColor)
                            Text(item.fileName)
                                .fontWeight(.medium)
                        }
                    }
                    .width(min: 180, ideal: 260)

                    TableColumn("Boyut") { item in
                        Text(item.totalBytes.map(formatBytes) ?? "—")
                            .font(.system(size: 12))
                            .monospacedDigit()
                    }
                    .width(75)

                    TableColumn("İlerleme") { item in
                        VStack(alignment: .leading, spacing: 2) {
                            ProgressView(value: item.percentage, total: 100)
                            Text("%\(String(format: "%.1f", item.percentage))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(110)

                    TableColumn("Hız") { item in
                        Text(item.status == .downloading ? formatSpeed(item.speed) : "—")
                            .font(.system(size: 12))
                            .monospacedDigit()
                    }
                    .width(75)

                    TableColumn("Kalan") { item in
                        Text(item.status == .downloading ? formatETA(item.etaSeconds) : "—")
                            .font(.system(size: 12))
                    }
                    .width(65)

                    TableColumn("Bağl.") { item in
                        Text("\(item.activeConnections)/\(item.maxConnections)")
                            .font(.system(size: 12))
                            .monospacedDigit()
                    }
                    .width(50)

                    TableColumn("Durum") { item in
                        Text(item.status.rawValue.capitalized)
                            .font(.system(size: 12))
                            .foregroundColor(statusColor(item.status))
                    }
                    .width(80)
                }
                .contextMenu(forSelectionType: AppDownloadItem.ID.self) { selection in
                    Button("Detayları Göster") {
                        if let id = selection.first, let item = items.first(where: { $0.id == id }) {
                            activeDetailItem = item
                        }
                    }
                    Button("Finder'da Göster") {
                        if let id = selection.first {
                            downloadManager.revealInFinder(id: id)
                        }
                    }
                    Button("Aç") {
                        if let id = selection.first {
                            downloadManager.openFile(id: id)
                        }
                    }
                    Button("URL'yi Kopyala") {
                        if let id = selection.first {
                            downloadManager.copyURL(id: id)
                        }
                    }
                    Divider()
                    Button("Duraklat") {
                        if let id = selection.first {
                            Task { await downloadManager.pauseDownload(id: id) }
                        }
                    }
                    Button("Sürdür") {
                        if let id = selection.first {
                            Task { await downloadManager.resumeDownload(id: id) }
                        }
                    }
                    Divider()
                    Button("Listeden Sil") {
                        if let id = selection.first {
                            Task { await downloadManager.deleteDownload(id: id, deleteFile: false) }
                        }
                    }
                    Button("Dosyayla Birlikte Sil") {
                        if let id = selection.first {
                            Task { await downloadManager.deleteDownload(id: id, deleteFile: true) }
                        }
                    }
                }

                // Status Bar
                HStack(spacing: 16) {
                    Text("↓ \(formatSpeed(downloadManager.totalSpeed))")
                        .fontWeight(.semibold)
                    Text("· \(downloadManager.activeCount) aktif indirme")
                    Spacer()
                    Text("Hız Sınırı: Yok")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.08))
            }
        }
        .searchable(text: $searchText, prompt: "İndirmelerde ara...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { isAddUrlPresented = true }) {
                    Label("URL Ekle", systemImage: "plus")
                }
                Button(action: {
                    if let id = selectedItemId {
                        Task { await downloadManager.resumeDownload(id: id) }
                    }
                }) {
                    Label("Sürdür", systemImage: "play.fill")
                }
                .disabled(selectedItemId == nil)

                Button(action: {
                    if let id = selectedItemId {
                        Task { await downloadManager.pauseDownload(id: id) }
                    }
                }) {
                    Label("Duraklat", systemImage: "pause.fill")
                }
                .disabled(selectedItemId == nil)

                Button(action: {
                    if let id = selectedItemId {
                        Task { await downloadManager.deleteDownload(id: id, deleteFile: false) }
                    }
                }) {
                    Label("Sil", systemImage: "trash")
                }
                .disabled(selectedItemId == nil)

                Spacer()
                Button(action: { isSettingsPresented = true }) {
                    Label("Ayarlar", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $isAddUrlPresented) {
            AddUrlView(onStartDownload: { url, conns, dest in
                isAddUrlPresented = false
                Task {
                    _ = try? await downloadManager.addDownload(
                        url: url,
                        connections: conns,
                        destinationDirectory: dest
                    )
                }
            }, onCancel: {
                isAddUrlPresented = false
            })
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .sheet(item: $activeDetailItem) { item in
            DetailWindowView(item: item)
                .environment(downloadManager)
        }
    }

    private func iconForCategory(_ cat: String) -> String {
        switch cat {
        case "video": return "film"
        case "music": return "music.note"
        case "archive": return "archivebox"
        case "app": return "shippingbox"
        default: return "doc"
        }
    }

    private func statusColor(_ status: DownloadStatus) -> Color {
        switch status {
        case .downloading: return .blue
        case .completed: return .green
        case .paused: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }

    private func formatBytes(_ b: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: b)
    }

    private func formatSpeed(_ s: Double) -> String {
        let mb = s / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f MB/s", mb)
        }
        let kb = s / 1024
        return String(format: "%.0f KB/s", kb)
    }

    private func formatETA(_ sec: Int?) -> String {
        guard let s = sec else { return "—" }
        if s < 60 { return "\(s) sn" }
        let m = s / 60
        return "\(m) dk"
    }
}
