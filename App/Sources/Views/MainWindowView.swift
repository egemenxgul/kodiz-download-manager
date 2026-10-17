import SwiftUI
import KodizStore
import KodizEngine

public struct MainWindowView: View {
    @State private var items: [AppDownloadItem] = [
        AppDownloadItem(
            fileName: "ubuntu-26.04-desktop-arm64.iso",
            url: "https://cdimage.ubuntu.com/releases/ubuntu-26.04-desktop-arm64.iso",
            totalBytes: 5_820_000_000,
            downloadedBytes: 3_410_000_000,
            speed: 48_200_000,
            status: .downloading,
            category: "archive",
            activeConnections: 8,
            maxConnections: 8,
            segments: [
                Segment(idx: 0, start: 0, end: 745_000_000, received: 745_000_000, state: .completed),
                Segment(idx: 1, start: 745_000_001, end: 1_490_000_000, received: 512_000_000, state: .downloading),
                Segment(idx: 2, start: 1_490_000_001, end: 2_235_000_000, received: 620_000_000, state: .downloading),
                Segment(idx: 3, start: 2_235_000_001, end: 2_980_000_000, received: 745_000_000, state: .completed),
                Segment(idx: 4, start: 2_980_000_001, end: 3_725_000_000, received: 320_000_000, state: .downloading),
                Segment(idx: 5, start: 3_725_000_001, end: 4_470_000_000, received: 210_000_000, state: .downloading),
                Segment(idx: 6, start: 4_470_000_001, end: 5_215_000_000, received: 170_000_000, state: .downloading),
                Segment(idx: 7, start: 5_215_000_001, end: 5_820_000_000, received: 88_000_000, state: .downloading)
            ]
        ),
        AppDownloadItem(
            fileName: "Xcode_27.xip",
            url: "https://developer.apple.com/download/Xcode_27.xip",
            totalBytes: 11_800_000_000,
            downloadedBytes: 1_652_000_000,
            speed: 12_400_000,
            status: .downloading,
            category: "app",
            activeConnections: 6,
            maxConnections: 8
        ),
        AppDownloadItem(
            fileName: "WWDC26_Keynote_1080p.mp4",
            url: "https://youtube.com/watch?v=wwdc2026",
            totalBytes: 2_100_000_000,
            downloadedBytes: 2_100_000_000,
            speed: 0,
            status: .completed,
            category: "video"
        )
    ]

    @State private var selectedFilter: String = "all"
    @State private var selectedItemId: UUID?
    @State private var searchText: String = ""
    @State private var isAddUrlPresented: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var activeDetailItem: AppDownloadItem?

    public init() {}

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
                    Label("Video", systemImage: "film").tag("video")
                    Label("Müzik", systemImage: "music.note").tag("music")
                    Label("Arşiv", systemImage: "archivebox").tag("archive")
                    Label("Uygulama", systemImage: "shippingbox").tag("app")
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
                    Button("Finder'da Göster") {}
                    Divider()
                    Button("Duraklat") {}
                    Button("Sürdür") {}
                    Divider()
                    Button("Listeden Sil") {}
                }

                // Status Bar
                HStack(spacing: 16) {
                    let totalSpeed = items.filter { $0.status == .downloading }.reduce(0.0) { $0 + $1.speed }
                    let activeCount = items.filter { $0.status == .downloading }.count

                    Text("↓ \(formatSpeed(totalSpeed))")
                        .fontWeight(.semibold)
                    Text("· \(activeCount) aktif indirme")
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
                Button(action: {}) {
                    Label("Sürdür", systemImage: "play.fill")
                }
                Button(action: {}) {
                    Label("Duraklat", systemImage: "pause.fill")
                }
                Button(action: {}) {
                    Label("Sil", systemImage: "trash")
                }
                Spacer()
                Button(action: { isSettingsPresented = true }) {
                    Label("Ayarlar", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $isAddUrlPresented) {
            AddUrlView(onStartDownload: { url, conns, dest in
                isAddUrlPresented = false
                let newItem = AppDownloadItem(
                    fileName: url.lastPathComponent,
                    url: url.absoluteString,
                    status: .downloading,
                    activeConnections: conns,
                    maxConnections: conns
                )
                items.insert(newItem, at: 0)
            }, onCancel: {
                isAddUrlPresented = false
            })
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .sheet(item: $activeDetailItem) { item in
            DetailWindowView(item: item)
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
        return String(format: "%.1f MB/s", mb)
    }

    private func formatETA(_ sec: Int?) -> String {
        guard let s = sec else { return "—" }
        if s < 60 { return "\(s) sn" }
        let m = s / 60
        return "\(m) dk"
    }
}
