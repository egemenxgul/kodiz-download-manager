import SwiftUI
import AppKit
import KodizEngine

public struct AddUrlView: View {
    @State private var urlString: String = ""
    @State private var isProbing: Bool = false
    @State private var probeResult: ProbeResult?
    @State private var connections: Int = 8
    @State private var destDir: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    @State private var errorMessage: String?

    public var onStartDownload: ((URL, Int, URL) -> Void)?
    public var onCancel: (() -> Void)?

    public init(onStartDownload: ((URL, Int, URL) -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.onStartDownload = onStartDownload
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Yeni İndirme Ekle")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("İndirme Adresi (URL):")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    TextField("https://...", text: $urlString)
                        .textFieldStyle(.roundedBorder)

                    Button("Probe Et") {
                        Task { await probeURL() }
                    }
                    .disabled(urlString.isEmpty || isProbing)
                }
            }

            if isProbing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Sunucu bilgisi alınıyor...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let result = probeResult {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dosya Adı: \(result.suggestedFileName)")
                        .fontWeight(.medium)

                    HStack(spacing: 16) {
                        Text("Boyut: \(result.totalBytes.map(formatBytes) ?? "Bilinmiyor")")
                        Text(result.supportsRange ? "✓ Sürdürme Destekleniyor" : "⚠ Sürdürme Yok")
                            .foregroundColor(result.supportsRange ? .green : .orange)
                    }
                    .font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Text("Bağlantı Sayısı:")
                    .font(.caption)
                Picker("", selection: $connections) {
                    ForEach([1, 2, 4, 8, 12, 16], id: \.self) { c in
                        Text("\(c)").tag(c)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            HStack {
                Text("Hedef:")
                    .font(.caption)
                Text(destDir.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Seç...") {
                    selectFolder()
                }
            }

            Divider()

            HStack {
                Button("İptal") {
                    onCancel?()
                }
                Spacer()
                Button("Hemen Başlat") {
                    guard let url = URL(string: urlString) else { return }
                    onStartDownload?(url, connections, destDir)
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlString.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            checkClipboard()
        }
    }

    private func checkClipboard() {
        if let clipboard = NSPasteboard.general.string(forType: .string),
           let url = URL(string: clipboard),
           url.scheme == "http" || url.scheme == "https" {
            urlString = clipboard
            Task { await probeURL() }
        }
    }

    private func probeURL() async {
        guard let url = URL(string: urlString) else { return }
        isProbing = true
        errorMessage = nil
        do {
            let probe = DownloadProbe()
            let result = try await probe.probe(url: url)
            self.probeResult = result
        } catch {
            self.errorMessage = "Bağlantı hatası: \(error.localizedDescription)"
        }
        isProbing = false
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            destDir = url
        }
    }

    private func formatBytes(_ b: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: b)
    }
}
