import SwiftUI
import KodizEngine
import KodizStore

public struct DetailWindowView: View {
    @Bindable public var item: AppDownloadItem

    public init(item: AppDownloadItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Info
            VStack(alignment: .leading, spacing: 6) {
                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(1)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("URL:")
                            .foregroundColor(.secondary)
                        Text(item.url)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    GridRow {
                        Text("Durum:")
                            .foregroundColor(.secondary)
                        HStack {
                            Text(item.status.rawValue.capitalized)
                                .fontWeight(.medium)
                            Spacer()
                            Text("Sürdürme Desteği: Evet (Range)")
                                .foregroundColor(.secondary)
                        }
                    }
                    GridRow {
                        Text("Boyut:")
                            .foregroundColor(.secondary)
                        Text(formatBytes(item.downloadedBytes) + " / " + (item.totalBytes.map(formatBytes) ?? "Bilinmiyor") + " (%\(String(format: "%.1f", item.percentage)))")
                    }
                    GridRow {
                        Text("Hız:")
                            .foregroundColor(.secondary)
                        HStack {
                            Text(formatSpeed(item.speed))
                                .fontWeight(.medium)
                            Spacer()
                            Text("Kalan Süre: \(formatETA(item.etaSeconds))")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .font(.system(size: 12))
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)

            // Segment Bar (IDM style)
            VStack(alignment: .leading, spacing: 4) {
                Text("Bağlantı Parçaları")
                    .font(.subheadline)
                    .fontWeight(.medium)
                SegmentCanvasView(segments: item.segments, totalBytes: item.totalBytes)
            }

            // Segments Table
            Table(item.segments) {
                TableColumn("#") { seg in
                    Text("\(seg.idx + 1)")
                        .monospacedDigit()
                }
                .width(30)

                TableColumn("Aralık") { seg in
                    Text("\(formatBytes(seg.start)) – \(seg.end > 0 ? formatBytes(seg.end) : "...")")
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                .width(140)

                TableColumn("İndirilen") { seg in
                    Text(formatBytes(seg.received))
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                .width(80)

                TableColumn("Durum") { seg in
                    Text(seg.state.rawValue.capitalized)
                        .font(.system(size: 11))
                        .foregroundColor(seg.state == .completed ? .green : .blue)
                }
            }
            .frame(minHeight: 140)

            // Bottom Actions
            HStack {
                Button("Duraklat") {
                    // Pause action
                }
                Button("İptal Et") {
                    // Cancel action
                }
                Spacer()
                Button("Finder'da Göster") {
                    // Reveal file
                }
            }
        }
        .padding(16)
        .frame(minWidth: 550, minHeight: 450)
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
        let remS = s % 60
        return "\(m) dk \(remS) sn"
    }
}
